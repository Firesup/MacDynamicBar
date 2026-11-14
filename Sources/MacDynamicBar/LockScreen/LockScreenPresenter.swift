import AppKit
import Darwin
import os

/// Private API boundary. Call sequence/signatures researched in SkyLightWindow (MIT,
/// Lakr Aream) and Nocta (MIT, aNasiusA). See Support/LockScreenThirdPartyNotices.txt.
/// A successful placement is not evidence that a human can see or click the panel.
@MainActor
protocol LockScreenPresenting: AnyObject {
  func place(window: Int, orderWindow: () -> Void) throws
  func hide() throws
}

struct LockScreenPresentationError: Error, CustomStringConvertible {
  let description: String
  var retryable = false
}

/// Owns an isolated space only while the signed-in session is locked.
@MainActor
final class SkyLightLockScreenPresenter: LockScreenPresenting {
  struct Functions {
    var connection: () -> Int32
    var create: (Int32, Int32, Int32) -> UInt64
    var level: (Int32, UInt64, Int32) -> Int32
    var show: (Int32, CFArray) -> Void
    var add: (Int32, UInt64, CFArray, Int32) -> Int32
    var hide: (Int32, CFArray) -> Int32
    var destroy: (Int32, UInt64) -> Int32
  }
  private let logger = Logger(subsystem: "com.minnow.MacDynamicBar", category: "LockScreen")
  private let functions: Functions
  private let handle: UnsafeMutableRawPointer?
  private var connection: Int32 = 0
  private var space: UInt64 = 0

  init(functions: Functions, handle: UnsafeMutableRawPointer? = nil) {
    self.functions = functions
    self.handle = handle
  }

