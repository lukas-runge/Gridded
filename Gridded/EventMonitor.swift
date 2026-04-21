//
//  EventMonitor.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import AppKit
import Cocoa
import CoreGraphics
import Foundation
import Logging

//enum DockPosition {
//  case bottom
//  case left
//  case right
//}

class EventMonitor {
  static let shared = EventMonitor()

  private static let escapeKeyCode: Int64 = 53
  private static let dragDetectionThreshold: CGFloat = 0

  private let logger = Logger(label: "EventMonitor")

  public var isMonitoring: Bool { eventTap != nil }
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var isSpacePressed = false
  private var dragCheckTimer: Timer?
  private var overlayWindow: OverlayWindow?
  private var isDragging: Bool = false
  private var isSnapping: Bool = false
  private var frontMostWindow: AXUIElement? = nil
  private var originalDraggedWindow: AXUIElement? = nil
  private var mouseCoordinatesStart: CGPoint? = nil
  private var mouseCoordinatesEnd: CGPoint? = nil
  private var windowCoordinatesStart: CGPoint? = nil
  private var windowCoordinatesEnd: CGPoint? = nil
  private var originalWindowAXFrame: AXWindowFrame? = nil
  public private(set) var activeScreen: NSScreen? = nil
  private var snapToCoordinates: CGRect? = nil

  private init() {}

  // MARK: Lifecycle
  /**
   * Start event monitor, should run when app is started.
   */
  func start() {
    guard eventTap == nil else { return }

    let options: NSDictionary = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: false
    ]
    Configuration.shared.accessibilityPermission = AXIsProcessTrustedWithOptions(options)

    if !Configuration.shared.accessibilityPermission {
      showAccessibilityAlert()
      return
    }

