//
//  GriddedApp.swift
//  Gridded
//
//  Created by An So on 2025-04-13.
//

import SwiftUI

struct AboutView: View {
  var body: some View {
    VStack(spacing: 20) {
      Image("AppIcon")
        .resizable()
        .frame(width: 64, height: 64)
        .cornerRadius(12)

      Text("Gridded")
        .font(.title)
        .bold()

      Text("A simple app that helps organizing windows by snapping them into grids.")
        .multilineTextAlignment(.center)
        .frame(width: 250)
        .lineLimit(nil)

      Text("Version 0.0.1")
        .font(.subheadline)
        .foregroundColor(.secondary)

      Text("Early access.")
        .multilineTextAlignment(.center)
        .frame(width: 250)
        .lineLimit(nil)

      Text("May be unstable.")
        .multilineTextAlignment(.center)
        .frame(width: 250)
        .lineLimit(nil)

      Text("© 2025 An So")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
  }
}

#Preview {
  AboutView()
}
