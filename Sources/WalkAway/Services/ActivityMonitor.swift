import CoreGraphics
import Foundation

enum ActivityMonitor {
  static let lockDeferralWindow: TimeInterval = 8

  private static let inputEventTypes: [CGEventType] = [
    .keyDown,
    .leftMouseDown,
    .rightMouseDown,
    .otherMouseDown,
    .mouseMoved,
    .leftMouseDragged,
    .rightMouseDragged,
    .scrollWheel
  ]

  /// Seconds since the most recent keyboard/mouse input of any kind — a
  /// continuous, reliable "is the user physically here" measure that is
  /// independent of (and far steadier than) the BLE signal.
  static func secondsSinceLastInput() -> TimeInterval {
    inputEventTypes
      .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
      .min() ?? .greatestFiniteMagnitude
  }

  static func isUserActive(within seconds: TimeInterval = lockDeferralWindow) -> Bool {
    secondsSinceLastInput() < seconds
  }

  /// True when the main display has powered down (display sleep / screensaver
  /// blanked it). A strong "user is not at the screen" signal — it lets the
  /// lock decision skip the idle-confirmation wait and lock promptly.
  static func isDisplayAsleep() -> Bool {
    CGDisplayIsAsleep(CGMainDisplayID()) != 0
  }
}
