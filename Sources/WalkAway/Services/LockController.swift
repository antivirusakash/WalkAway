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

  // Startup grace. A fresh launch hasn't connected to the watch yet, so the
  // first readings are nil ("no signal") even when the watch is right here.
  // Without this guard a cold start arms away and locks within the grace while
  // the watch sits on the desk (observed: lock 10 s after relaunch at 0.5 m).
  // Suppress away-locking until we've seen the watch at least once, or a brief
  // window since launch has elapsed (after which a genuine absence still locks).
  private let startDate = Date()
  private var hasSeenSignal = false
  private let startupGraceSeconds: TimeInterval = 20

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

  /// A genuine walk-away slides RSSI down in small steps as you move; the
  /// watch's radio throttle drops it off a cliff (~25 dB in one reading) while
  /// the watch sits on the desk and you stop touching the Mac. An away run that
  /// *enters* as a cliff from the last present level is therefore suspect: it
  /// must not fire the lock on depressed RSSI alone — only genuine signal loss
  /// (the watch leaving BLE range → nil) or a sleeping display confirms it.
  /// Gradual departures never trip the cliff, so distance locking still works.
  private let cliffDropDB = 18
  /// Last present (in-range) smoothed RSSI, the baseline a cliff is measured
  /// from. nil until the first present reading.
  private var lastPresentRSSI: Int?
  /// True while the current away run began as a cliff drop (suspected throttle).
  private var awayRunIsSuspectThrottle = false

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
    // Bluetooth off is a genuine loss, not a throttled reading — lock normally.
    beginOrContinueLeaving(now: Date(), reason: .noSignal)
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
      if consecutiveAwayReadings == 1 {
        // Classify the run at its first away reading: cliff drop from the last
        // present level (still an RSSI reading, not a signal loss) = suspect
        // throttle. A loss (nil) is never a throttle artifact, so never suspect.
        awayRunIsSuspectThrottle = reason == .rssi
          && (rssi.map { (lastPresentRSSI ?? $0) - $0 >= cliffDropDB } ?? false)
      }
    } else {
      consecutivePresentReadings += 1
      consecutiveAwayReadings = 0
      awayRunIsSuspectThrottle = false
      if let rssi { lastPresentRSSI = rssi }
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
      // Startup grace: don't treat "no signal yet" as away while we're still
      // connecting on a fresh launch. Once any present reading arrives, or the
      // window elapses, fall through to normal away handling.
      if !hasSeenSignal, Date().timeIntervalSince(startDate) < startupGraceSeconds {
        if case .present = state {} else {
          WALog.decide("away during startup grace — still connecting, not arming")
        }
        state = settings.hasSelectedDevice ? .connecting : .noDevice
        consecutiveAwayReadings = 0
        return
      }
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
      beginOrContinueLeaving(now: Date(), reason: reason)
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
      hasSeenSignal = true
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

  private func beginOrContinueLeaving(now: Date, reason: AwayReason = .rssi) {
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

    // Throttle guard: this away run entered as a cliff and is still only a
    // depressed RSSI reading (the watch is visible, not lost) with the display
    // awake — the radio-throttle false-lock signature. Hold in Leaving and wait
    // for a trustworthy confirmation: the watch leaving range (reason becomes
    // .noSignal) or the display sleeping both bypass this guard and lock.
    if awayRunIsSuspectThrottle, reason == .rssi, !ActivityMonitor.isDisplayAsleep() {
      state = .leaving(deadline: deferredDeadline(from: now))
      WALog.decide("suspect radio-throttle (cliff drop, still visible) → hold, await signal loss or display sleep")
      return
    }

    locker.lockScreen()
    hasLockedForCurrentAbsence = true
    state = .locked
    metrics?.recordLock()
    WALog.decide("LOCK screen — away confirmed, grace elapsed (idle=\(Int(ActivityMonitor.secondsSinceLastInput()))s displayAsleep=\(ActivityMonitor.isDisplayAsleep()) hasSeenSignal=\(hasSeenSignal))")
  }

  /// Mac-local presence fusion layered on top of the BLE away signal. The BLE
  /// reading is noisy (the watch throttles its radio), so before locking we
  /// confirm against signals that can't be faked by a glitchy advertisement:
  ///
  ///   • display asleep  → the user is plainly not at the screen → lock now,
  ///     don't wait for the idle window.
  ///   • display awake   → require `confirmIdleSeconds` with no keyboard/mouse
  ///     input before locking, so a stray BLE drop while you sit reading at the
  ///     desk can't trigger a false lock. Any recent input defers the lock.
  ///
  /// Only active while "Pause while active" is on (the default).
  private func shouldDeferForUserActivity() -> Bool {
    guard settings.pauseWhileActive else { return false }
    if ActivityMonitor.isDisplayAsleep() { return false }
    return ActivityMonitor.secondsSinceLastInput() < TimeInterval(settings.confirmIdleSeconds)
  }

  private func deferredDeadline(from now: Date) -> Date {
    now.addingTimeInterval(max(lockRecheckInterval, TimeInterval(settings.graceSeconds)))
  }
}

enum AwayReason {
  case rssi
  case noSignal
}
