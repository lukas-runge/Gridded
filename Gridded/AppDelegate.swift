//
//  AppDelegate.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        // Check for updates
        Task {
            await UpdateChecker.shared.checkForUpdates()
        }
    }
}
