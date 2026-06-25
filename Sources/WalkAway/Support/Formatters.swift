import Foundation

enum Formatters {
  static func rssi(_ value: Int?) -> String {
    guard let value else { return "No signal" }
    return "\(value) dBm"
  }

  static func seconds(_ value: Int) -> String {
    value == 1 ? "1 second" : "\(value) seconds"
  }

  static func meters(_ value: Double?) -> String {
    guard let value else { return "No distance" }
    if value < 10 {
      return String(format: "%.1f m", value)
    }
    return "\(Int(value.rounded())) m"
  }

  static func decimal(_ value: Double, places: Int = 2) -> String {
    String(format: "%.\(places)f", value)
  }
}
