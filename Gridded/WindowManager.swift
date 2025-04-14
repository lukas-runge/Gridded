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
    private func setWindow(_ window: AXUIElement, frame: CGRect) {
        // Create mutable variables for inout parameters
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

    public func snap(window: AXUIElement, to coord: SnapToCoordinates) {

        // macOS coordinates origin is at bottom left
        // while AXUIElementSetAttributeValue wants a coordinates origin at top left
        // Why the inconsistence, Apple?

        // Get the active screen and its visible frame
        let screen = getActiveScreen() ?? NSScreen.main!
        let visibleFrame = screen.visibleFrame

        // Calculate grid cell dimensions
        let cellWidth = visibleFrame.width / CGFloat(Configuration.shared.columns)
        let cellHeight = visibleFrame.height / CGFloat(Configuration.shared.rows)

        // Find the bounding box of the drag coordinates
        let dragMinX = min(coord.start.x, coord.end.x)
        let dragMaxX = max(coord.start.x, coord.end.x)
        let dragMinY = min(coord.start.y, coord.end.y)
        let dragMaxY = max(coord.start.y, coord.end.y)

        // Convert screen coordinates to grid indices
        // For X: 0 is at left edge of visible frame
        let startCol = Int(((dragMinX - visibleFrame.minX) / cellWidth).rounded(.down))
        let endCol = Int(((dragMaxX - visibleFrame.minX) / cellWidth).rounded(.down))

        // For Y: 0 is at top edge of visible frame
        let startRow = Int(((visibleFrame.maxY - dragMaxY) / cellHeight).rounded(.down))
        let endRow = Int(((visibleFrame.maxY - dragMinY) / cellHeight).rounded(.down))

        // Calculate the window frame
        // X position: start from left edge of visible frame + column offset
        let x = visibleFrame.minX + CGFloat(startCol) * cellWidth

        // Y position: start from top edge of visible frame - row offset
        // We use maxY because we need to flip the Y coordinates
        let menubarHeight = screen.frame.maxY - visibleFrame.maxY
        let y = menubarHeight + CGFloat(startRow) * cellHeight

        // Width: number of columns * cell width
        let width = CGFloat(endCol - startCol + 1) * cellWidth

        // Height: number of rows * cell height
        let height = CGFloat(endRow - startRow + 1) * cellHeight

        logger.info(
            "snapping window to (\(startCol), \(startRow)) to (\(endCol), \(endRow)), coordinates (\(x), \(y)) with a size of (\(width), \(height))"
        )

        // Create the final frame
        // Rect origin is top left
        let rect = CGRect(x: x, y: y, width: width, height: height)

        setWindow(window, frame: rect)
    }

    func getActiveScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }

        logger.notice("failed to determine active screen.")
        return nil
    }
}
