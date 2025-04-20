//
//  ScreenManager.swift
//  Gridded
//
//  Created by An So on 2025-04-20.
//

import Cocoa
import Logging

class ScreenManager {
  static let shared = ScreenManager()
  private let logger = Logger(label: "ScreenManager")

  private init() {}

  public func getActiveScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation

    for screen in NSScreen.screens {
      if screen.frame.contains(mouseLocation) {
        return screen
      }
    }

    logger.notice("failed to determine active screen.")
    return nil
  }

  public func getScreenPadding(screen: NSScreen) -> (
    top: CGFloat, bottom: CGFloat, right: CGFloat, left: CGFloat
  ) {
    // Get the active screen and its visible frame
    let visibleFrame = screen.visibleFrame
    let screenFrame = screen.frame

    // Calculate menubar and dock height (if visible)
    let paddingLeft = visibleFrame.minX - screenFrame.minX
    let paddingRight = screenFrame.maxX - visibleFrame.maxX
    let paddingTop = screenFrame.maxY - visibleFrame.maxY
    let paddingBottom = visibleFrame.minY - screenFrame.minY
    return (top: paddingTop, bottom: paddingBottom, right: paddingRight, left: paddingLeft)
  }

  public func convertCoordinates(
    coords: (start: CGPoint, end: CGPoint),  // global multi-screen coordinates
    screen: NSScreen
  ) -> CGRect {
    // macOS coordinates origin is at bottom left
    // while AXUIElementSetAttributeValue wants a coordinates origin at top left
    // Why the inconsistence, Apple?

    logger.info("")
    
    let visibleFrame = screen.visibleFrame
    let screenFrame = screen.frame
    
    logger.info("Converting new snap coordinates")

    // Calculate grid cell dimensions
    let cellWidth = visibleFrame.width / CGFloat(Configuration.shared.columns)
    let cellHeight = visibleFrame.height / CGFloat(Configuration.shared.rows)

    logger.info("Cell w/h\t\t(\(cellWidth), \(cellHeight))")

    // Find the bounding box of the drag coordinates in global space
    let boundingGlobalTop = max(coords.start.y, coords.end.y)
    let boundingGlobalRight = max(coords.start.x, coords.end.x)
    let boundingGlobalBottom = min(coords.start.y, coords.end.y)
    let boundingGlobalLeft = min(coords.start.x, coords.end.x)

    logger.info(
      "Drag global\t\t(\(boundingGlobalTop), \(boundingGlobalRight), \(boundingGlobalBottom), \(boundingGlobalLeft))"
    )

    // Convert global screen coordinates to local single-screen coordinates
    let boundingLocalTop = boundingGlobalTop - screenFrame.minY
    let boundingLocalRight = boundingGlobalRight - screenFrame.minX
    let boundingLocalBottom = boundingGlobalBottom - screenFrame.minY
    let boundingLocalLeft = boundingGlobalLeft - screenFrame.minX

    logger.info(
      "Drag local\t\t(\(boundingLocalTop), \(boundingLocalRight), \(boundingLocalBottom), \(boundingLocalLeft))"
    )

    // Gonvert local screen coordinates to visible frame coordinates
    let (paddingTop, paddingBottom, paddingRight, paddingLeft) = getScreenPadding(
      screen: screen)
    let boundingVisibleTop = boundingLocalTop - paddingBottom
    let boundingVisibleRight = boundingLocalRight - paddingLeft
    let boundingVisibleBottom = boundingLocalBottom - paddingBottom
    let boundingVisibleLeft = boundingLocalLeft - paddingLeft

    logger.info(
      "Drag visible\t(\(boundingVisibleTop), \(boundingVisibleRight), \(boundingVisibleBottom), \(boundingVisibleLeft))"
    )

    // Get containing grid index, starting from 0, in visible frame starting from bottom left
    let gridTop = (boundingVisibleTop / cellHeight).rounded(.down)
    let gridRight = (boundingVisibleRight / cellWidth).rounded(.down)
    let gridBottom = (boundingVisibleBottom / cellHeight).rounded(.down)
    let gridLeft = (boundingVisibleLeft / cellWidth).rounded(.down)

    logger.info(
      "Grid index\t\t(\(gridTop), \(gridRight), \(gridBottom), \(gridLeft))")
    
    // Get window width and cellHeight
    let windowWidth = (gridRight - gridLeft + 1) * cellWidth
    let windowHeight = (gridTop - gridBottom + 1) * cellHeight

    logger.info("Window w/h\t\t(\(windowWidth), \(windowHeight))")

    // Get bounding visible frame coordinates for the grids
    let gridBoundingVisibleTop = (gridTop + 1) * cellHeight
    let gridBoundingVisibleRight = (gridRight + 1) * cellWidth
    let gridBoundingVisibleBottom = gridBottom * cellHeight
    let gridBoundingVisibleLeft = gridLeft * cellWidth

    logger.info(
      "Grid visible\t(\(gridBoundingVisibleTop), \(gridBoundingVisibleRight), \(gridBoundingVisibleBottom), \(gridBoundingVisibleLeft))"
    )

    // Get bounding local screen coordinates for the grids
    let gridBoundingLocalTop = gridBoundingVisibleTop + paddingBottom
    let gridBoundingLocalRight = gridBoundingVisibleRight + paddingLeft
    let gridBoundingLocalBottom = gridBoundingVisibleBottom + paddingBottom
    let gridBoundingLocalLeft = gridBoundingVisibleLeft + paddingLeft

    logger.info(
      "Grid local\t\t(\(gridBoundingLocalTop), \(gridBoundingLocalRight), \(gridBoundingLocalBottom), \(gridBoundingLocalLeft))"
    )

    // Get bounding global screen coordinates for the grids
    let gridBoundingGlobalTop = gridBoundingLocalTop + screenFrame.minY
    let gridBoundingGlobalRight = gridBoundingLocalRight + screenFrame.minX
    let gridBoundingGlobalBottom = gridBoundingLocalBottom + screenFrame.minY
    let gridBoundingGlobalLeft = gridBoundingLocalLeft + screenFrame.minX

    logger.info(
      "Grid global\t\t(\(gridBoundingGlobalTop), \(gridBoundingGlobalRight), \(gridBoundingGlobalBottom), \(gridBoundingGlobalLeft))"
    )

    return CGRect(
      x: gridBoundingGlobalLeft,
      y: gridBoundingGlobalBottom,
      width: windowWidth,
      height: windowHeight
    )
  }

}
