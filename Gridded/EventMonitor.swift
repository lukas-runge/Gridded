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

class EventMonitor {
    static let shared = EventMonitor()

    private let logger = Logger(label: "EventMonitor")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSpacePressed = false
    private var dragCheckTimer: Timer?

    var isDragging: Bool = false
    var isSnapping: Bool = false
    var frontMostWindow: AXUIElement? = nil
    var mouseCoordinatesStart: CGPoint? = nil
    var mouseCoordinatesEnd: CGPoint? = nil
    var windowCoordinatesStart: CGPoint? = nil
    var windowCoordinatesEnd: CGPoint? = nil

    private init() {}

    // MARK: Lifecycle
    /**
     * Start event monitor, should run when app is started.
     */
    func start() {
        guard eventTap == nil else { return }
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: false]
        Configuration.shared.accessibilityPermission = AXIsProcessTrustedWithOptions(options)
        
        if (!Configuration.shared.accessibilityPermission) {
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
        // TODO: make this configurable
        let activateKey = 49  // space
        switch type {
        case .leftMouseDown:
            logger.debug("left mouse down")
            leftMouseDown()
        case .leftMouseUp:
            logger.debug("left mouse up")
            leftMouseUp()
        case .leftMouseDragged:
            logger.debug("left mouse up")
            if isSnapping {
                let currentMouse = getMouseCoordinates()
                OverlayWindow.shared.updateWindowPreview(
                    start: mouseCoordinatesStart!,
                    end: currentMouse
                )
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
        isDragging = true
    }

    private func leftMouseUp() {
        if isSnapping {
            mouseCoordinatesEnd = getMouseCoordinates()
            if windowCoordinatesEnd != windowCoordinatesStart {
                // window moved
                WindowManager.shared.snap(
                    window: frontMostWindow!,
                    to: SnapToCoordinates(
                        start: mouseCoordinatesStart!,
                        end: mouseCoordinatesEnd!
                    )
                )
            }

        }
        reset()
    }

    private func reset() {
        mouseCoordinatesEnd = nil
        mouseCoordinatesStart = nil
        windowCoordinatesEnd = nil
        windowCoordinatesStart = nil
        frontMostWindow = nil
        isDragging = false
        isSnapping = false
        OverlayWindow.shared.hide()
    }

    private func startSnapping() {
        guard isDragging else { return }
        isSnapping = true
        frontMostWindow = WindowManager.shared.getFrontmostWindow()
        windowCoordinatesStart = getWindowCoordinates()
        mouseCoordinatesStart = getMouseCoordinates()
        OverlayWindow.shared.show()
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
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            
//            NSApplication.shared.terminate(self)
        }
    }
}