    let eventMask =
      (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.leftMouseDragged.rawValue)
      | (1 << CGEventType.leftMouseUp.rawValue)
      | (1 << CGEventType.rightMouseDown.rawValue)
      | (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.mouseMoved.rawValue)

    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: { _, type, event, refcon in
        let handledEvent = EventMonitor.shared.handle(event: event, type: type)
        guard let handledEvent else { return nil }
        return Unmanaged.passUnretained(handledEvent)
      },
      userInfo: nil
    )

    if let eventTap = eventTap {
      runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
      CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    logger.info("event monitor started")
  }

  /**
   * Stop event monitor, should run when app exits.
   */
  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
    if let tap = eventTap {
      CFMachPortInvalidate(tap)
    }
    eventTap = nil
    runLoopSource = nil
    logger.info("event monitor stopped")
  }

  func restart() {
    stop()
    reset()
    start()
  }

  // MARK: Event handlers

  private func handle(event: CGEvent, type: CGEventType) -> CGEvent? {
    let activateKey = Configuration.shared.activateKey
    switch type {
    case .leftMouseDown:
      logger.debug("left mouse down")
      leftMouseDown()
    case .leftMouseUp:
      logger.debug("left mouse up")
      leftMouseUp()
    case .leftMouseDragged:
      if isSnapping {
        logger.debug("left mouse dragged")
        leftMouseDragged()
      } else {
        updateDraggingState()
      }
    case .rightMouseDown:
      logger.debug("right mouse down")
      startSnapping()
    case .keyDown:
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      if keyCode == Self.escapeKeyCode, cancelSnapping() {
        logger.debug("escape down")
        return nil
      }
      if keyCode == activateKey {
        logger.debug("space down")
        startSnapping()
      }
    default:
      break
    }

    return event
  }

  @discardableResult
  private func cancelSnapping() -> Bool {
    guard isSnapping else { return false }
    logger.debug("cancel snapping")

    if Configuration.shared.resetWindowOnEscape {
      let window = originalDraggedWindow ?? frontMostWindow
      let originalWindowAXFrame = originalWindowAXFrame

      endActiveWindowDrag()
      reset()

      if let window, let originalWindowAXFrame {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          WindowManager.shared.restoreWindow(
            window: window,
            axFrame: originalWindowAXFrame
          )
        }
      }
      return true
    }

    mouseCoordinatesEnd = nil
    mouseCoordinatesStart = nil
    isSnapping = false
    snapToCoordinates = nil

    if overlayWindow != nil {
      overlayWindow?.orderOut(nil)
      overlayWindow = nil
    }

    return true
  }

  private func leftMouseDown() {
    reset()
    activeScreen = ScreenManager.shared.getActiveScreen()
    isDragging = !Configuration.shared.requireWindowDragBeforeSnapping
    captureWindowForCurrentDrag()

    // Only async-refresh if the sync capture found nothing — do NOT overwrite a
    // successful capture, because by the time this fires, focus may have shifted
    // to a different app (e.g. the window that received the click becoming active).
    if frontMostWindow == nil {
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isSnapping else { return }
        self.captureWindowForCurrentDrag()
      }
    }
  }

  private func leftMouseUp() {
    guard isSnapping else { return reset() }
    guard activeScreen != nil else { return reset() }
    guard mouseCoordinatesEnd != mouseCoordinatesStart else { return reset() }
    guard snapToCoordinates != nil else { return reset() }

    if !Configuration.shared.moveOnActivate {
      // Capture state before reset — we must defer setWindow until after this
      // event-tap callback returns so the mouseUp propagates to the app first.
      // The target app's drag handler needs time to process the mouseUp and
      // exit its drag state; applyWindowFrame retries if the app reverts changes.
      let window = self.frontMostWindow!
      let screen = activeScreen!
      let frame = snapToCoordinates!
      reset()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        WindowManager.shared.setWindow(window: window, screen: screen, frame: frame)
      }
      return
    }
    reset()
  }

  private func leftMouseDragged() {
    guard isSnapping else { return reset() }
    var currentMouse = getMouseCoordinates()
    let hoveredScreen = ScreenManager.shared.getScreen(at: currentMouse)

    if let hoveredScreen,
      let previousScreen = activeScreen,
      previousScreen != hoveredScreen
    {
      logger.debug("active screen changed during drag")
      overlayWindow?.orderOut(nil)
      overlayWindow = nil
    }

    // Only constrain the mouse if the user has enabled this setting
    if Configuration.shared.constrainMouse {
      currentMouse = constrainMouseForSnapping(
        currentMouse,
        hoveredScreen: hoveredScreen
      )
    }

    if hoveredScreen != nil {
      activeScreen = ScreenManager.shared.getScreen(at: currentMouse) ?? hoveredScreen ?? activeScreen
    }

    guard let activeScreen else { return }

    mouseCoordinatesEnd = currentMouse

    snapToCoordinates = ScreenManager.shared.convertCoordinates(
      coords: (start: mouseCoordinatesStart!, end: mouseCoordinatesEnd!),
      screen: activeScreen
    )
    updateOverlayPreview(snapToCoordinates: snapToCoordinates!)
    if Configuration.shared.moveOnActivate {
      WindowManager.shared.setWindow(
        window: self.frontMostWindow!,
        screen: activeScreen,
        frame: snapToCoordinates!
      )
    }
  }

  private func reset() {
    mouseCoordinatesEnd = nil
    mouseCoordinatesStart = nil
    windowCoordinatesEnd = nil
    windowCoordinatesStart = nil
    frontMostWindow = nil
    originalDraggedWindow = nil
    originalWindowAXFrame = nil
    isDragging = false
    isSnapping = false
    activeScreen = nil
    snapToCoordinates = nil

    // Hide and dispose of overlay window
    if overlayWindow != nil {
      overlayWindow?.orderOut(nil)
      overlayWindow = nil
    }
  }

  private func startSnapping() {
    if Configuration.shared.requireWindowDragBeforeSnapping {
      updateDraggingState()
      guard isDragging else { return }
    }

    guard isDragging else { return }
    isSnapping = true
    activeScreen = ScreenManager.shared.getActiveScreen() ?? activeScreen
    guard activeScreen != nil else { return }

    if let snapWindow = WindowManager.shared.getWindowAtPoint(getMouseCoordinates())
      ?? WindowManager.shared.getFrontmostWindow()
    {
      if let capturedWindow = frontMostWindow,
        !CFEqual(capturedWindow, snapWindow)
      {
        logger.warning("startSnapping: captured window differs from snap window, preserving original restore target")
      }
      frontMostWindow = snapWindow
    }
    windowCoordinatesStart = getWindowCoordinates()
    mouseCoordinatesStart = getMouseCoordinates()
    mouseCoordinatesEnd = mouseCoordinatesStart

    snapToCoordinates = ScreenManager.shared.convertCoordinates(
      coords: (start: mouseCoordinatesStart!, end: mouseCoordinatesStart!),
      screen: activeScreen!
    )

    // Show initial overlay preview
    if Configuration.shared.moveOnActivate {
      WindowManager.shared.setWindow(
        window: self.frontMostWindow!,
        screen: activeScreen!,
        frame: snapToCoordinates!
      )
    }
    updateOverlayPreview(snapToCoordinates: snapToCoordinates!)
  }

  private func captureWindowForCurrentDrag() {
    let mouse = getMouseCoordinates()
    let hitWindow = WindowManager.shared.getWindowAtPoint(mouse)
    frontMostWindow = hitWindow ?? WindowManager.shared.getFrontmostWindow()

    if hitWindow == nil {
      logger.warning("captureWindowForCurrentDrag: hit-test failed, falling back to frontmost window")
    }
    windowCoordinatesStart = getWindowCoordinates()
    if let frontMostWindow {
      originalDraggedWindow = frontMostWindow
      originalWindowAXFrame = WindowManager.shared.getAXWindowFrame(window: frontMostWindow)
    } else {
      originalDraggedWindow = nil
      originalWindowAXFrame = nil
    }
  }

  private func updateDraggingState() {
    guard Configuration.shared.requireWindowDragBeforeSnapping else {
      isDragging = true
      return
    }

    guard let frontMostWindow else {
      isDragging = false
      return
    }

    guard let windowCoordinatesStart else {
      isDragging = false
      return
    }

    var currentWindowPosition = CGPoint.zero
    var value: AnyObject?

    guard AXUIElementCopyAttributeValue(frontMostWindow, kAXPositionAttribute as CFString, &value)
      == .success,
      let value,
      AXValueGetType(value as! AXValue) == .cgPoint
    else {
      isDragging = false
      return
    }

    AXValueGetValue(value as! AXValue, .cgPoint, &currentWindowPosition)

    let deltaX = abs(currentWindowPosition.x - windowCoordinatesStart.x)
    let deltaY = abs(currentWindowPosition.y - windowCoordinatesStart.y)
    isDragging = deltaX > Self.dragDetectionThreshold || deltaY > Self.dragDetectionThreshold
  }

  private func endActiveWindowDrag() {
    let cocoaMousePosition = getMouseCoordinates()
    let axMousePosition = WindowManager.shared.appKitPointToAXPoint(cocoaMousePosition)

    guard let event = CGEvent(
      mouseEventSource: nil,
      mouseType: .leftMouseUp,
      mouseCursorPosition: axMousePosition,
      mouseButton: .left
    ) else {
      return
    }

    event.post(tap: .cghidEventTap)
  }

  private func constrainMouseForSnapping(_ mousePosition: CGPoint, hoveredScreen: NSScreen?) -> CGPoint {
    // If the pointer is on any screen, do not interfere; this preserves cross-monitor dragging.
    if hoveredScreen != nil {
      return mousePosition
    }

    guard let activeScreen else { return mousePosition }

    let frame = activeScreen.visibleFrame
    let margin: CGFloat = 3
    let clamped = CGPoint(
      x: min(max(mousePosition.x, frame.minX + margin), frame.maxX - margin),
      y: min(max(mousePosition.y, frame.minY + margin), frame.maxY - margin)
    )

    // Use logical clamping only; physical cursor warping causes monitor hops on some layouts.
    return clamped
  }

  private func updateOverlayPreview(snapToCoordinates: CGRect) {
    guard isSnapping, let activeScreen = activeScreen,
      mouseCoordinatesStart != nil,
      mouseCoordinatesEnd != nil
    else {
      return
    }

    // Create or update overlay window
    if overlayWindow == nil {
      overlayWindow = OverlayWindow(frame: snapToCoordinates, screen: activeScreen)
      overlayWindow?.orderFront(nil)
    } else {
      overlayWindow?.update(frame: snapToCoordinates, screen: activeScreen)
    }
  }

  // MARK: Coordinates polling

  private func startPollingWindow() {
    dragCheckTimer?.invalidate()
    dragCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
      self.windowCoordinatesEnd = self.getWindowCoordinates()
    }
    logger.debug("window coordinates polling started")
  }

  private func stopPollingWindow() {
    dragCheckTimer?.invalidate()
    dragCheckTimer = nil
    logger.debug("window coordinates polling stopped")
  }

  private func getMouseCoordinates() -> CGPoint {
    return NSEvent.mouseLocation
  }

  private func getWindowCoordinates() -> CGPoint? {
    guard let window = frontMostWindow else {
      logger.notice("frontmost window not set")
      return nil
    }

    var topLeft: CGPoint = CGPoint.zero

    var value: AnyObject?
    guard AXIsProcessTrusted() else {
      restart()
      return nil
    }

    if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
      == .success
    {
      let position = value as! AXValue
      if AXValueGetType(position) == .cgPoint {
        AXValueGetValue(position, .cgPoint, &topLeft)
      }
    }

    return topLeft
  }

  // MARK: alert when permission not granted
  func showAccessibilityAlert() {
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission"
    alert.informativeText = """
      To detect window movement and move window, the app needs accessibility permission.

      Please go to System Settings → Privacy & Security → Accessibility, and enable access for this app.

      You may need to restart the app after granting permission.
      """
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
      NSWorkspace.shared.open(url)

      //      NSApplication.shared.terminate(self)
    }
  }
}
