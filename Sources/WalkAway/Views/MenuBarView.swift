import AppKit
import SwiftUI

struct MenuBarView: View {
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var locker: Locker
  @EnvironmentObject private var metrics: MetricsMonitor
  @EnvironmentObject private var lockController: LockController
  @EnvironmentObject private var proximityMonitor: ProximityMonitor
  @State private var isCalibrationExpanded = false
  @State private var isAdvancedExpanded = false
  @State private var isDiagnosticsExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      statusHeader
      card { deviceSection }
      card { tuningSection }
      card { advancedSection }
      actionSection
    }
    .frame(width: 312)
    .padding(14)
    .controlSize(.small)
    .toggleStyle(.switch)
    .tint(.green)
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

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.primary.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )
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
          .background(isSelected(device) ? Color.green.opacity(0.14) : Color.clear)
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

      if settings.pauseWhileActive {
        sliderRow(
          title: "Confirm idle",
          value: Binding(
            get: { Double(settings.confirmIdleSeconds) },
            set: { settings.confirmIdleSeconds = Int($0.rounded()) }
          ),
          range: 5 ... 120,
          step: 5,
          label: Formatters.seconds(settings.confirmIdleSeconds)
        )
      }

      scheduleSection
    }
  }

  /// Full-width clickable disclosure header (the whole row toggles, not just the
  /// chevron). Used for Advanced / Calibration / Diagnostics.
  private func disclosureRow(_ title: String, systemImage: String? = nil, isExpanded: Binding<Bool>) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
    } label: {
      HStack(spacing: 8) {
        if let systemImage {
          Image(systemName: systemImage).foregroundStyle(.secondary)
        }
        Text(title)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .font(.caption)
  }

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Auto-lock schedule", isOn: $settings.lockScheduleEnabled)

      if settings.lockScheduleEnabled {
        timePickerRow(
          title: "From",
          selection: $settings.lockScheduleStartMinutes,
          options: Array(stride(from: 0, through: 1410, by: 30))
        )

        timePickerRow(
          title: "Until",
          selection: $settings.lockScheduleEndMinutes,
          options: Array(stride(from: 30, through: 1440, by: 30))
        )

        Text(settings.isWithinLockSchedule()
          ? "Active now — auto-lock on"
          : "Outside window — won't auto-lock now")
          .font(.caption2)
          .foregroundStyle(settings.isWithinLockSchedule() ? Color.green : Color.secondary)
      }
    }
  }

  private func timePickerRow(title: String, selection: Binding<Int>, options: [Int]) -> some View {
    HStack {
      Text(title)
      Spacer()
      Picker("", selection: selection) {
        ForEach(options, id: \.self) { minutes in
          Text(Self.clockLabel(minutes)).tag(minutes)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
    }
    .font(.caption)
  }

  private static func clockLabel(_ minutes: Int) -> String {
    let hour = (minutes / 60) % 24
    let minute = minutes % 60
    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    if let date = Calendar.current.date(from: components) {
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return formatter.string(from: date)
    }
    return String(format: "%02d:%02d", hour, minute)
  }

  private var advancedSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      disclosureRow("Advanced", isExpanded: $isAdvancedExpanded)

      if isAdvancedExpanded {
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

        Divider()
        diagnosticsSection
      }
    }
    .font(.caption)
  }

  private var calibrationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      disclosureRow("Calibration", isExpanded: $isCalibrationExpanded)

      if isCalibrationExpanded {
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
    // Snap to `step` in the binding so the track stays clean (no tick marks).
    let snapped = Binding<Double>(
      get: { value.wrappedValue },
      set: { value.wrappedValue = step > 0 ? (($0 / step).rounded() * step) : $0 }
    )
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Text(label)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .font(.caption)
      Slider(value: snapped, in: range)
    }
  }

  private var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      disclosureRow("Diagnostics", systemImage: "waveform.path.ecg", isExpanded: $isDiagnosticsExpanded)

      if isDiagnosticsExpanded {
        metricRow("Memory", String(format: "%.0f MB", metrics.memoryMB))
        metricRow("CPU (app)", String(format: "%.2f %%", metrics.cpuPercent))
        metricRow("Poll cost", String(format: "%.0f ms avg", metrics.avgPollMillis))
        metricRow("Locks", "\(metrics.lockCount)")
        metricRow("Away events", "\(metrics.awayCount)")
        metricRow("Deferred", "\(metrics.deferCount)")
        metricRow("Uptime", Formatters.seconds(metrics.uptimeSeconds))

        Button("Reset stats") { metrics.resetCounters() }
          .buttonStyle(.link)
          .font(.caption2)
          .padding(.top, 2)
      }
    }
    .font(.caption)
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      Text(value).monospacedDigit()
    }
    .font(.caption)
  }

  private var actionSection: some View {
    HStack(spacing: 10) {
      Button {
        locker.lockScreen()
      } label: {
        Label("Lock Now", systemImage: "lock.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Button(role: .destructive) {
        NSApplication.shared.terminate(nil)
      } label: {
        Label("Quit", systemImage: "power")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .keyboardShortcut("q")
    }
    .padding(.top, 2)
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
