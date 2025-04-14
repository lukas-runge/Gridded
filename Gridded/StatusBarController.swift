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
            button.image = NSImage(systemSymbolName: "grid", accessibilityDescription: "GridSnap")
        }

        let menu = NSMenu(title: "Gridded")
        menu.addItem(
            NSMenuItem(
                title: "About Gridded", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Preferences", action: #selector(openPreferences), keyEquivalent: ""))
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
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            preferencesWindow?.center()
            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.contentView = NSHostingView(rootView: view)
            preferencesWindow?.title = "Gridded Preferences"
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        if aboutWindow == nil {
            let view = AboutView()
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 250),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            aboutWindow?.center()
            aboutWindow?.isReleasedWhenClosed = false
            aboutWindow?.contentView = NSHostingView(rootView: view)
            aboutWindow?.title = "About Gridded"
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
