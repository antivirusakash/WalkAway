import Darwin
import Foundation

@MainActor
final class Locker: ObservableObject {
  @Published private(set) var lastLockDate: Date?

  func lockScreen() {
    typealias LockFn = @convention(c) () -> Void

    if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
       let symbol = dlsym(handle, "SACLockScreenImmediate") {
      let lock = unsafeBitCast(symbol, to: LockFn.self)
      lock()
      lastLockDate = Date()
      return
    }

    fallbackLock()
    lastLockDate = Date()
  }

  private func fallbackLock() {
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    )
    process.arguments = ["-suspend"]
    try? process.run()
  }
}
