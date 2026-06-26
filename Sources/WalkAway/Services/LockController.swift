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
  private let metrics: MetricsMonitor?
  private var hasLockedForCurrentAbsence = false
  private let lockRecheckInterval: TimeInterval = 2

  // Tier A accuracy tuning.
  /// dB the signal must recover above the away cutoff before re-arming as
  /// present — asymmetric hysteresis for raw-RSSI mode only. In distance mode
  /// the recover point scales with the limit (see presentRecoverRSSI), so an
  /// in-range distance can't get latched "away" by a single far spike.
  private let hysteresisMarginDB = 3
  /// Consecutive away readings required before the grace countdown starts —
  /// debounce so a brief RSSI noise burst can't begin a lock. system_profiler
  /// RSSI swings ~30 dB at a fixed distance; 2 was too few (locked at 3-4 m).
  private let awayConfirmReadings = 3
  /// Consecutive present readings required to ABORT an already-armed lock.
  /// Stops one or two stray "present" RSSI readings from canceling a lock
  /// that is mid-grace (the real-world walk-away failure we observed).
  private let presentConfirmReadings = 3
  /// Sticky away/present decision within the hysteresis band.
  private var lastReadingAway = false
  /// Run of consecutive away readings (resets on any present reading).
  private var consecutiveAwayReadings = 0
  /// Run of consecutive present readings (resets on any away reading).
  private var consecutivePresentReadings = 0

  init(settings: SettingsStore, locker: Locker, metrics: MetricsMonitor? = nil) {
    self.settings = settings
    self.locker = locker
    self.metrics = metrics
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
    guard settings.lockOnBluetoothUnavailable, settings.isWithinLockSchedule() else { return }
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
    if isAway {
      consecutiveAwayReadings += 1
      consecutivePresentReadings = 0
    } else {
      consecutivePresentReadings += 1
      consecutiveAwayReadings = 0
    }
    let cutoff = awayCutoffRSSI()
    let distStr = rssi.map {
      String(format: "%.1fm", DistanceEstimator.meters(
        rssi: $0,
        referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
        pathLossExponent: settings.pathLossExponent
      ))
    } ?? "n/a"
    WALog.decide("evaluate rssi=\(rssi.map(String.init) ?? "nil") dist=\(distStr) limit=\(String(format: "%.1f", settings.lockDistanceMeters))m cutoff=\(cutoff)dBm reason=\(reason) away=\(isAway) awayRun=\(consecutiveAwayReadings)/\(awayConfirmReadings) presentRun=\(consecutivePresentReadings)/\(presentConfirmReadings) state=\(state.title)")

    if isAway {
      // Schedule gate: outside the configured auto-lock window, never lock.
      // Hold present so nothing arms until the window opens.
      guard settings.isWithinLockSchedule() else {
        if case .present = state {} else {
          WALog.decide("away but outside auto-lock window — idle until schedule opens")
        }
        state = .present
        hasLockedForCurrentAbsence = false
        consecutiveAwayReadings = 0
        return
      }
      // Debounce: require N consecutive away readings before arming.
      guard consecutiveAwayReadings >= awayConfirmReadings else { return }
      beginOrContinueLeaving(now: Date())
    } else if isArmedOrLocked(state), consecutivePresentReadings < presentConfirmReadings {
      // Armed (leaving) OR already locked, and this reading is "present". A lone
      // present blip must NOT reset the state: while leaving it would cancel a
      // real walk-away (and firing here would lock on a present reading — the
      // 3-4 m false-lock); while locked it clears hasLockedForCurrentAbsence and
      // re-fires lockScreen() on the next weak reading (observed 8 re-locks in
      // one departure). Only sustained presence (>= presentConfirmReadings)
      // returns to Present via the else branch. The lock itself only fires on an
      // away reading once grace elapses (see the isAway branch).
      WALog.decide("present blip (\(consecutivePresentReadings)/\(presentConfirmReadings)) — holding \(state.title)")
    } else {
      state = .present
      hasLockedForCurrentAbsence = false
    }
  }

  /// Away decision on a calibrated RSSI cutoff (dBm) with asymmetric
  /// hysteresis — steadier than a live meters estimate. RSSI is negative dBm
  /// (weaker = more negative). Missing RSSI counts as away.
  private func isAwayReading(_ rssi: Int?) -> Bool {
    guard let rssi else {
      lastReadingAway = true
      return true
    }

    let awayCutoff = awayCutoffRSSI()
    if rssi <= awayCutoff {
      lastReadingAway = true
    } else if rssi >= presentRecoverRSSI() {
      lastReadingAway = false
    }
    // Within the band, hold the previous decision (sticky).
    return lastReadingAway
  }

  /// RSSI (dBm) at or above which the watch re-arms as present after being
  /// away. In distance mode this is the RSSI at 80% of the limit, so anything
  /// comfortably inside the limit clears an "away" latch — a far noise spike
  /// can't trap an in-range watch. In raw mode it's a fixed dB margin.
  private func presentRecoverRSSI() -> Int {
    if settings.useDistanceThreshold {
      return DistanceEstimator.rssiThreshold(
        forMeters: settings.lockDistanceMeters * 0.8,
        referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
        pathLossExponent: settings.pathLossExponent
      )
    }
    return settings.rssiThreshold + hysteresisMarginDB
  }

  /// True while a lock is armed (leaving) or has already fired (locked) — states
  /// a lone present blip must not reset.
  private func isArmedOrLocked(_ state: PresenceState) -> Bool {
    switch state {
    case .leaving, .locked: return true
    default: return false
    }
  }

  /// The RSSI (dBm) at or below which the watch counts as away. Derived from
  /// the distance limit in distance mode, else the raw RSSI threshold.
  private func awayCutoffRSSI() -> Int {
    if settings.useDistanceThreshold {
      return DistanceEstimator.rssiThreshold(
        forMeters: settings.lockDistanceMeters,
        referenceRSSIAtOneMeter: settings.referenceRSSIAtOneMeter,
        pathLossExponent: settings.pathLossExponent
      )
    }
    return settings.rssiThreshold
  }

  private func beginOrContinueLeaving(now: Date) {
    if hasLockedForCurrentAbsence {
      return
    }

    if shouldDeferForUserActivity() {
      state = .leaving(deadline: deferredDeadline(from: now))
      metrics?.recordDefer()
      WALog.decide("away but user active → defer lock")
      return
    }

    let deadline: Date
    if case let .leaving(existingDeadline) = state {
      deadline = existingDeadline
    } else {
      deadline = now.addingTimeInterval(TimeInterval(settings.graceSeconds))
      state = .leaving(deadline: deadline)
      metrics?.recordAway()
      WALog.decide("start grace \(settings.graceSeconds)s → lock at \(deadline)")
    }

    guard now >= deadline else { return }

    if shouldDeferForUserActivity() {
      state = .leaving(deadline: deferredDeadline(from: now))
      metrics?.recordDefer()
      WALog.decide("grace elapsed but user active → defer lock")
      return
    }

    locker.lockScreen()
    hasLockedForCurrentAbsence = true
    state = .locked
    metrics?.recordLock()
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
