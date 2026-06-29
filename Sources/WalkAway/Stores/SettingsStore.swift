import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
  @Published var peripheralUUID: UUID? {
    didSet { savePeripheralUUID() }
  }

  @Published var systemBluetoothAddress: String {
    didSet { defaults.set(systemBluetoothAddress, forKey: Keys.systemBluetoothAddress) }
  }

  @Published var peripheralName: String {
    didSet { defaults.set(peripheralName, forKey: Keys.peripheralName) }
  }

  @Published var rssiThreshold: Int {
    didSet { defaults.set(rssiThreshold, forKey: Keys.rssiThreshold) }
  }

  @Published var useDistanceThreshold: Bool {
    didSet { defaults.set(useDistanceThreshold, forKey: Keys.useDistanceThreshold) }
  }

  @Published var lockDistanceMeters: Double {
    didSet {
      if lockDistanceMeters < 2 {
        lockDistanceMeters = 2
        return
      }
      defaults.set(lockDistanceMeters, forKey: Keys.lockDistanceMeters)
    }
  }

  @Published var referenceRSSIAtOneMeter: Int {
    didSet { defaults.set(referenceRSSIAtOneMeter, forKey: Keys.referenceRSSIAtOneMeter) }
  }

  @Published var pathLossExponent: Double {
    didSet { defaults.set(pathLossExponent, forKey: Keys.pathLossExponent) }
  }

  @Published var referenceRSSIAtTwoMeters: Int {
    didSet { defaults.set(referenceRSSIAtTwoMeters, forKey: Keys.referenceRSSIAtTwoMeters) }
  }

  @Published var lockWhenRSSIMissing: Bool {
    didSet { defaults.set(lockWhenRSSIMissing, forKey: Keys.lockWhenRSSIMissing) }
  }

  @Published var graceSeconds: Int {
    didSet { defaults.set(graceSeconds, forKey: Keys.graceSeconds) }
  }

  @Published var noSignalTimeout: Int {
    didSet { defaults.set(noSignalTimeout, forKey: Keys.noSignalTimeout) }
  }

  @Published var pauseWhileActive: Bool {
    didSet { defaults.set(pauseWhileActive, forKey: Keys.pauseWhileActive) }
  }

  /// While "Pause while active" is on and the display is awake, require this
  /// many seconds with no keyboard/mouse input before an auto-lock is allowed.
  /// Positive "the user actually left" evidence that a noisy BLE away reading
  /// can't fake — stops false locks while you sit at the desk. Bypassed the
  /// instant the display sleeps (you're clearly not at the screen then).
  @Published var confirmIdleSeconds: Int {
    didSet { defaults.set(confirmIdleSeconds, forKey: Keys.confirmIdleSeconds) }
  }

  @Published var lockOnBluetoothUnavailable: Bool {
    didSet { defaults.set(lockOnBluetoothUnavailable, forKey: Keys.lockOnBluetoothUnavailable) }
  }

  /// When on, WalkAway only auto-locks inside the [start, end) window below.
  @Published var lockScheduleEnabled: Bool {
    didSet { defaults.set(lockScheduleEnabled, forKey: Keys.lockScheduleEnabled) }
  }

  /// Auto-lock window as minutes since midnight. Default 09:00–17:00.
  @Published var lockScheduleStartMinutes: Int {
    didSet { defaults.set(lockScheduleStartMinutes, forKey: Keys.lockScheduleStartMinutes) }
  }

  @Published var lockScheduleEndMinutes: Int {
    didSet { defaults.set(lockScheduleEndMinutes, forKey: Keys.lockScheduleEndMinutes) }
  }

  @Published private(set) var launchAtLoginEnabled: Bool

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.peripheralUUID = defaults.string(forKey: Keys.peripheralUUID).flatMap(UUID.init(uuidString:))
    self.systemBluetoothAddress = defaults.string(forKey: Keys.systemBluetoothAddress) ?? ""
    self.peripheralName = defaults.string(forKey: Keys.peripheralName) ?? ""
    self.rssiThreshold = defaults.object(forKey: Keys.rssiThreshold) as? Int ?? -75
    self.useDistanceThreshold = defaults.object(forKey: Keys.useDistanceThreshold) as? Bool ?? true
    self.lockDistanceMeters = max(2, defaults.object(forKey: Keys.lockDistanceMeters) as? Double ?? 6)
    self.referenceRSSIAtOneMeter = defaults.object(forKey: Keys.referenceRSSIAtOneMeter) as? Int ?? -55
    self.pathLossExponent = defaults.object(forKey: Keys.pathLossExponent) as? Double ?? 2.2
    self.referenceRSSIAtTwoMeters = defaults.object(forKey: Keys.referenceRSSIAtTwoMeters) as? Int ?? -62
    self.lockWhenRSSIMissing = defaults.object(forKey: Keys.lockWhenRSSIMissing) as? Bool ?? true
    self.graceSeconds = defaults.object(forKey: Keys.graceSeconds) as? Int ?? 5
    self.noSignalTimeout = defaults.object(forKey: Keys.noSignalTimeout) as? Int ?? 5
    self.pauseWhileActive = defaults.object(forKey: Keys.pauseWhileActive) as? Bool ?? true
    self.confirmIdleSeconds = defaults.object(forKey: Keys.confirmIdleSeconds) as? Int ?? 20
    self.lockOnBluetoothUnavailable = defaults.object(forKey: Keys.lockOnBluetoothUnavailable) as? Bool ?? false
    self.lockScheduleEnabled = defaults.object(forKey: Keys.lockScheduleEnabled) as? Bool ?? false
    self.lockScheduleStartMinutes = defaults.object(forKey: Keys.lockScheduleStartMinutes) as? Int ?? 9 * 60
    self.lockScheduleEndMinutes = defaults.object(forKey: Keys.lockScheduleEndMinutes) as? Int ?? 17 * 60
    self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    applyReliabilityMigrationIfNeeded()
    applyDistanceDefaultMigrationIfNeeded()
  }

  /// One-time push of the 6 m lock distance to every install (including users
  /// who previously set a custom distance), and turns lock-by-distance on so
  /// the value takes effect. Runs once; users can still adjust afterwards.
  private func applyDistanceDefaultMigrationIfNeeded() {
    guard !defaults.bool(forKey: Keys.distanceDefaultV2) else { return }
    useDistanceThreshold = true
    lockDistanceMeters = 6
    defaults.set(true, forKey: Keys.distanceDefaultV2)
  }

  /// One-time bump so existing installs get the reliable away-detection
  /// behaviour without manual toggling: missing RSSI counts as away, and the
  /// old 10s no-signal timeout is shortened to 5s. Runs once; users can still
  /// change either value afterwards.
  private func applyReliabilityMigrationIfNeeded() {
    guard !defaults.bool(forKey: Keys.reliabilityDefaultsV1) else { return }
    lockWhenRSSIMissing = true
    if noSignalTimeout == 10 {
      noSignalTimeout = 5
    }
    defaults.set(true, forKey: Keys.reliabilityDefaultsV1)
  }

  /// Whether auto-lock is permitted right now. Always true unless a schedule is
  /// enabled, in which case only inside the [start, end) window. Supports a
  /// window that wraps past midnight (start > end, e.g. 22:00–06:00).
  func isWithinLockSchedule(_ date: Date = Date()) -> Bool {
    guard lockScheduleEnabled else { return true }
    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
    let now = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    let start = lockScheduleStartMinutes
    let end = lockScheduleEndMinutes
    if start == end { return false }
    if start < end { return now >= start && now < end }
    return now >= start || now < end
  }

  func select(device: DiscoveredDevice) {
    peripheralUUID = device.peripheralUUID
    systemBluetoothAddress = device.bluetoothAddress ?? ""
    peripheralName = device.displayName
  }

  func forgetDevice() {
    peripheralUUID = nil
    systemBluetoothAddress = ""
    peripheralName = ""
  }

  var hasSelectedDevice: Bool {
    peripheralUUID != nil || !systemBluetoothAddress.isEmpty
  }

  func refreshLaunchAtLoginStatus() {
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      NSLog("WalkAway launch-at-login update failed: \(error.localizedDescription)")
    }
    refreshLaunchAtLoginStatus()
  }

  private func savePeripheralUUID() {
    if let peripheralUUID {
      defaults.set(peripheralUUID.uuidString, forKey: Keys.peripheralUUID)
    } else {
      defaults.removeObject(forKey: Keys.peripheralUUID)
    }
  }
}

