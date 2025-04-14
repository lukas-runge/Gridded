import Cocoa

class GridView: NSView {
  var rows: CGFloat = 5
  var columns: CGFloat = 5
  var visibleFrame: NSRect = .zero
  var windowStart: CGPoint?
  var windowEnd: CGPoint?

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else { return }

    // Calculate grid cell size based on visible frame
    let cellWidth = visibleFrame.width / columns
    let cellHeight = visibleFrame.height / rows

    // Draw highlighted cells if window coordinates are set
    if let start = windowStart, let end = windowEnd {
      // Determine which cells are covered
      let minX = min(start.x, end.x)
      let maxX = max(start.x, end.x)
      let minY = min(start.y, end.y)
      let maxY = max(start.y, end.y)

      // Convert to grid indices
      let startCol = Int((minX - visibleFrame.minX) / cellWidth)
      let endCol = Int((maxX - visibleFrame.minX) / cellWidth)
      let startRow = Int((visibleFrame.maxY - maxY) / cellHeight)
      let endRow = Int((visibleFrame.maxY - minY) / cellHeight)

      // Draw highlighted cells
      context.setFillColor(NSColor.white.withAlphaComponent(0.1).cgColor)
      for row in startRow...endRow {
        for col in startCol...endCol {
          let rect = NSRect(
            x: visibleFrame.minX + CGFloat(col) * cellWidth,
            y: visibleFrame.maxY - (CGFloat(row + 1) * cellHeight),
            width: cellWidth,
            height: cellHeight
          )
          context.fill(rect)
        }
      }
    }

    // Set line properties
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
    context.setLineWidth(1.0)

    // Draw vertical lines
    for i in 1..<Int(columns) {
      let x = visibleFrame.minX + CGFloat(i) * cellWidth
      context.move(to: CGPoint(x: x, y: visibleFrame.minY))
      context.addLine(to: CGPoint(x: x, y: visibleFrame.maxY))
    }

    // Draw horizontal lines
    for i in 1..<Int(rows) {
      let y = visibleFrame.minY + CGFloat(i) * cellHeight
      context.move(to: CGPoint(x: visibleFrame.minX, y: y))
      context.addLine(to: CGPoint(x: visibleFrame.maxX, y: y))
    }

    context.strokePath()
  }
}

class OverlayWindow: NSWindow {
  static let shared = OverlayWindow()
  private let gridView = GridView()

  private init() {
    super.init(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    self.backgroundColor = NSColor.black.withAlphaComponent(0.2)
    self.isOpaque = false
    self.level = .floating
    self.ignoresMouseEvents = true

    // Setup grid view
    gridView.autoresizingMask = [.width, .height]
    self.contentView = gridView
  }

  func updateGrid() {
    gridView.rows = CGFloat(Configuration.shared.rows)
    gridView.columns = CGFloat(Configuration.shared.columns)
    if let screen = NSScreen.main {
      gridView.visibleFrame = screen.visibleFrame
    }
    gridView.needsDisplay = true
  }

  func updateWindowPreview(start: CGPoint, end: CGPoint) {
    gridView.windowStart = start
    gridView.windowEnd = end
    gridView.needsDisplay = true
  }

  func show() {
    updateGrid()
    if let screen = NSScreen.main {
      self.setFrame(screen.frame, display: true)
      gridView.visibleFrame = screen.visibleFrame
      self.orderFront(nil)
    }
  }

  func hide() {
    gridView.windowStart = nil
    gridView.windowEnd = nil
    self.orderOut(nil)
  }
}
