//
//  Configuration.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import Combine
import Foundation
import ServiceManagement
import Logging

final class Configuration: ObservableObject {
  let logger = Logger(label: "Configuration")
  
  @Published var columns: Int
  @Published var rows: Int
  @Published var autoStart: Bool
  @Published var activateKey: Int
  @Published var accessibilityPermission: Bool = false

  static let shared = Configuration()

  private var cancellables = Set<AnyCancellable>()

  private init() {
    let defaults = UserDefaults.standard
    columns = defaults.integer(forKey: "gridColumns")
    rows = defaults.integer(forKey: "gridRows")
    autoStart = defaults.bool(forKey: "autoStart")
    activateKey = defaults.integer(forKey: "activateKey")
    
    if columns == 0 { columns = 3 }
    if rows == 0 { rows = 3 }
    if activateKey == 0 { activateKey = 49 }

    $columns
      .sink { defaults.set($0, forKey: "gridColumns") }
      .store(in: &cancellables)

    $rows
      .sink { defaults.set($0, forKey: "gridRows") }
      .store(in: &cancellables)

    $autoStart
      .sink {
        defaults.set($0, forKey: "autoStart")
        self.autoStart($0)
      }
      .store(in: &cancellables)

    $activateKey
      .sink {
        defaults.set($0, forKey: "activateKey")
        if (EventMonitor.shared.isMonitoring) {
          EventMonitor.shared.restart()          
        }
      }
      .store(in: &cancellables)
  }

  private func autoStart(_ start: Bool) {
    do {
      if start {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      logger.warning("Failed to register auto start: \(error)")
    }
  }
}
