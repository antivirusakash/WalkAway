import CoreGraphics
import Foundation

enum ActivityMonitor {
  static let lockDeferralWindow: TimeInterval = 8

  static func isUserActive(within seconds: TimeInterval = lockDeferralWindow) -> Bool {
    let eventTypes: [CGEventType] = [
      .keyDown,
      .leftMouseDown,
      .rightMouseDown,
      .otherMouseDown,
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .scrollWheel
    ]

    return eventTypes.contains { eventType in
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType) < seconds
    }
  }
}
