import Foundation

/// Wait for actor-scheduled UI work without assuming other tests leave the main
/// actor idle during a fixed sleep. Callers still assert the final state.
@MainActor
func waitForCondition(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !condition(), clock.now < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
}
