import Foundation

enum DistanceEstimator {
  static func meters(
    rssi: Int,
    referenceRSSIAtOneMeter: Int,
    pathLossExponent: Double
  ) -> Double {
    let exponent = max(1.2, min(pathLossExponent, 4.5))
    let power = Double(referenceRSSIAtOneMeter - rssi) / (10 * exponent)
    return pow(10, power)
  }

  static func isBeyondLimit(
    rssi: Int,
    limitMeters: Double,
    referenceRSSIAtOneMeter: Int,
    pathLossExponent: Double
  ) -> Bool {
    meters(
      rssi: rssi,
      referenceRSSIAtOneMeter: referenceRSSIAtOneMeter,
      pathLossExponent: pathLossExponent
    ) > limitMeters
  }

  static func rssiThreshold(
    forMeters meters: Double,
    referenceRSSIAtOneMeter: Int,
    pathLossExponent: Double
  ) -> Int {
    let distance = max(0.1, meters)
    let exponent = max(1.2, min(pathLossExponent, 4.5))
    let rssi = Double(referenceRSSIAtOneMeter) - (10 * exponent * log10(distance))
    return Int(rssi.rounded())
  }

  static func pathLossExponent(
    referenceRSSIAtOneMeter: Int,
    rssiAtKnownDistance: Int,
    knownDistanceMeters: Double
  ) -> Double {
    let distance = max(1.1, knownDistanceMeters)
    let exponent = Double(referenceRSSIAtOneMeter - rssiAtKnownDistance) / (10 * log10(distance))
    guard exponent.isFinite else { return 2.2 }
    return max(1.2, min(exponent, 4.5))
  }
}
