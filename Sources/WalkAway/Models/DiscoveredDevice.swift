import Foundation

struct DiscoveredDevice: Identifiable, Equatable {
  enum Source: Equatable {
    case coreBluetooth
    case systemBluetooth
  }

  let id: String
  let name: String
  let rssi: Int?
  let source: Source
  let peripheralUUID: UUID?
  let bluetoothAddress: String?

  var displayName: String {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedName.isEmpty ? "Unnamed device" : trimmedName
  }

  var subtitle: String {
    if let rssi {
      return "\(shortIdentifier) · \(rssi) dBm"
    }
    return shortIdentifier
  }

  private var shortIdentifier: String {
    switch source {
    case .coreBluetooth:
      return peripheralUUID.map { String($0.uuidString.prefix(8)) } ?? String(id.prefix(8))
    case .systemBluetooth:
      return "\(bluetoothAddress ?? String(id.prefix(12))) · System"
    }
  }
}
