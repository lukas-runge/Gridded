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
    let visibleFrame = screen.visibleFrame
    let screenFrame = screen.frame

    let paddingLeft = visibleFrame.minX - screenFrame.minX
    let paddingRight = screenFrame.maxX - visibleFrame.maxX
    let paddingTop = screenFrame.maxY - visibleFrame.maxY
    let paddingBottom = visibleFrame.minY - screenFrame.minY
    return (top: paddingTop, bottom: paddingBottom, right: paddingRight, left: paddingLeft)
  }

  public func convertCoordinates(
    coords: (start: CGPoint, end: CGPoint),
    screen: NSScreen
  ) -> CGRect {
    let visibleFrame = screen.visibleFrame
    let screenFrame = screen.frame

    let cellWidth = visibleFrame.width / CGFloat(Configuration.shared.columns)
    let cellHeight = visibleFrame.height / CGFloat(Configuration.shared.rows)

    let boundingGlobalTop = max(coords.start.y, coords.end.y)
    let boundingGlobalRight = max(coords.start.x, coords.end.x)
    let boundingGlobalBottom = min(coords.start.y, coords.end.y)
    let boundingGlobalLeft = min(coords.start.x, coords.end.x)

    let boundingLocalTop = boundingGlobalTop - screenFrame.minY
    let boundingLocalRight = boundingGlobalRight - screenFrame.minX
    let boundingLocalBottom = boundingGlobalBottom - screenFrame.minY
    let boundingLocalLeft = boundingGlobalLeft - screenFrame.minX

    let (_, paddingBottom, _, paddingLeft) = getScreenPadding(screen: screen)
    let boundingVisibleTop = boundingLocalTop - paddingBottom
    let boundingVisibleRight = boundingLocalRight - paddingLeft
    let boundingVisibleBottom = boundingLocalBottom - paddingBottom
    let boundingVisibleLeft = boundingLocalLeft - paddingLeft

    let rows = CGFloat(Configuration.shared.rows)
    let columns = CGFloat(Configuration.shared.columns)
    let gridTop = min((boundingVisibleTop / cellHeight).rounded(.down), rows - 1)
    let gridRight = min((boundingVisibleRight / cellWidth).rounded(.down), columns - 1)
    let gridBottom = max((boundingVisibleBottom / cellHeight).rounded(.down), 0)
    let gridLeft = max((boundingVisibleLeft / cellWidth).rounded(.down), 0)

    let windowWidth = (gridRight - gridLeft + 1) * cellWidth
    let windowHeight = (gridTop - gridBottom + 1) * cellHeight

    let gridBoundingVisibleBottom = gridBottom * cellHeight
    let gridBoundingVisibleLeft = gridLeft * cellWidth

    let gridBoundingLocalBottom = gridBoundingVisibleBottom + paddingBottom
    let gridBoundingLocalLeft = gridBoundingVisibleLeft + paddingLeft

    let gridBoundingGlobalBottom = gridBoundingLocalBottom + screenFrame.minY
    let gridBoundingGlobalLeft = gridBoundingLocalLeft + screenFrame.minX

    let result = CGRect(x: gridBoundingGlobalLeft, y: gridBoundingGlobalBottom, width: windowWidth, height: windowHeight)
    return result
  }

}
