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

        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                return Unmanaged.passRetained(EventMonitor.shared.handle(event: event, type: type))
            },
            userInfo: nil
        )

        if let eventTap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }

        logger.debug("started")
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
        logger.debug("stopped")
    }

    // MARK: Event handlers

    private func handle(event: CGEvent, type: CGEventType) -> CGEvent {
        // TODO: make this configurable
        let activateKey = 49 // space
        switch type {
        case .leftMouseDown:
            logger.debug("left mouse down")
            leftMouseDown()
        case .leftMouseUp:
            logger.debug("left mouse up")
            leftMouseUp()
        case .leftMouseDragged:
            if isSnapping {
                let currentMouse = getMouseCoordinates()
                OverlayWindow.shared.updateWindowPreview(
                    start: mouseCoordinatesStart!,
                    end: currentMouse
                )
            }
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == activateKey {
                logger.debug("space down")
                spaceDown()
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

    private func spaceDown() {
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
}
