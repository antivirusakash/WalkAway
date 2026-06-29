@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class ProximityMonitor: NSObject, ObservableObject {
  @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
  @Published private(set) var smoothedRSSI: Int?
  @Published private(set) var lastRSSIDate: Date?
  @Published private(set) var bluetoothDescription = "Starting"
  @Published private(set) var isSelectedSystemDeviceVisible = false

  private let settings: SettingsStore
  private let lockController: LockController
  private let metrics: MetricsMonitor?
  /// Adaptive poll cadence: poll the (expensive) system_profiler source every
  /// `fastPollInterval` normally, backing off to `slowPollInterval` only while
  /// the watch is comfortably present. Snaps back to fast the moment the signal
  /// weakens, goes missing, or the watch starts leaving.
  /// Samples further than this from the window median are dropped as glitches
  /// before smoothing (RSSI spikes are impulsive).
  private let outlierRejectMarginDB = 12
  private let fastPollInterval: TimeInterval = 2
  private let slowPollInterval: TimeInterval = 5
  /// dB margin above the away threshold required before slowing down.
  private let comfortablePresentMarginDB = 6
  private var currentPollInterval: TimeInterval = 2
  private var centralManager: CBCentralManager!
  private var targetPeripheral: CBPeripheral?
  private var rssiTimer: Timer?
  private var noSignalTimer: Timer?
  private var systemBluetoothTimer: Timer?
  private var samples: [RSSISample] = []
  private let maxSampleCount = 5
  /// Discard RSSI readings older than this so a stale "near" value can never
  /// keep the watch marked present once fresh samples stop arriving.
  private let sampleMaxAge: TimeInterval = 10
  private var knownPeripherals: [UUID: CBPeripheral] = [:]
  private var systemBluetoothPollingStartDate = Date()
  private var lastSystemDeviceSeenDate: Date?

  init(settings: SettingsStore, lockController: LockController, metrics: MetricsMonitor? = nil) {
    self.settings = settings
    self.lockController = lockController
    self.metrics = metrics
    super.init()
    self.centralManager = CBCentralManager(delegate: self, queue: .main)
    self.noSignalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.checkNoSignalTimeout()
      }
    }
  }

  deinit {
    rssiTimer?.invalidate()
    noSignalTimer?.invalidate()
    systemBluetoothTimer?.invalidate()
  }

  func startScan() {
    discoveredDevices.removeAll()
    scanSystemBluetoothDevices()
    guard centralManager.state == .poweredOn else {
      updateBluetoothState(centralManager.state)
      return
    }
    lockController.scanning()
    centralManager.scanForPeripherals(withServices: nil, options: [
      CBCentralManagerScanOptionAllowDuplicatesKey: true
    ])
  }

  func stopScan() {
    centralManager.stopScan()
    if !settings.hasSelectedDevice {
      lockController.deviceMissing()
    }
  }

  func connectToSavedPeripheral() {
    guard settings.systemBluetoothAddress.isEmpty else {
      centralManager.stopScan()
      startSystemBluetoothPolling()
      return
    }

    guard let uuid = settings.peripheralUUID else {
      lockController.deviceMissing()
      startScan()
      return
    }

    guard centralManager.state == .poweredOn else {
      updateBluetoothState(centralManager.state)
      return
    }

    centralManager.stopScan()
    lockController.connecting()

    if let existing = targetPeripheral, existing.identifier == uuid {
      connect(existing)
      return
    }

    let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
    if let peripheral = knownPeripherals[uuid] ?? peripherals.first {
      connect(peripheral)
    } else {
      targetPeripheral = nil
      smoothedRSSI = nil
      lastRSSIDate = nil
      lockController.disconnected()
      startScan()
    }
  }

  func reconnect() {
    clearRSSI()
    connectToSavedPeripheral()
  }

  func selectedDeviceChanged() {
    rssiTimer?.invalidate()
    systemBluetoothTimer?.invalidate()
    isSelectedSystemDeviceVisible = false
    lastSystemDeviceSeenDate = nil
    if let targetPeripheral {
      centralManager.cancelPeripheralConnection(targetPeripheral)
    }
    targetPeripheral = nil
    clearRSSI()
    connectToSavedPeripheral()
  }

  private func connect(_ peripheral: CBPeripheral) {
    targetPeripheral = peripheral
    peripheral.delegate = self
    centralManager.connect(peripheral)
  }

  private func startRSSIPolling(for peripheral: CBPeripheral) {
    systemBluetoothTimer?.invalidate()
    rssiTimer?.invalidate()
    peripheral.readRSSI()
    rssiTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak peripheral] _ in
      peripheral?.readRSSI()
    }
  }

  private func startSystemBluetoothPolling() {
    rssiTimer?.invalidate()
    systemBluetoothPollingStartDate = Date()
    isSelectedSystemDeviceVisible = false
    lastSystemDeviceSeenDate = nil
    lockController.connecting()
    pollSystemBluetooth()
    currentPollInterval = fastPollInterval
    scheduleSystemBluetoothTimer()
  }

  private func scheduleSystemBluetoothTimer() {
    systemBluetoothTimer?.invalidate()
    systemBluetoothTimer = Timer.scheduledTimer(withTimeInterval: currentPollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.pollSystemBluetooth()
      }
    }
  }

  /// Reschedule the poll timer if the desired cadence changed.
  private func applyPollInterval() {
    let desired = desiredPollInterval()
    guard desired != currentPollInterval else { return }
    currentPollInterval = desired
    scheduleSystemBluetoothTimer()
  }

  private func desiredPollInterval() -> TimeInterval {
    // Only slow down when comfortably present with a strong, valid reading.
    guard case .present = lockController.state, let rssi = smoothedRSSI else {
      return fastPollInterval
    }
    let awayThresholdRSSI: Int
    if settings.useDistanceThreshold {
      awayThresholdRSSI = DistanceEstimator.rssiThreshold(
        forMeters: settings.lockDistanceMeters,
        referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
        pathLossExponent: settings.pathLossExponent
      )
    } else {
      awayThresholdRSSI = settings.rssiThreshold
    }
    // RSSI is dBm (negative); stronger = larger. Require a margin over threshold.
    return rssi >= awayThresholdRSSI + comfortablePresentMarginDB ? slowPollInterval : fastPollInterval
  }

  private func scanSystemBluetoothDevices() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let devices = SystemBluetoothSnapshot.load()
      DispatchQueue.main.async {
        guard let self else { return }
        self.mergeSystemBluetoothDevices(devices)
        self.autoSelectSystemAppleWatch(from: devices)
      }
    }
  }

  private func pollSystemBluetooth() {
    let targetAddress = SystemBluetoothSnapshot.normalizeAddress(settings.systemBluetoothAddress)
    guard !targetAddress.isEmpty else { return }

    DispatchQueue.global(qos: .utility).async { [weak self] in
      let pollStart = Date()
      let devices = SystemBluetoothSnapshot.load()
      let pollMillis = Date().timeIntervalSince(pollStart) * 1000
      DispatchQueue.main.async {
        guard let self else { return }
        self.metrics?.recordPoll(millis: pollMillis)
        self.mergeSystemBluetoothDevices(devices)
        if let device = devices.first(where: { $0.address == targetAddress }) {
          self.isSelectedSystemDeviceVisible = true
          self.lastSystemDeviceSeenDate = Date()

          if let rssi = device.rssi {
            self.pushRSSI(rssi)
          } else {
            self.markSignalLost()
            if self.settings.lockWhenRSSIMissing {
              self.lockController.evaluate(rssi: nil, reason: .noSignal)
            } else {
              self.lockController.deviceVisibleWithoutRSSI()
            }
          }
        } else {
          self.isSelectedSystemDeviceVisible = false
          self.evaluateMissingSystemDevice()
        }
        self.applyPollInterval()
      }
    }
  }

  private func checkNoSignalTimeout() {
    guard settings.hasSelectedDevice else { return }

    if !settings.systemBluetoothAddress.isEmpty {
      evaluateSystemDeviceTimeout()
      return
    }

    let now = Date()
    let lastRead = lastRSSIDate ?? .distantPast
    if now.timeIntervalSince(lastRead) >= TimeInterval(settings.noSignalTimeout) {
      smoothedRSSI = nil
      lockController.evaluate(rssi: nil, reason: .noSignal)
    }
  }

  private func pushRSSI(_ rssi: Int) {
    let now = Date()
    lastRSSIDate = now
    samples.append(RSSISample(value: rssi, time: now))
    samples.removeAll { now.timeIntervalSince($0.time) > sampleMaxAge }
    if samples.count > maxSampleCount {
      samples.removeFirst(samples.count - maxSampleCount)
    }
    let smoothed = robustSmoothed(samples.map(\.value))
    smoothedRSSI = smoothed
    let dist = DistanceEstimator.meters(
      rssi: smoothed,
      referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
      pathLossExponent: settings.pathLossExponent
    )
    WALog.decide("rssi raw=\(rssi) smoothed=\(smoothed) dist=\(String(format: "%.1f", dist))m samples=\(samples.count)")
    lockController.evaluate(rssi: smoothed)
  }

  /// Median after dropping samples far from the median — robust to single-
  /// sample RSSI spikes (unlike a plain mean).
  private func robustSmoothed(_ values: [Int]) -> Int {
    let med = Self.median(values)
    let kept = values.filter { abs($0 - med) <= outlierRejectMarginDB }
    return Self.median(kept.isEmpty ? values : kept)
  }

  private static func median(_ values: [Int]) -> Int {
    let sorted = values.sorted()
    let count = sorted.count
    guard count > 0 else { return 0 }
    if count % 2 == 1 { return sorted[count / 2] }
    return Int((Double(sorted[count / 2 - 1]) + Double(sorted[count / 2])) / 2.0)
  }

  private func clearRSSI() {
    samples.removeAll()
    smoothedRSSI = nil
    lastRSSIDate = nil
  }

  /// Mark the live signal lost for the UI and poll cadence WITHOUT discarding
  /// the smoothing window. Use on transient no-signal blips (timeouts, a single
  /// missing reading). Wiping `samples` here was a false-lock trigger: the watch
  /// throttles its radio and emits a depressed RSSI (~the away cutoff) instead
  /// of dropping cleanly. With history intact that reading is outlier-rejected;
  /// after a wipe it becomes the sole sample and smooths straight to the cutoff,
  /// arming a lock while the watch is on the desk. The window ages out on its
  /// own (sampleMaxAge) in pushRSSI, so a genuine departure still locks; only
  /// hard disconnect / device-change calls clearRSSI() to reset fully.
  private func markSignalLost() {
    smoothedRSSI = nil
    lastRSSIDate = nil
  }

  private func evaluateMissingSystemDevice() {
    let now = Date()
    let lastSeen = lastSystemDeviceSeenDate ?? systemBluetoothPollingStartDate
    if now.timeIntervalSince(lastSeen) >= TimeInterval(settings.noSignalTimeout) {
      markSignalLost()
      lockController.evaluate(rssi: nil, reason: .noSignal)
    }
  }

  private func evaluateSystemDeviceTimeout() {
    let now = Date()

    if let lastRead = lastRSSIDate,
       now.timeIntervalSince(lastRead) < TimeInterval(settings.noSignalTimeout) {
      return
    }

    if let lastSeen = lastSystemDeviceSeenDate,
       now.timeIntervalSince(lastSeen) < TimeInterval(settings.noSignalTimeout) {
      markSignalLost()
      isSelectedSystemDeviceVisible = true
      if settings.lockWhenRSSIMissing {
        lockController.evaluate(rssi: nil, reason: .noSignal)
      } else {
        lockController.deviceVisibleWithoutRSSI()
      }
      return
    }

    if lastSystemDeviceSeenDate == nil,
       now.timeIntervalSince(systemBluetoothPollingStartDate) < TimeInterval(settings.noSignalTimeout) {
      return
    }

    isSelectedSystemDeviceVisible = false
    markSignalLost()
    lockController.evaluate(rssi: nil, reason: .noSignal)
  }

  private func updateBluetoothState(_ state: CBManagerState) {
    switch state {
    case .poweredOn:
      bluetoothDescription = "On"
      connectToSavedPeripheral()
    case .poweredOff:
      bluetoothDescription = "Off"
      rssiTimer?.invalidate()
      lockController.bluetoothUnavailable("Bluetooth is off")
    case .resetting:
      bluetoothDescription = "Resetting"
      rssiTimer?.invalidate()
      lockController.bluetoothUnavailable("Bluetooth is resetting")
    case .unauthorized:
      bluetoothDescription = "Unauthorized"
      rssiTimer?.invalidate()
      lockController.bluetoothUnavailable("Bluetooth permission is missing")
    case .unsupported:
      bluetoothDescription = "Unsupported"
      rssiTimer?.invalidate()
      lockController.bluetoothUnavailable("Bluetooth is unsupported")
    case .unknown:
      bluetoothDescription = "Unknown"
      lockController.bluetoothUnavailable("Bluetooth state is unknown")
    @unknown default:
      bluetoothDescription = "Unavailable"
      lockController.bluetoothUnavailable("Bluetooth is unavailable")
    }
  }

  private func mergeSystemBluetoothDevices(_ devices: [SystemBluetoothDevice]) {
    for device in devices {
      let discovered = discoveredDevice(from: device)
      if let index = discoveredDevices.firstIndex(where: { $0.id == discovered.id }) {
        discoveredDevices[index] = discovered
      } else {
        discoveredDevices.append(discovered)
      }
    }

    discoveredDevices.sort {
      let lhsRSSI = $0.rssi ?? Int.min
      let rhsRSSI = $1.rssi ?? Int.min
      if lhsRSSI != rhsRSSI {
        return lhsRSSI > rhsRSSI
      }
      return $0.displayName < $1.displayName
    }
  }

  private func autoSelectSystemAppleWatch(from devices: [SystemBluetoothDevice]) {
    guard !settings.hasSelectedDevice else { return }
    guard let watch = devices.first(where: {
      $0.normalizedName.localizedCaseInsensitiveContains("Apple Watch")
    }) else {
      return
    }

    settings.select(device: discoveredDevice(from: watch))
    startSystemBluetoothPolling()
  }

  private func discoveredDevice(from device: SystemBluetoothDevice) -> DiscoveredDevice {
    DiscoveredDevice(
      id: "system:\(device.address)",
      name: device.normalizedName,
      rssi: device.rssi,
      source: .systemBluetooth,
      peripheralUUID: nil,
      bluetoothAddress: device.address
    )
  }
}

