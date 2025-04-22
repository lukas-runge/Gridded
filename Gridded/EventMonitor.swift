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
  private var mouseCoordinatesStart: CGPoint? = nil
  private var mouseCoordinatesEnd: CGPoint? = nil
  private var windowCoordinatesStart: CGPoint? = nil
  private var windowCoordinatesEnd: CGPoint? = nil
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

  private func handle(event: CGEvent, type: CGEventType) -> CGEvent {
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
      }
    case .rightMouseDown:
      logger.debug("right mouse down")
      startSnapping()
    case .keyDown:
      if event.getIntegerValueField(.keyboardEventKeycode) == activateKey {
        logger.debug("space down")
        startSnapping()
      }
    default:
      break
    }

    return event
  }

  private func leftMouseDown() {
    reset()
    activeScreen = ScreenManager.shared.getActiveScreen()
    isDragging = true
  }

  private func leftMouseUp() {
    guard isSnapping else { return reset() }
    guard activeScreen != nil else { return reset() }
    guard mouseCoordinatesEnd != mouseCoordinatesStart else { return reset() }
    guard windowCoordinatesEnd != windowCoordinatesStart else { return reset() }
    guard snapToCoordinates != nil else { return reset() }

    if !Configuration.shared.moveOnActivate {
      WindowManager.shared.setWindow(
        window: self.frontMostWindow!,
        screen: activeScreen!,
        frame: snapToCoordinates!
      )
    }
    reset()
  }

  private func leftMouseDragged() {
    guard isSnapping else { return reset() }
    let currentMouse = getMouseCoordinates()

    // Only constrain the mouse if the user has enabled this setting
    if Configuration.shared.constrainMouse {
      constrainMouseToActiveScreen(currentMouse)
    }
    mouseCoordinatesEnd = currentMouse

    snapToCoordinates = ScreenManager.shared.convertCoordinates(
      coords: (start: mouseCoordinatesStart!, end: mouseCoordinatesEnd!),
      screen: activeScreen!
    )
    updateOverlayPreview(snapToCoordinates: snapToCoordinates!)
    if Configuration.shared.moveOnActivate {
      WindowManager.shared.setWindow(
        window: self.frontMostWindow!,
        screen: activeScreen!,
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
    guard isDragging else { return }
    isSnapping = true
    guard activeScreen != nil else { return }
    frontMostWindow = WindowManager.shared.getFrontmostWindow()
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

  private func constrainMouseToActiveScreen(_ mousePosition: CGPoint) {
    guard let activeScreen = activeScreen else { return }

    // Get the screen frame in global coordinates
    let visibleFrame = activeScreen.visibleFrame

    let margin: CGFloat = 5

    let minX = visibleFrame.minX + margin
    let maxX = visibleFrame.maxX - margin
    let minY = visibleFrame.minY + margin
    let maxY = visibleFrame.maxY - margin

    // Constrain the mouse position to the screen bounds
    var newMousePosition = mousePosition

    var moved: Bool = false
    if mousePosition.x > maxX {
      newMousePosition.x = maxX
      moved = true
    }
    if mousePosition.x < minX {
      newMousePosition.x = minX
      moved = true
    }
    if mousePosition.y > maxY {
      newMousePosition.y = maxY
      moved = true
    }
    if mousePosition.y < minY {
      newMousePosition.y = minY
      moved = true
    }

    if moved {
      newMousePosition.y = activeScreen.frame.maxY - newMousePosition.y
      CGWarpMouseCursorPosition(newMousePosition)
    }
  }

  private func updateOverlayPreview(snapToCoordinates: CGRect) {
    guard isSnapping, let activeScreen = activeScreen,
      let mouseStart = mouseCoordinatesStart,
      let mouseEnd = mouseCoordinatesEnd
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