private enum Keys {
  static let peripheralUUID = "peripheralUUID"
  static let systemBluetoothAddress = "systemBluetoothAddress"
  static let peripheralName = "peripheralName"
  static let rssiThreshold = "rssiThreshold"
  static let useDistanceThreshold = "useDistanceThreshold"
  static let lockDistanceMeters = "lockDistanceMeters"
  static let referenceRSSIAtOneMeter = "referenceRSSIAtOneMeter"
  static let pathLossExponent = "pathLossExponent"
  static let referenceRSSIAtTwoMeters = "referenceRSSIAtTwoMeters"
  static let lockWhenRSSIMissing = "lockWhenRSSIMissing"
  static let graceSeconds = "graceSeconds"
  static let noSignalTimeout = "noSignalTimeout"
  static let pauseWhileActive = "pauseWhileActive"
  static let confirmIdleSeconds = "confirmIdleSeconds"
  static let lockOnBluetoothUnavailable = "lockOnBluetoothUnavailable"
  static let reliabilityDefaultsV1 = "reliabilityDefaultsV1"
  static let distanceDefaultV2 = "distanceDefaultV2"
  static let lockScheduleEnabled = "lockScheduleEnabled"
  static let lockScheduleStartMinutes = "lockScheduleStartMinutes"
  static let lockScheduleEndMinutes = "lockScheduleEndMinutes"
}
