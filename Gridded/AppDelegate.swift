//
//  AppDelegate.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//


import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}