  static func load(
    resolveSymbol: (UnsafeMutableRawPointer, String) -> UnsafeMutableRawPointer? = { dlsym($0, $1) }
  ) throws -> SkyLightLockScreenPresenter {
    guard let handle = dlopen(
      "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW | RTLD_LOCAL
    ) else { throw LockScreenPresentationError(description: "SkyLight could not be loaded") }
    func resolve<T>(_ name: String, _ type: T.Type) throws -> T {
      guard let pointer = resolveSymbol(handle, name) else {
        throw LockScreenPresentationError(description: "Missing SkyLight symbol: \(name)")
      }
      return unsafeBitCast(pointer, to: type)
    }
    do {
      let connection = try resolve("SLSMainConnectionID", (@convention(c) () -> Int32).self)
      // Space IDs are pointer-sized (64-bit). Several mutators return void; a
      // return register is not a CGError. Verify server state through Copy/Get APIs.
      let create = try resolve("SLSSpaceCreate", (@convention(c) (Int32, Int32, Int32) -> UInt64).self)
      let level = try resolve("SLSSpaceSetAbsoluteLevel", (@convention(c) (Int32, UInt64, Int32) -> Void).self)
      let getLevel = try resolve("SLSSpaceGetAbsoluteLevel", (@convention(c) (Int32, UInt64) -> Int32).self)
      let show = try resolve("SLSShowSpaces", (@convention(c) (Int32, CFArray) -> Void).self)
      let add = try resolve("SLSSpaceAddWindowsAndRemoveFromSpaces", (@convention(c) (Int32, UInt64, CFArray, Int32) -> Void).self)
      let hide = try resolve("SLSHideSpaces", (@convention(c) (Int32, CFArray) -> Void).self)
      let destroy = try resolve("SLSSpaceDestroy", (@convention(c) (Int32, UInt64) -> Void).self)
      let copySpaces = try resolve("SLSCopySpaces", (@convention(c) (Int32, Int32) -> Unmanaged<CFArray>?).self)
      let isOrdered = try resolve("SLSWindowIsOrderedIn", (@convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt8>) -> Int32).self)
      let copyWindowSpaces = try resolve("SLSCopySpacesForWindows", (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?).self)
      func contains(_ array: Unmanaged<CFArray>?, _ space: UInt64) -> Bool? {
        guard let array, let numbers = array.takeRetainedValue() as? [NSNumber] else { return nil }
        return numbers.contains { $0.uint64Value == space }
      }
      let functions = Functions(
        connection: { connection() }, create: { create($0, $1, $2) },
        level: { cid, sid, value in
          level(cid, sid, value)
          return getLevel(cid, sid) == value ? 0 : -1
        },
        show: { cid, spaces in show(cid, spaces) },
        add: { cid, sid, windows, selector in
          add(cid, sid, windows, selector)
          guard let numbers = windows as? [NSNumber], let window = numbers.first?.uint32Value else { return -1 }
          var ordered: UInt8 = 0
          let orderResult = isOrdered(cid, window, &ordered)
          let member = contains(copyWindowSpaces(cid, 0x7, windows), sid)
          let listed = contains(copySpaces(cid, 0x10007), sid)
          let log = Logger(subsystem: "com.minnow.MacDynamicBar", category: "LockScreen")
          log.info("SkyLight window postconditions orderedResult=\(orderResult) ordered=\(ordered) member=\(member == true) shownSpaceListed=\(listed == true); visual visibility unverified")
          // These enumeration APIs can omit unmanaged/custom lock spaces. Hardware
          // observation confirmed a visible panel while both lists omitted this space.
          // Keep membership as a diagnostic, not a reason to destroy a visible panel.
          return orderResult == 0 && ordered != 0 ? 0 : -2
        },
        hide: { cid, spaces in
          guard let numbers = spaces as? [NSNumber], let sid = numbers.first?.uint64Value else { return -1 }
          hide(cid, spaces)
          return contains(copySpaces(cid, 0x10007), sid) == false ? 0 : -1
        },
        destroy: { cid, sid in
          destroy(cid, sid)
          return contains(copySpaces(cid, 0x7), sid) == false ? 0 : -1
        })
      return SkyLightLockScreenPresenter(functions: functions, handle: handle)
    } catch {
      dlclose(handle)
      throw error
    }
  }

  func place(window: Int, orderWindow: () -> Void = {}) throws {
    guard window > 0, let windowID = Int32(exactly: window) else {
      throw LockScreenPresentationError(description: "Invalid panel window number")
    }
    if space == 0 {
      connection = functions.connection()
      guard connection != 0 else {
        throw LockScreenPresentationError(description: "No SkyLight connection")
      }
      space = functions.create(connection, 1, 0)
      logger.info("SkyLight create connection=\(self.connection) space=\(self.space)")
      guard space > 0 else {
        space = 0
        throw LockScreenPresentationError(description: "SkyLight space creation failed")
      }
    }
    try check(functions.level(connection, space, 400), "set space level")
    // The space must be shown before adoption, and AppKit must register/order the
    // window before WindowServer can move it. Repeat the whole sequence on wake.
    functions.show(connection, [space] as CFArray)
    orderWindow()
    try check(functions.add(connection, space, [windowID] as CFArray, 7), "adopt panel")
  }

  func hide() throws {
    guard space != 0 else { return }
    let hidden = functions.hide(connection, [space] as CFArray)
    let destroyed = functions.destroy(connection, space)
    // Retain the ID when destruction fails so cleanup can be retried.
    if destroyed == 0 { space = 0 }
    try check(hidden, "hide space")
    try check(destroyed, "destroy space")
  }

  private func check(_ result: Int32, _ operation: String) throws {
    logger.info("SkyLight operation=\(operation, privacy: .public) verifiedResult=\(result) space=\(self.space)")
    guard result == 0 else {
      throw LockScreenPresentationError(
        description: "SkyLight \(operation) failed (\(result))", retryable: result == -2)
    }
  }

  isolated deinit {
    // Best-effort backstop; the controller performs checked cleanup synchronously.
    if space != 0 {
      _ = functions.hide(connection, [space] as CFArray)
      _ = functions.destroy(connection, space)
    }
    if let handle { dlclose(handle) }
  }
}
