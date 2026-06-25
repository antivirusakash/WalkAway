import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@main
struct WalkAwayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var settings = SettingsStore()
  @StateObject private var locker = Locker()
  @StateObject private var metrics = MetricsMonitor()
  @StateObject private var lockController: LockController
  @StateObject private var proximityMonitor: ProximityMonitor

  init() {
    let settings = SettingsStore()
    let locker = Locker()
    let metrics = MetricsMonitor()
    let lockController = LockController(settings: settings, locker: locker, metrics: metrics)
    let proximityMonitor = ProximityMonitor(
      settings: settings,
      lockController: lockController,
      metrics: metrics
    )

    _settings = StateObject(wrappedValue: settings)
    _locker = StateObject(wrappedValue: locker)
    _metrics = StateObject(wrappedValue: metrics)
    _lockController = StateObject(wrappedValue: lockController)
    _proximityMonitor = StateObject(wrappedValue: proximityMonitor)
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView()
        .environmentObject(settings)
        .environmentObject(locker)
        .environmentObject(metrics)
        .environmentObject(lockController)
        .environmentObject(proximityMonitor)
    } label: {
      MenuBarStatusIcon(
        title: lockController.menuTitle(rssi: proximityMonitor.smoothedRSSI),
        isConnected: proximityMonitor.smoothedRSSI != nil
      )
    }
    .menuBarExtraStyle(.window)
  }
}

struct MenuBarStatusIcon: View {
  let title: String
  let isConnected: Bool

  var body: some View {
    if let image = NSImage.walkAwayStatusIcon {
      Image(nsImage: image)
        .foregroundStyle(isConnected ? Color.green : Color.secondary)
        .accessibilityLabel(title)
    } else {
      Label(title, systemImage: "lock")
        .foregroundStyle(isConnected ? Color.green : Color.secondary)
    }
  }
}

private extension NSImage {
  static var walkAwayStatusIcon: NSImage? {
    guard let url = Bundle.main.url(forResource: "WalkAwayStatusIcon", withExtension: "png"),
          let image = NSImage(contentsOf: url) else {
      return nil
    }
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    return image
  }
}
