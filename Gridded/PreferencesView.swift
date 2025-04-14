//
//  PreferencesView.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var config = Configuration.shared

    var body: some View {
        VStack {
            VStack {
                Text("Activate grid snapping by...")
                Text("Pressing space key when dragging a window.")
                Text("This will be customizable in the future.")
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
