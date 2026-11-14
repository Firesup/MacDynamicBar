import Foundation

/// Locking, sleeping and switching users are distinct events. Unknown session data is not an unlock.
struct LockScreenLifecycle {
  private(set) var locked = false
  private(set) var awake = true
  private(set) var onConsole = true
  private(set) var awaitingUnlockConfirmation = false

  var canPresent: Bool { locked && awake && onConsole && !awaitingUnlockConfirmation }

  mutating func lockChanged(_ value: Bool) {
    locked = value
    awaitingUnlockConfirmation = !value
  }
  mutating func sleep() { awake = false }
  mutating func wake(observedLock: Bool?, onConsole: Bool?) {
    awake = true
    // Never elevate above the desktop after waking without positive lock evidence.
    locked = observedLock ?? false
    if observedLock == false { awaitingUnlockConfirmation = false }
    self.onConsole = onConsole ?? false
  }
  mutating func sessionBecameActive() {
    locked = false
    awaitingUnlockConfirmation = true
    onConsole = true
  }
  mutating func reconcile(observedLock: Bool?, onConsole: Bool?) {
    // An unlock notification can precede the session dictionary update. Do not recreate
    // the panel from that stale `true` while the desktop is being revealed.
    if awaitingUnlockConfirmation {
      if observedLock == false { awaitingUnlockConfirmation = false }
      locked = false
    } else if let observedLock {
      locked = observedLock
    }
    if let onConsole { self.onConsole = onConsole }
  }
}
