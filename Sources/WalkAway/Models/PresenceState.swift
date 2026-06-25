import Foundation

enum PresenceState: Equatable {
  case noDevice
  case bluetoothUnavailable(String)
  case scanning
  case connecting
  case present
  case leaving(deadline: Date)
  case locked

  var title: String {
    switch self {
    case .noDevice:
      return "Pick a device"
    case .bluetoothUnavailable:
      return "Bluetooth unavailable"
    case .scanning:
      return "Scanning"
    case .connecting:
      return "Connecting"
    case .present:
      return "Present"
    case .leaving:
      return "Leaving"
    case .locked:
      return "Locked"
    }
  }
}