private struct RSSISample {
  let value: Int
  let time: Date
}

extension ProximityMonitor: CBCentralManagerDelegate {
  nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
    Task { @MainActor in
      self.updateBluetoothState(central.state)
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    Task { @MainActor in
      let name = peripheral.name
        ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ?? ""
      self.knownPeripherals[peripheral.identifier] = peripheral
      let device = DiscoveredDevice(
        id: "core:\(peripheral.identifier.uuidString)",
        name: name,
        rssi: RSSI.intValue,
        source: .coreBluetooth,
        peripheralUUID: peripheral.identifier,
        bluetoothAddress: nil
      )
      if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
        self.discoveredDevices[index] = device
      } else {
        self.discoveredDevices.append(device)
      }
      self.discoveredDevices.sort {
        ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min)
      }
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Task { @MainActor in
      self.bluetoothDescription = "On"
      self.targetPeripheral = peripheral
      self.startRSSIPolling(for: peripheral)
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    Task { @MainActor in
      self.clearRSSI()
      self.lockController.disconnected()
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    Task { @MainActor in
      self.rssiTimer?.invalidate()
      self.clearRSSI()
      self.lockController.disconnected()
      self.connectToSavedPeripheral()
    }
  }
}

extension ProximityMonitor: CBPeripheralDelegate {
  nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    Task { @MainActor in
      guard error == nil else {
        self.lockController.evaluate(rssi: nil, reason: .noSignal)
        return
      }
      self.pushRSSI(RSSI.intValue)
    }
  }
}
