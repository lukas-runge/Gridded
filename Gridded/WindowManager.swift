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

@Observable class WindowManager {

  static let shared = WindowManager()

  private let logger = Logger(label: "WindowManager")

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
      logger.debug(
        "successfully got frontmost window for app: \(frontmostApp.localizedName ?? "unknown")"
      )
      return (windowElement as! AXUIElement)
    }

    logger.notice("failed to get frontmost window with error: \(result.rawValue)")
    return nil
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

    logger.info(
      "Got frame\t\t(x: \(_frame.origin.x), y: \(_frame.origin.y), width: \(_frame.width), height: \(_frame.height))"
    )

    let primaryScreenHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? NSScreen.main!.frame.height

    let frame = CGRect(
      x: _frame.origin.x,
      y: primaryScreenHeight - _frame.origin.y - _frame.height,
      width: _frame.width,
      height: _frame.height
    )

    logger.info(
      "Set frame\t\t(x: \(frame.origin.x), y: \(frame.origin.y), width: \(frame.width), height: \(frame.height))"
    )

    var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
    var size = CGSize(width: frame.size.width, height: frame.size.height)

    // Create AXValues with the mutable variables
    if let positionValue = AXValueCreate(.cgPoint, &position),
      let sizeValue = AXValueCreate(.cgSize, &size)
    {
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
  }
}
