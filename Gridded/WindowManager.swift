//
//  WindowManager.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import ApplicationServices
import CoreGraphics
import Foundation
import Logging
import SwiftUI

struct SnapToCoordinates: Hashable {
  var start: CGPoint
  var end: CGPoint
}

private typealias CGSConnectionID = UInt32
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSDisableUpdate") private func CGSDisableUpdate(_ connection: CGSConnectionID)
@_silgen_name("CGSReenableUpdate") private func CGSReenableUpdate(_ connection: CGSConnectionID)

@Observable class WindowManager {

  static let shared = WindowManager()

  private let logger = Logger(label: "WindowManager")

  private func primaryScreenHeight() -> CGFloat {
    return NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
      ?? NSScreen.main?.frame.height
      ?? 0
  }

  // Returns a debug string for a window: "AppName – WindowTitle @ (x,y,w,h)"
  public func windowDebugDescription(_ window: AXUIElement) -> String {
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)
    let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid:\(pid)"

    var titleRef: AnyObject?
    let title: String
    if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
       let t = titleRef as? String {
      title = t.isEmpty ? "<untitled>" : t
    } else {
      title = "<no title>"
    }

    var posRef: AnyObject?
    var sizeRef: AnyObject?
    var pos = CGPoint.zero
    var size = CGSize.zero
    if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
       let v = posRef { AXValueGetValue(v as! AXValue, .cgPoint, &pos) }
    if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
       let v = sizeRef { AXValueGetValue(v as! AXValue, .cgSize, &size) }

