//
//  StatusBarController.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import AppKit
import Logging
import SwiftUI

final class StatusBarController {
    private let logger = Logger(label: "StatusBarController")

    private var statusItem: NSStatusItem!

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "grid", accessibilityDescription: "Gridded")
        }

        let menu = NSMenu(title: "Gridded")
        menu.addItem(
            NSMenuItem(
                title: "About Gridded", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Preferences", action: #selector(openPreferences), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Restart event monitor", action: #selector(restartEventMonitor),
                keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""))

        // Set target on each menu item
        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView()
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)

            preferencesWindow?.center()
            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.contentView = NSHostingView(rootView: view)
            preferencesWindow?.title = "Gridded Preferences"
        }

        if preferencesWindow?.isVisible == true {
            preferencesWindow?.orderOut(nil)
        } else {
            preferencesWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func restartEventMonitor() {
        EventMonitor.shared.restart()
    }

    @objc private func openAbout() {
        if aboutWindow == nil {
            let view = AboutView()
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 450),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            aboutWindow?.center()
            aboutWindow?.isReleasedWhenClosed = false
            aboutWindow?.contentView = NSHostingView(rootView: view)
            aboutWindow?.title = "About"
        }

        if aboutWindow?.isVisible == true {
            aboutWindow?.orderOut(nil)
        } else {
            aboutWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
