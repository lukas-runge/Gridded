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

struct AXWindowFrame {
  var position: CGPoint
  var size: CGSize
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

  public func appKitPointToAXPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: primaryScreenHeight() - point.y)
  }

  public func windowDebugDescription(_ window: AXUIElement) -> String {
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)
    let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid:\(pid)"

    var titleRef: AnyObject?
    let title: String
    if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
       let titleValue = titleRef as? String {
      title = titleValue.isEmpty ? "<untitled>" : titleValue
    } else {
      title = "<no title>"
    }

    return "\(appName) - \"\(title)\""
  }

  // Returns the frontmost (active) window of the currently focused application.
  public func getFrontmostWindow() -> AXUIElement? {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      logger.notice("failed to get frontmost application")
      return nil
    }

    let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

    var window: AnyObject?
    let result = AXUIElementCopyAttributeValue(
      appElement, kAXFocusedWindowAttribute as CFString, &window)

    if result == .success, let windowElement = window {
      let resolvedWindow = windowElement as! AXUIElement
      logger.notice("getFrontmostWindow: \(self.windowDebugDescription(resolvedWindow))")
      return resolvedWindow
    }

    logger.notice("getFrontmostWindow: failed for app \(frontmostApp.localizedName ?? "unknown"), error=\(result.rawValue)")
    return nil
  }

  public func getWindowAtPoint(_ point: CGPoint) -> AXUIElement? {
    let systemWideElement = AXUIElementCreateSystemWide()
    var hitElementRef: AXUIElement?

    // NSEvent.mouseLocation uses AppKit coords (origin bottom-left, y up).
    // AXUIElementCopyElementAtPosition uses CG/AX coords (origin top-left, y down).
    let axPoint = appKitPointToAXPoint(point)
    let hitResult = AXUIElementCopyElementAtPosition(
      systemWideElement,
      Float(axPoint.x),
      Float(axPoint.y),
      &hitElementRef
    )

    logger.notice("getWindowAtPoint: AppKit=(\(point.x),\(point.y)) AX=(\(axPoint.x),\(axPoint.y)) result=\(hitResult.rawValue)")

    if hitResult == .success,
      let hitElementRef,
      let window = resolveWindowElement(from: hitElementRef)
    {
      logger.notice("getWindowAtPoint: resolved \(self.windowDebugDescription(window))")
      return window
    }

    logger.notice("getWindowAtPoint: no window resolved")

    return nil
  }

  public func getWindowFrame(window: AXUIElement) -> CGRect? {
    guard let axFrame = getAXWindowFrame(window: window) else { return nil }

    let primaryHeight = primaryScreenHeight()

    return CGRect(
      x: axFrame.position.x,
      y: primaryHeight - axFrame.position.y - axFrame.size.height,
      width: axFrame.size.width,
      height: axFrame.size.height
    )
  }

  public func getAXWindowFrame(window: AXUIElement) -> AXWindowFrame? {
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

    let axFrame = AXWindowFrame(position: position, size: size)
    logger.notice("getAXWindowFrame: \(self.windowDebugDescription(window)) -> pos=(\(position.x),\(position.y)) size=(\(size.width),\(size.height))")
    return axFrame
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

  public func restoreWindow(window: AXUIElement, axFrame: AXWindowFrame) {
    logger.notice(
      "restoreWindow: \(self.windowDebugDescription(window)) -> pos=(\(axFrame.position.x),\(axFrame.position.y)) size=(\(axFrame.size.width),\(axFrame.size.height))"
    )
    applyWindowFrame(
      window: window,
      targetPosition: axFrame.position,
      targetSize: axFrame.size,
      attempt: 1
    )
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
