import AppKit
import SwiftUI

struct MenuBarView: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var locker: Locker
  @EnvironmentObject private var license: LicenseStore
  @EnvironmentObject private var lockController: LockController
  @EnvironmentObject private var proximityMonitor: ProximityMonitor
  @State private var isCalibrationExpanded = false
  @State private var isAdvancedExpanded = false
  @State private var isEnteringKey = false
  @State private var keyInput = ""
  @State private var activationFailed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      statusHeader
      Divider()
      deviceSection
      Divider()
      tuningSection
      Divider()
      licenseSection
      Divider()
      actionSection
    }
    .frame(width: 300)
    .padding(16)
    .controlSize(.small)
    .onAppear {
      settings.refreshLaunchAtLoginStatus()
      if !settings.hasSelectedDevice {
        proximityMonitor.startScan()
      }
    }
    .onChange(of: settings.peripheralUUID) { _ in
      proximityMonitor.selectedDeviceChanged()
    }
    .onChange(of: settings.systemBluetoothAddress) { _ in
      proximityMonitor.selectedDeviceChanged()
    }
  }

  private var statusHeader: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: statusIconName)
          .font(.system(size: 26, weight: .medium))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(statusColor)

        Circle()
          .fill(isConnected ? Color.green : Color.secondary.opacity(0.45))
          .frame(width: 8, height: 8)
          .overlay {
            Circle()
              .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
          }
          .offset(x: 3, y: 1)
      }
      .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(statusTitle)
          .font(.system(.headline, design: .rounded).weight(.semibold))
          .foregroundStyle(statusColor)
        Text(statusDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()
    }
  }

  private var statusDetail: String {
    switch lockController.state {
    case let .bluetoothUnavailable(message):
      return message
    case let .leaving(deadline):
      let remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
      return "Locking in \(Formatters.seconds(remaining))"
    default:
      let deviceName = settings.peripheralName.isEmpty ? "No watch selected" : settings.peripheralName
      return "\(deviceName) · \(readingSummary)"
    }
  }

  private var statusTitle: String {
    if isNearbyArmed {
      return "Nearby"
    }
    return lockController.state.title
  }

  private var statusIconName: String {
    isNearbyArmed ? "checkmark.shield" : lockController.statusIcon
  }

  private var readingSummary: String {
    let rssi = proximityMonitor.smoothedRSSI
    if rssi == nil, proximityMonitor.isSelectedSystemDeviceVisible {
      return "Connected"
    }

    guard settings.useDistanceThreshold || isNearbyArmed else {
      return Formatters.rssi(rssi)
    }

    return "\(Formatters.meters(estimatedDistance)) · \(Formatters.rssi(rssi))"
  }

  private var statusColor: Color {
    switch lockController.state {
    case .present where isConnected, .locked:
      return .green
    case .leaving:
      return .orange
    case .bluetoothUnavailable:
      return .red
    default:
      return isConnected ? .green : .secondary
    }
  }

  private var isConnected: Bool {
    proximityMonitor.smoothedRSSI != nil || proximityMonitor.isSelectedSystemDeviceVisible
  }

  private var isNearbyArmed: Bool {
    guard isConnected, lockController.state == .present, let estimatedDistance else {
      return false
    }
    return estimatedDistance <= 1
  }

  private var deviceSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "applewatch")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(settings.hasSelectedDevice ? watchDisplayName : "Pick a watch")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text(deviceStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        Button {
          proximityMonitor.startScan()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("Rescan")

        if settings.hasSelectedDevice {
          deviceActionsMenu
        }
      }

      if !settings.hasSelectedDevice || !proximityMonitor.discoveredDevices.isEmpty {
        deviceList
      }
    }
  }

  private var deviceActionsMenu: some View {
    Menu {
      Button("Reconnect") {
        proximityMonitor.reconnect()
      }
      Button("Forget Device") {
        settings.forgetDevice()
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .help("Device actions")
  }

  private var deviceList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 6) {
        ForEach(proximityMonitor.discoveredDevices) { device in
          Button {
            settings.select(device: device)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                  .font(.subheadline)
                  .lineLimit(1)
                Text(device.subtitle)
                  .font(.caption2.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              if isSelected(device) {
                Image(systemName: "checkmark")
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(6)
          .background(isSelected(device) ? Color.accentColor.opacity(0.14) : Color.clear)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }

        if proximityMonitor.discoveredDevices.isEmpty {
          Text("Scanning for nearby BLE devices")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
      }
    }
    .frame(maxHeight: 128)
  }

  private var tuningSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Lock by distance", isOn: $settings.useDistanceThreshold)

      if settings.useDistanceThreshold {
        sliderRow(
          title: "Distance",
          value: $settings.lockDistanceMeters,
          range: 2 ... 20,
          step: 0.5,
          label: Formatters.meters(settings.lockDistanceMeters)
        )

        if let estimatedDistance {
          HStack {
            Text("Current")
            Spacer()
            Text(Formatters.meters(estimatedDistance))
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .font(.caption)
        }
      }

      sliderRow(
        title: "Lock delay",
        value: Binding(
          get: { Double(settings.graceSeconds) },
          set: { settings.graceSeconds = Int($0.rounded()) }
        ),
        range: 1 ... 30,
        step: 1,
        label: Formatters.seconds(settings.graceSeconds)
      )

      Toggle("Pause while active", isOn: $settings.pauseWhileActive)
      advancedSection
    }
  }

  private var advancedSection: some View {
    DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        sliderRow(
          title: "Missing signal",
          value: Binding(
            get: { Double(settings.noSignalTimeout) },
            set: { settings.noSignalTimeout = Int($0.rounded()) }
          ),
          range: 3 ... 60,
          step: 1,
          label: Formatters.seconds(settings.noSignalTimeout)
        )

        if settings.useDistanceThreshold {
          Toggle("Lock when signal is lost", isOn: $settings.lockWhenRSSIMissing)
        } else {
          sliderRow(
            title: "RSSI threshold",
            value: Binding(
              get: { Double(settings.rssiThreshold) },
              set: { settings.rssiThreshold = Int($0.rounded()) }
            ),
            range: -95 ... -45,
            step: 1,
            label: "\(settings.rssiThreshold) dBm"
          )
        }

        Toggle("Lock if Bluetooth drops", isOn: $settings.lockOnBluetoothUnavailable)
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { settings.launchAtLoginEnabled },
            set: { settings.setLaunchAtLogin($0) }
          )
        )

        if proximityMonitor.smoothedRSSI != nil {
          Divider()
          calibrationSection
        }
      }
      .padding(.top, 6)
    }
    .font(.caption)
  }

  private var calibrationSection: some View {
    DisclosureGroup("Calibration", isExpanded: $isCalibrationExpanded) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Button("Set 1 m") {
            if let rssi = proximityMonitor.smoothedRSSI {
              settings.referenceRSSIAtOneMeter = rssi
              updatePathLossFromCalibration()
            }
          }

          Button("Set 2 m") {
            if let rssi = proximityMonitor.smoothedRSSI {
              settings.referenceRSSIAtTwoMeters = rssi
              updatePathLossFromCalibration()
            }
          }
        }

        HStack {
          Button("Set away point") {
            if let rssi = proximityMonitor.smoothedRSSI {
              settings.pathLossExponent = DistanceEstimator.pathLossExponent(
                referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
                rssiAtKnownDistance: rssi,
                knownDistanceMeters: settings.lockDistanceMeters
              )
              if abs(settings.lockDistanceMeters - 2) <= 0.25 {
                settings.referenceRSSIAtTwoMeters = rssi
              }
            }
          }

          Spacer()

          Text(Formatters.rssi(proximityMonitor.smoothedRSSI))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }

        HStack {
          Text("1 m \(settings.referenceRSSIAtOneMeter) dBm")
          Spacer()
          Text("2 m \(settings.referenceRSSIAtTwoMeters) dBm · n \(Formatters.decimal(settings.pathLossExponent))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
      }
      .padding(.top, 4)
    }
    .font(.caption)
  }

  private func sliderRow(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    label: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
        Spacer()
        Text(label)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .font(.caption)
      Slider(value: value, in: range, step: step)
    }
  }

  @ViewBuilder
  private var licenseSection: some View {
    switch license.status {
    case let .licensed(payload):
      HStack(spacing: 6) {
        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        Text("Licensed").fontWeight(.medium)
        Spacer()
        Text(payload).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      .font(.caption)

    case let .trial(daysLeft):
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "clock").foregroundStyle(.secondary)
          Text("Trial · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left").font(.caption)
          Spacer()
          buyButton
        }
        licenseEntry
      }

    case .expired:
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text("Trial ended — auto-lock paused").font(.caption).fontWeight(.medium)
        }
        HStack {
          buyButton
          Spacer()
        }
        licenseEntry
      }
    }
  }

  private var buyButton: some View {
    Button("Buy · $4.99") {
      NSWorkspace.shared.open(LicenseStore.purchaseURL)
    }
    .font(.caption)
  }

  @ViewBuilder
  private var licenseEntry: some View {
    if isEnteringKey {
      VStack(alignment: .leading, spacing: 4) {
        TextField("Paste license key", text: $keyInput, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...3)
          .font(.caption)
        HStack {
          Button("Activate") {
            if license.activate(keyInput) {
              isEnteringKey = false
              activationFailed = false
              keyInput = ""
            } else {
              activationFailed = true
            }
          }
          .font(.caption)
          if activationFailed {
            Text("Invalid key").foregroundStyle(.red).font(.caption2)
          }
          Spacer()
        }
      }
    } else {
      Button("Enter license key") { isEnteringKey = true }
        .buttonStyle(.link)
        .font(.caption)
    }
  }

  private var actionSection: some View {
    HStack {
      Button {
        locker.lockScreen()
      } label: {
        Label("Lock Now", systemImage: "lock")
      }

      Spacer()

      Button(role: .destructive) {
        NSApplication.shared.terminate(nil)
      } label: {
        Label("Quit", systemImage: "xmark.circle")
      }
      .keyboardShortcut("q")
    }
  }

  private var watchDisplayName: String {
    settings.peripheralName.isEmpty ? "Selected watch" : settings.peripheralName
  }

  private var deviceStatusText: String {
    if !settings.hasSelectedDevice {
      return "No watch selected"
    }
    if proximityMonitor.smoothedRSSI != nil {
      return "Connected"
    }
    if proximityMonitor.isSelectedSystemDeviceVisible {
      return "Connected"
    }
    return "Not visible"
  }

  private var estimatedDistance: Double? {
    guard let rssi = proximityMonitor.smoothedRSSI else { return nil }
    return DistanceEstimator.meters(
      rssi: rssi,
      referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
      pathLossExponent: settings.pathLossExponent
    )
  }

  private func updatePathLossFromCalibration() {
    settings.pathLossExponent = DistanceEstimator.pathLossExponent(
      referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
      rssiAtKnownDistance: settings.referenceRSSIAtTwoMeters,
      knownDistanceMeters: 2
    )
  }

  private func isSelected(_ device: DiscoveredDevice) -> Bool {
    if let uuid = device.peripheralUUID {
      return settings.peripheralUUID == uuid
    }
    if let address = device.bluetoothAddress {
      return settings.systemBluetoothAddress == address
    }
    return false
  }
}
