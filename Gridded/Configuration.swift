//
//  Configuration.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import Combine
import Foundation

final class Configuration: ObservableObject {
    @Published var columns: Int
    @Published var rows: Int

    static let shared = Configuration()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let defaults = UserDefaults.standard
        columns = defaults.integer(forKey: "gridColumns")
        rows = defaults.integer(forKey: "gridRows")

        if columns == 0 { columns = 3 }
        if rows == 0 { rows = 3 }

        $columns
            .sink { defaults.set($0, forKey: "gridColumns") }
            .store(in: &cancellables)

        $rows
            .sink { defaults.set($0, forKey: "gridRows") }
            .store(in: &cancellables)

    }
}
