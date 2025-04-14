//
//  GriddedApp.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import SwiftUI

@main
struct GriddedApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        EventMonitor.shared.start()
    }

    var body: some Scene {}
    
}