    return "\(appName) – \"\(title)\" @ (\(Int(pos.x)),\(Int(pos.y)) \(Int(size.width))×\(Int(size.height)))"
  }

  // Returns the frontmost (active) window of the currently focused application.
  public func getFrontmostWindow() -> AXUIElement? {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      logger.notice("getFrontmostWindow: failed to get frontmost application")
      return nil
    }

    let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

    var window: AnyObject?
    let result = AXUIElementCopyAttributeValue(
      appElement, kAXFocusedWindowAttribute as CFString, &window)

    if result == .success, let windowElement = window {
      let w = windowElement as! AXUIElement
      logger.debug("getFrontmostWindow: \(windowDebugDescription(w))")
      return w
    }

    logger.notice("getFrontmostWindow: failed for app \(frontmostApp.localizedName ?? "unknown"), error=\(result.rawValue)")
    return nil
  }

  public func getWindowAtPoint(_ point: CGPoint) -> AXUIElement? {
    let systemWideElement = AXUIElementCreateSystemWide()
    var hitElementRef: AXUIElement?

    // NSEvent.mouseLocation uses AppKit coords (origin bottom-left, y up).
    // AXUIElementCopyElementAtPosition uses CG/AX coords (origin top-left, y down).
    let cgY = primaryScreenHeight() - point.y
    let hitResult = AXUIElementCopyElementAtPosition(
      systemWideElement,
      Float(point.x),
      Float(cgY),
      &hitElementRef
    )

    logger.debug("getWindowAtPoint: AppKit(\(point.x), \(point.y)) → CG(\(point.x), \(cgY)), AX result=\(hitResult.rawValue)")

    guard hitResult == .success, let hitElementRef else {
      logger.debug("getWindowAtPoint: hit-test failed (result=\(hitResult.rawValue)) → returning nil")
      return nil
    }

    var hitRole = "<unknown>"
    var roleRef: AnyObject?
    if AXUIElementCopyAttributeValue(hitElementRef, kAXRoleAttribute as CFString, &roleRef) == .success {
      hitRole = (roleRef as? String) ?? "<unknown>"
    }
    logger.debug("getWindowAtPoint: hit element role=\(hitRole)")

    if let window = resolveWindowElement(from: hitElementRef) {
      logger.debug("getWindowAtPoint: resolved window → \(windowDebugDescription(window))")
      return window
    }

    logger.debug("getWindowAtPoint: could not resolve AXWindow from hit element → returning nil")
    return nil
  }

  public func getWindowFrame(window: AXUIElement) -> CGRect? {
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)

    // Some apps only expose reliable AX frame attributes with enhanced UI mode enabled.
    let appRef = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

    var position = CGPoint.zero
    var size = CGSize.zero

    // Prefer AXFrame when available; some apps expose this more reliably than position+size.
    var frameValueRef: AnyObject?
    if AXUIElementCopyAttributeValue(window, "AXFrame" as CFString, &frameValueRef) == .success,
       let frameValueRef,
       AXValueGetType(frameValueRef as! AXValue) == .cgRect {
      var frame = CGRect.zero
      AXValueGetValue(frameValueRef as! AXValue, .cgRect, &frame)
      position = frame.origin
      size = frame.size
    } else {
      var positionValueRef: AnyObject?
      var sizeValueRef: AnyObject?

      guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValueRef)
        == .success,
        let positionValueRef,
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValueRef) == .success,
        let sizeValueRef,
        AXValueGetType(positionValueRef as! AXValue) == .cgPoint,
        AXValueGetType(sizeValueRef as! AXValue) == .cgSize
      else {
        logger.notice("failed to get window frame")
        return nil
      }

      AXValueGetValue(positionValueRef as! AXValue, .cgPoint, &position)
      AXValueGetValue(sizeValueRef as! AXValue, .cgSize, &size)
    }

    let primaryHeight = primaryScreenHeight()

    return CGRect(
      x: position.x,
      y: primaryHeight - position.y - size.height,
      width: size.width,
      height: size.height
    )
  }

  // Moves and resizes the given window to a new CGRect.
  public func setWindow(window: AXUIElement, screen: NSScreen, frame _frame: CGRect) {
    /*
      The frame we get here is {
      x:  left
      y:  bottom
      width:  width
      height: height
      }, we will need to convert to top left origin used by AX
    */

    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)

    // Electron and some apps respond better to AX changes with enhanced UI mode enabled
    let appRef = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
    let primaryHeight = primaryScreenHeight()
    let frame = CGRect(
      x: _frame.origin.x,
      y: primaryHeight - _frame.origin.y - _frame.height,
      width: _frame.width,
      height: _frame.height
    )

    let targetPosition = CGPoint(x: frame.origin.x, y: frame.origin.y)
    let targetSize = CGSize(width: frame.size.width, height: frame.size.height)

    applyWindowFrame(window: window, targetPosition: targetPosition, targetSize: targetSize, attempt: 1)
  }

  private func applyWindowFrame(window: AXUIElement, targetPosition: CGPoint, targetSize: CGSize, attempt: Int) {
    let maxAttempts = 10
    guard attempt <= maxAttempts else {
      logger.notice("setWindow: giving up after \(maxAttempts) attempts")
      return
    }

    var position = targetPosition
    var size = targetSize

    guard let positionValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
      return
    }

    // Apply size first, then position (some apps need this order)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    // Set size again after position — some apps clamp size based on position
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    // Schedule a verification+retry — the app's drag-end handler may revert our changes
    let delay = 0.05 * Double(attempt)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      var checkPos = CGPoint.zero
      var checkSize = CGSize.zero
      var pRef: AnyObject?
      var sRef: AnyObject?
      if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pRef) == .success,
         let v = pRef { AXValueGetValue(v as! AXValue, .cgPoint, &checkPos) }
      if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sRef) == .success,
         let v = sRef { AXValueGetValue(v as! AXValue, .cgSize, &checkSize) }

      let posOk = abs(checkPos.x - targetPosition.x) <= 2 && abs(checkPos.y - targetPosition.y) <= 2
      let sizeOk = abs(checkSize.width - targetSize.width) <= 2 && abs(checkSize.height - targetSize.height) <= 2

      if !posOk || !sizeOk {
        self?.applyWindowFrame(window: window, targetPosition: targetPosition, targetSize: targetSize, attempt: attempt + 1)
      }
    }
  }

  private func resolveWindowElement(from element: AXUIElement) -> AXUIElement? {
    var windowValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
       let windowValue,
       CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
      return unsafeBitCast(windowValue, to: AXUIElement.self)
    }

    var current: AXUIElement? = element
    var depth = 0
    while let currentElement = current, depth < 10 {
      var roleRef: AnyObject?
      if AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &roleRef) == .success,
         let role = roleRef as? String,
         role == kAXWindowRole {
        return currentElement
      }

      var parentValue: CFTypeRef?
      if AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentValue) != .success {
        break
      }
      guard let parentValue,
        CFGetTypeID(parentValue) == AXUIElementGetTypeID()
      else {
        break
      }
      current = unsafeBitCast(parentValue, to: AXUIElement.self)
      depth += 1
    }

    return nil
  }
}
