import Foundation

@MainActor
final class LockController: ObservableObject {
  @Published private(set) var state: PresenceState = .noDevice

  var statusIcon: String {
    switch state {
    case .noDevice:
      return "applewatch"
    case .bluetoothUnavailable:
      return "antenna.radiowaves.left.and.right.slash"
    case .scanning:
      return "dot.radiowaves.left.and.right"
    case .connecting:
      return "link"
    case .present:
      return "lock.open"
    case .leaving:
      return "timer"
    case .locked:
      return "lock"
    }
  }

  private let settings: SettingsStore
  private let locker: Locker
  /// Returns true while the app is licensed or in trial. Auto-lock is disabled
  /// when this is false (trial expired, unlicensed).
  private let isEntitled: () -> Bool
  private var hasLockedForCurrentAbsence = false
  private let lockRecheckInterval: TimeInterval = 2

  init(settings: SettingsStore, locker: Locker, isEntitled: @escaping () -> Bool = { true }) {
    self.settings = settings
    self.locker = locker
    self.isEntitled = isEntitled
    self.state = settings.hasSelectedDevice ? .connecting : .noDevice
  }

  func menuTitle(rssi: Int?) -> String {
    if let rssi {
      return "WalkAway \(rssi)"
    }
    return "WalkAway"
  }

  func deviceMissing() {
    state = .noDevice
    hasLockedForCurrentAbsence = false
  }

  func scanning() {
    guard !settings.hasSelectedDevice else { return }
    state = .scanning
  }

  func connecting() {
    guard settings.hasSelectedDevice else {
      state = .noDevice
      return
    }
    state = .connecting
  }

  func bluetoothUnavailable(_ message: String) {
    state = .bluetoothUnavailable(message)
    guard settings.lockOnBluetoothUnavailable else { return }
    beginOrContinueLeaving(now: Date())
  }

  func disconnected() {
    evaluate(rssi: nil, reason: .noSignal)
  }

  func deviceVisibleWithoutRSSI() {
    guard settings.hasSelectedDevice else {
      deviceMissing()
      return
    }

    state = .present
    hasLockedForCurrentAbsence = false
  }

  func evaluate(rssi: Int?, reason: AwayReason = .rssi) {
    guard settings.hasSelectedDevice else {
      deviceMissing()
      return
    }

    let isAway = isAwayReading(rssi)
    WALog.decide("evaluate rssi=\(rssi.map(String.init) ?? "nil") reason=\(reason) away=\(isAway) state=\(state.title)")
    if isAway {
      beginOrContinueLeaving(now: Date())
    } else {
      state = .present
      hasLockedForCurrentAbsence = false
    }
  }

  private func isAwayReading(_ rssi: Int?) -> Bool {
    guard let rssi else { return true }

    if settings.useDistanceThreshold {
      return DistanceEstimator.isBeyondLimit(
        rssi: rssi,
        limitMeters: settings.lockDistanceMeters,
        referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
        pathLossExponent: settings.pathLossExponent
      )
    }

    return rssi < settings.rssiThreshold
  }

  private func beginOrContinueLeaving(now: Date) {
    guard isEntitled() else {
      // Trial expired and unlicensed: do not arm or lock. UI surfaces this.
      WALog.decide("away but unlicensed → auto-lock disabled")
      return
    }

    if hasLockedForCurrentAbsence {
      return
    }

    if shouldDeferForUserActivity() {
      state = .leaving(deadline: deferredDeadline(from: now))
      WALog.decide("away but user active → defer lock")
      return
    }

    let deadline: Date
    if case let .leaving(existingDeadline) = state {
      deadline = existingDeadline
    } else {
      deadline = now.addingTimeInterval(TimeInterval(settings.graceSeconds))
      state = .leaving(deadline: deadline)
      WALog.decide("start grace \(settings.graceSeconds)s → lock at \(deadline)")
    }

    guard now >= deadline else { return }

    if shouldDeferForUserActivity() {
      state = .leaving(deadline: deferredDeadline(from: now))
      WALog.decide("grace elapsed but user active → defer lock")
      return
    }

    locker.lockScreen()
    hasLockedForCurrentAbsence = true
    state = .locked
    WALog.decide("LOCK screen — away confirmed, grace elapsed")
  }

  private func shouldDeferForUserActivity() -> Bool {
    settings.pauseWhileActive && ActivityMonitor.isUserActive()
  }

  private func deferredDeadline(from now: Date) -> Date {
    now.addingTimeInterval(max(lockRecheckInterval, TimeInterval(settings.graceSeconds)))
  }
}

enum AwayReason {
  case rssi
  case noSignal
}
