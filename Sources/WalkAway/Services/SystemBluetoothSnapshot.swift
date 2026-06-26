import Foundation

struct SystemBluetoothDevice: Equatable {
  let name: String
  let address: String
  let rssi: Int?

  var normalizedName: String {
    name.replacingOccurrences(of: "\u{00a0}", with: " ")
  }
}

enum SystemBluetoothSnapshot {
  static func load() -> [SystemBluetoothDevice] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType"]
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      NSLog("WalkAway system_profiler failed: \(error.localizedDescription)")
      return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      return []
    }
    return parse(output)
  }

  static func parse(_ output: String) -> [SystemBluetoothDevice] {
    var devices: [SystemBluetoothDevice] = []
    var currentName: String?
    var currentAddress: String?
    var currentRSSIValues: [Int] = []

    func flush() {
      guard let currentName, let currentAddress else { return }
      devices.append(
        SystemBluetoothDevice(
          name: currentName,
          address: normalizeAddress(currentAddress),
          rssi: Self.median(currentRSSIValues)
        )
      )
    }

    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let raw = String(line)
      let trimmed = raw.trimmingCharacters(in: .whitespaces)

      if raw.hasPrefix("          "), trimmed.hasSuffix(":"),
         !trimmed.contains("Address:"),
         !trimmed.contains("Bluetooth Controller:") {
        flush()
        currentName = String(trimmed.dropLast())
        currentAddress = nil
        currentRSSIValues = []
        continue
      }

      if trimmed.hasPrefix("Address:") {
        currentAddress = value(after: "Address:", in: trimmed)
      } else if trimmed.hasPrefix("RSSI:"), let value = Int(value(after: "RSSI:", in: trimmed)) {
        // A single snapshot can list several RSSI lines for one device that
        // span ~25 dB (e.g. -49, -48, -72). Median across them kills the
        // impulsive outlier instead of arbitrarily keeping the last line.
        currentRSSIValues.append(value)
      }
    }

    flush()
    return devices
  }

  private static func median(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let count = sorted.count
    if count % 2 == 1 { return sorted[count / 2] }
    return Int((Double(sorted[count / 2 - 1]) + Double(sorted[count / 2])) / 2.0)
  }

  static func normalizeAddress(_ address: String) -> String {
    address
      .replacingOccurrences(of: ":", with: "-")
      .lowercased()
  }

  private static func value(after prefix: String, in line: String) -> String {
    String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
  }
}
