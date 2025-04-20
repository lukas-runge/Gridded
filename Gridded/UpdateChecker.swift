import AppKit
import Foundation
import Logging

public class UpdateChecker {
  let logger = Logger(label: "UpdateChecker")

  public static let shared = UpdateChecker()

  private let releasesURL = URL(
  string: "https://api.github.com/repos/gentlespoon/gridded/releases")!

  public func checkForUpdates() async {
  do {
    let (data, _) = try await URLSession.shared.data(from: releasesURL)
    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

    guard let latestRelease = releases.first else { return }

    let currentVersion =
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"

    logger.info("Current version: \(currentVersion), latest version: \(latestRelease.tag_name)")
    let isUpdateAvailable =
    compareVersions(currentVersion, latestRelease.tag_name) == .orderedAscending

    if isUpdateAvailable {
    await MainActor.run {
      showUpdateAlert(latestVersion: latestRelease.tag_name, htmlUrl: latestRelease.html_url)
    }
    }
  } catch {
    print("Failed to check for updates: \(error)")
  }
  }

  private func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
  return version1.compare(version2, options: .numeric)
  }

  private func showUpdateAlert(latestVersion: String, htmlUrl: String) {
  let alert = NSAlert()
  alert.messageText = "Update Available"
  alert.informativeText = "A new version \(latestVersion) is available!"
  alert.alertStyle = .informational
  alert.addButton(withTitle: "Download")
  alert.addButton(withTitle: "Later")

  if alert.runModal() == .alertFirstButtonReturn {
    if let url = URL(string: htmlUrl) {
    NSWorkspace.shared.open(url)
    }
  }
  }
}

public struct GitHubRelease: Codable {
  public let tag_name: String
  public let html_url: String
  public let body: String
}
