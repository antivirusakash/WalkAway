import Darwin
import Foundation
import os

/// On-device performance + usage instrumentation. Nothing leaves the Mac.
///
/// Samples this process's memory footprint and CPU every 30s, records the cost
/// of each Bluetooth poll, and counts lock / away / defer events so behaviour
/// can be tuned over time. Emits one `perf` log line per sample:
///
///   /usr/bin/log stream --predicate 'subsystem == "com.fizday.walkaway" && category == "perf"'
@MainActor
final class MetricsMonitor: ObservableObject {
  @Published private(set) var memoryMB: Double = 0
  @Published private(set) var cpuPercent: Double = 0
  @Published private(set) var lastPollMillis: Double = 0
  @Published private(set) var avgPollMillis: Double = 0
  @Published private(set) var lockCount: Int
  @Published private(set) var awayCount: Int
  @Published private(set) var deferCount: Int

  let startDate = Date()
  private var lastCPUTime: Double
  private var lastSampleDate = Date()
  private var pollSamples: [Double] = []
  private var timer: Timer?
  private let defaults: UserDefaults
  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "WalkAway",
    category: "perf"
  )

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    lockCount = defaults.integer(forKey: Keys.lockCount)
    awayCount = defaults.integer(forKey: Keys.awayCount)
    deferCount = defaults.integer(forKey: Keys.deferCount)
    lastCPUTime = Self.processCPUSeconds()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.sample() }
    }
    sample()
  }

  deinit { timer?.invalidate() }

  // MARK: - Event recording

  func recordLock() { lockCount += 1; defaults.set(lockCount, forKey: Keys.lockCount) }
  func recordAway() { awayCount += 1; defaults.set(awayCount, forKey: Keys.awayCount) }
  func recordDefer() { deferCount += 1; defaults.set(deferCount, forKey: Keys.deferCount) }

  func recordPoll(millis: Double) {
    lastPollMillis = millis
    pollSamples.append(millis)
    if pollSamples.count > 30 { pollSamples.removeFirst(pollSamples.count - 30) }
    avgPollMillis = pollSamples.reduce(0, +) / Double(pollSamples.count)
  }

  func resetCounters() {
    lockCount = 0; awayCount = 0; deferCount = 0
    defaults.set(0, forKey: Keys.lockCount)
    defaults.set(0, forKey: Keys.awayCount)
    defaults.set(0, forKey: Keys.deferCount)
  }

  var uptimeSeconds: Int { Int(Date().timeIntervalSince(startDate)) }

  // MARK: - Sampling

  private func sample() {
    let now = Date()
    let cpuSeconds = Self.processCPUSeconds()
    let dt = now.timeIntervalSince(lastSampleDate)
    if dt > 0 {
      cpuPercent = max(0, (cpuSeconds - lastCPUTime) / dt * 100)
    }
    lastCPUTime = cpuSeconds
    lastSampleDate = now
    memoryMB = Self.memoryFootprintMB()

    Self.log.log("""
      mem=\(self.memoryMB, format: .fixed(precision: 1))MB \
      cpu=\(self.cpuPercent, format: .fixed(precision: 2))% \
      poll=\(self.lastPollMillis, format: .fixed(precision: 0))ms(avg \
      \(self.avgPollMillis, format: .fixed(precision: 0))) \
      locks=\(self.lockCount) away=\(self.awayCount) defer=\(self.deferCount) \
      uptime=\(self.uptimeSeconds)s
      """)
  }

  // MARK: - Mach process metrics

  /// Resident memory footprint in MB (matches Activity Monitor's "Memory").
  static func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &info) { ptr in
      ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    return Double(info.phys_footprint) / 1_048_576
  }

  /// Total CPU time consumed by this process's live threads, in seconds.
  /// Note: excludes spawned child processes (e.g. system_profiler).
  static func processCPUSeconds() -> Double {
    var threadList: thread_act_array_t?
    var threadCount = mach_msg_type_number_t(0)
    guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
          let threads = threadList else {
      return 0
    }
    defer {
      vm_deallocate(
        mach_task_self_,
        vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(threads))),
        vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.stride)
      )
    }

    var total = 0.0
    for index in 0..<Int(threadCount) {
      var info = thread_basic_info()
      var infoCount = mach_msg_type_number_t(
        MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size
      )
      let kr = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
          thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
        }
      }
      if kr == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
        total += Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        total += Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
      }
    }
    return total
  }

  private enum Keys {
    static let lockCount = "metricLockCount"
    static let awayCount = "metricAwayCount"
    static let deferCount = "metricDeferCount"
  }
}
