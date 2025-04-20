//
//  PreferencesView.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject var config = Configuration.shared

  @State private var showAlert: Bool = true

  var body: some View {
    VStack {
      Toggle(isOn: $config.autoStart) {
        Text("Auto start")
      }

      Divider()

      VStack {
        if config.accessibilityPermission {
          Text("✅ Accessibility permission granted")
        } else {
          VStack {
            Text("❌ Accessibility permission not granted")
            Button("Grant permission") {
              let url = URL(
                string:
                  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              )!
              NSWorkspace.shared.open(url)
            }
            Button("Check permission again") {
              EventMonitor.shared.restart()
            }
            Text(
              "If the app is already in the list and granted permission but it still doesn't work, try removing the app from the list and restart the app."
            )
            .frame(width: 350)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
          }
        }
      }
      .padding(10)

      Divider()

      VStack {
        Text("Activate grid snapping by pressing space key when dragging a window.")
          .frame(width: 350)
          .multilineTextAlignment(.center)
          .lineLimit(nil)
        Text("This will be customizable in the future.")
          .font(.footnote)
      }
      .padding(10)

      Divider()

      VStack {
        Text("Grid layout")
        HStack {
          Form {
            HStack {
              Text("Columns")
              Spacer()
              Stepper(value: $config.columns, in: 1...24) {
                Text("\(config.columns)")
              }
            }
            HStack {
              Text("Rows")
              Spacer()
              Stepper(value: $config.rows, in: 1...24) {
                Text("\(config.rows)")
              }
            }
          }
          .frame(width: 200)

          GridPreview(rows: config.rows, columns: config.columns)
            .frame(width: 120, height: 75)
            .border(Color.gray)

        }
        Text("Tip: you may drag the window across multiple grids.")
          .font(.footnote)
      }
      .padding(10)
    }
    .padding(10)
    .environmentObject(Configuration.shared)
  }
}

struct GridPreview: View {
  let rows: Int
  let columns: Int

  var body: some View {
    GeometryReader { geometry in
      let cellWidth = geometry.size.width / CGFloat(columns)
      let cellHeight = geometry.size.height / CGFloat(rows)

      ForEach(0..<rows, id: \.self) { row in
        ForEach(0..<columns, id: \.self) { column in
          Rectangle()
            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            .frame(width: cellWidth, height: cellHeight)
            .position(
              x: cellWidth * CGFloat(column) + cellWidth / 2,
              y: cellHeight * CGFloat(row) + cellHeight / 2
            )
        }
      }
    }
  }
}

#Preview {
  PreferencesView()
}
