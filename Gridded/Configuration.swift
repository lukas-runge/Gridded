//
//  Configuration.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import Combine
import Foundation
import Logging
import ServiceManagement

final class Configuration: ObservableObject {
  let logger = Logger(label: "Configuration")

  @Published var columns: Int
  @Published var rows: Int
  @Published var autoStart: Bool
  @Published var activateKey: Int
  @Published var constrainMouse: Bool
  @Published var accessibilityPermission: Bool = false

  static let shared = Configuration()

  private var cancellables = Set<AnyCancellable>()

  private init() {
    let defaults = UserDefaults.standard
    columns = defaults.getValue(forKey: "gridColumns") ?? 3
    rows = defaults.getValue(forKey: "gridRows") ?? 3
    autoStart = defaults.getValue(forKey: "autoStart") ?? false
    activateKey = defaults.getValue(forKey: "activateKey") ?? 49
    constrainMouse = defaults.getValue(forKey: "constrainMouse") ?? true

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
        if EventMonitor.shared.isMonitoring {
          EventMonitor.shared.restart()
        }
      }
      .store(in: &cancellables)

    $constrainMouse
      .sink { defaults.set($0, forKey: "constrainMouse") }
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

// Extension to check if a key exists in UserDefaults
extension UserDefaults {
  func getValue<T>(forKey key: String) -> T? {
    return object(forKey: key) as? T
  }
}
