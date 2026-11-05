import Foundation

/// Locking, sleeping and switching users are distinct events. Unknown session data is not an unlock.
struct LockScreenLifecycle {
  private(set) var locked = false
  private(set) var awake = true
  private(set) var onConsole = true

  var canPresent: Bool { locked && awake && onConsole }

  mutating func lockChanged(_ value: Bool) { locked = value }
  mutating func sleep() { awake = false }
  mutating func wake(observedLock: Bool?, onConsole: Bool?) {
    awake = true
    // Never elevate above the desktop after waking without positive lock evidence.
    locked = observedLock ?? false
    self.onConsole = onConsole ?? true
  }
  mutating func sessionBecameActive() {
    locked = false
    onConsole = true
  }
  mutating func reconcile(observedLock: Bool?, onConsole: Bool?) {
    if let observedLock { locked = observedLock }
    if let onConsole { self.onConsole = onConsole }
  }
}
