import Foundation
import os

/// Lightweight, public decision logging so "going away" behaviour can be
/// confirmed and any future inconsistency diagnosed via Console.app / `log`.
/// Subsystem is the app bundle id (com.fizday.walkaway) when bundled:
///
///   log stream --predicate 'subsystem == "com.fizday.walkaway" && category == "decision"'
enum WALog {
  static let decision = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "WalkAway",
    category: "decision"
  )

  /// Log a single proximity/lock decision. Message is built lazily and emitted
  /// at `.public` privacy so it shows up in plain text.
  static func decide(_ message: @autoclosure () -> String) {
    let text = message()
    decision.log("\(text, privacy: .public)")
  }
}
