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

      Text("Version 0.0.1")
        .font(.subheadline)
        .foregroundColor(.secondary)

      Text("© 2025 An So")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
    .frame(width: 300, height: 250)
  }
}
