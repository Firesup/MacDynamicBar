# Continuation validation — November 3, 2026

Branch: `feat/lockscreen-player`. The pre-existing `.vscode/settings.json` edit was retained. No merge, commit, push or change to main was performed.

## Local verification

- Host: macOS 27.0.1, Apple silicon, Swift 6.4.1.
- `swift test` using the build script's workspace cache options: 44 tests passed. New checks cover small/offset display bounds, shared card/art/lyrics hit geometry, explicit call-control evidence and sample-call priority. Existing event, playback, settings and hover tests passed.
- `MINNOW_RENDER_SCENE=1 swift test --filter musicSceneRendersWithoutStartingPlaybackOrDeviceMonitoring` with the same cache options: one test passed separately.
- `zsh scripts/build-app.sh`: passed; `.build/Minnow.app` includes generated `Minnow.icns` and the development signature. The restricted sandbox prevented `iconutil` from packaging valid PNGs; system execution succeeded. The Swift icon generator is compiled with AppKit rather than relying on JIT framework loading.
- `codesign --verify --deep --strict .build/Minnow.app`, Info.plist lint, and `git diff --check`: passed.
- Generated 256-pixel icon visually reviewed. Call popup included in the offscreen smallest-width render test.

## Live app checks

Launched this workspace's `.build/Minnow.app`. General, Events and Lock Screen settings loaded. Fish branding appeared in Settings. The AirPods picker populated three actual paired devices without pressing Refresh; none was reported as connected. No connection attempt was made.

The explicit phone probe displayed its missing-Accessibility-access state. Permission was not granted; no app UI extraction or call action ran. The incoming-call preview button was exercised, but the separate island popup was not captured by the settings-window screenshot, so its live visual presentation is not verified.

The unlocked Music Scene displayed current Spotify metadata, artwork, playback position and real battery status. Artwork expansion and the lyrics pane worked; without an imported LRC, the pane correctly asked for a file. Playback remained paused. The scene was collapsed, lyrics toggled back off, and closed after testing. Settings remains open, and the app remains running.

## Remaining gates

- Genuine lock/unlock, authentication click-through, locked transport/seek, sleep/wake and multiple physical displays. Geometry tests and the unlocked scene do not establish locked-screen interaction.
- Renamed AirPods with real cached SDP records, connect/disconnect storms, wake reseeding, hardware connection attempts and output selection. Nearby-case discovery and battery readings remain unfinished.
- Grant Minnow Accessibility access through an explicit user action; inspect a real incoming and active FaceTime/Phone call. English button-label evidence is heuristic and not verified against live calls. Automatic monitoring, caller extraction, answer/decline and third-party call adapters are unfinished.

Accessibility implementation references: Apple's [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) and [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue). These APIs expose permission and UI attributes; they do not provide a universal call-state API.


## Follow-up: AirPods route names and capture denial

The live app returned `com.apple.ScreenCaptureKit.SCStreamErrorDomain (-3801)` while playing Spotify. System Settings showed Minnow enabled under Screen & System Audio Recording; Retry and a clean restart of the same bundle did not recover capture. This establishes a permission/runtime mismatch, not a missing music track or an AirPods recognition failure. The bundle has an ad-hoc designated requirement pinned to its code hash; no valid signing identities were available in the inspected environment. A stale permission for an earlier binary is a likely explanation, not proven from the protected TCC database.

Bluetooth enumerated the user's personalized AirPods names. All paired AirPods were disconnected during inspection, and the active output was MacBook Air Speakers. The Core Audio picker now maps Bluetooth route addresses to saved Bluetooth names; synthetic tests cover separated/compact addresses, unmatched devices and UUID rejection. A live AirPods route still needs connection to verify its actual UID format.

The capture UI now shows full diagnostics in Media settings and a short actionable island status. It can retry on returning after a permission grant and no longer flips the persisted waveform preference to retry. The build accepts `MINNOW_SIGN_IDENTITY` for a supplied persistent certificate. Reauthorization for the final current binary remains required before waveform success can be claimed.


Follow-up verification: all 46 tests passed after the route-naming and recovery changes; the development bundle built and its signature passed verification. Launched the final bundle and verified the new Media diagnostics show the exact `-3801` failure and recovery instructions. Permission refresh is awaiting the user's confirmation, and a live AirPods route is awaiting connection. No privacy permission was changed during these checks.


## Live follow-up completed after permission-refresh approval

The user authorized refreshing Minnow's capture permission and connected the AirPods. System Settings' stale entry was removed, this workspace's exact `.build/Minnow.app` was selected, and macOS's Quit & Reopen action applied the new grant. This was repeated for the final binary after the additional fixes below; other apps' permissions were left alone.

Live hardware revealed that Bluetooth changes the connected device's name to `AirPods 4 (ANC)` while Core Audio retains `Abisan’s AirPods` at the same address. The previous Bluetooth-first choice would overwrite the personalized name. The final rule preserves a personalized Core Audio name, uses a personalized paired name when the audio route is generic, and matches strictly by address. The Events device list and real connection-event name resolver now consume that same route name. A regression test covers the actual observed pair of names.

The restart also exposed a main-thread wait inside `SecItemCopyMatching` while restoring optional Spotify credentials. The noninteractive Keychain setting alone did not prevent this legacy-service wait on this Mac. Restoration now runs in a detached task, with stale-result protection; Keychain authentication can be requested explicitly from Connect Spotify. The stalled development instance was stopped through Activity Monitor. No Keychain item was deleted or credential value logged. The corrected app launched promptly, and Spotify account restoration later completed successfully.

Final verification:

- All **47 tests passed**, including the connected-device name regression. Final development bundle built and signature verified.
- Events displayed **Abisan’s AirPods** with **Connected** status.
- The live Sound Output picker displayed **Abisan’s AirPods** selected.
- Shared scene and island both reported **Playing · Listening to Spotify**. Screenshots showed nonzero waveform bars with different measured heights on successive observations; the earlier capture-unavailable line was absent.
- Music was already playing during the successful check and was left playing. The test scene and Settings were closed; Minnow remains running.
- No binary rebuild followed the successful final permission grant. Stable certificate signing remains the longer-term way to avoid permission churn during development.

These observations supersede the earlier follow-up notes saying permission refresh and connected-route verification were pending. Full reconnect popup timing, real lockscreen interaction and sleep/wake still retain their separate hardware gates.
