# Device-switch responsiveness investigation — 2026-11-06

Work began on the existing local `main` checkout at `778aa99`, with a clean working tree. No applicable AGENTS.md was found in the repository or its parent directories. The Calendar/Shelf implementation in the current checkout was retained. No commit or push was made.

## Observed causes

A separate Core Audio test used the hardware available here: MacBook speakers → HDMI display → MacBook speakers. In the existing running build, 2,110 of 4,044 main-thread samples were in the AudioOutputs property-notification/reload path. Core Audio listener removal and registration dominated that path. A later three-second sample, after the route had returned to speakers and the normal Quit interaction timed out, found **all 1,479 main-thread samples still in that notification/reload path**. This is evidence of persistent main-thread starvation from the output-notification storm, rather than a capture-queue deadlock.

A rebuild/relaunch also exposed a separate startup stall: all 2,590 main-thread samples were waiting in IOBluetoothCoreBluetoothCoordinator initialization, called by registerForConnectNotifications. Registration, not just device queries, must be kept off the main actor.

Spotify Connect was investigated separately. The picker initially offered an iPhone and the transfer was attempted, but the subsequent picker still reported “This computer”; the phone was no longer available. That is **not a completed Mac → phone → Mac reproduction**. Its sample showed rendering/layout activity and did not establish a Spotify-transfer-specific deadlock. Synchronous desktop AppleScript refresh and accessory calls were found by source inspection and remain a separate plausible contributor to transfer-time stalls.

## Changes

- Output reads, selection, listener management, Bluetooth naming, volume-HUD reads, and Bluetooth registration/inspection/unregistration run on dedicated serial workers. Main-actor callbacks publish value snapshots only.
- Core Audio system listeners persist; per-device listeners change only when device IDs change. Notification bursts coalesce for 60 ms. User selection and other interaction are not debounced. Generations reject obsolete enumeration and selection completions.
- Capture retains its existing serialized asynchronous reconciliation and process-tap control queue. Duplicate route IDs do not restart capture; changed routes supersede obsolete setup and trigger recovery. Late sample deliveries cannot repopulate obsolete levels.
- Desktop playback and accessory AppleScripts use a serial worker. Playback notices coalesce; stale snapshots are rejected across stop/session-lock changes. User commands are no longer dropped merely because a refresh is in progress.
- No device transition recreates the shared playback session or island windows. Waveform observation is confined to the small visual consumers; unchanged native surface state no longer gets reapplied on every layout pass.
- Collapse clears interaction flags; output-picker dismantling closes the popover. Normal quit asynchronously waits for capture cleanup, output teardown, and queued script completion.
- One session-owned Spotify route refresh loop reuses the account integration. Playback-detail requests share in-flight work and a short cache; account generations reject old responses and HTTP 429 Retry-After gates further requests. Sleep supersedes in-flight route reconciliation. No playback transfer API is used.
- Confirmed playing phone/speaker-class devices show “Playing on [name]” and suspend Spotify capture. Silence never determines remote playback. Computer devices remain explicitly **unknown** unless a trusted local Connect ID is supplied to the classifier; the integration currently has no reliable source for that ID. Unknown state uses ordinary capture eligibility and is never labelled confirmed local. Automatic trusted identification of this Mac remains a limitation.
- The island pairs dark native materials with a dark SwiftUI environment and explicit light tab labels. Accessibility-display changes update the native appearance; reduced transparency uses an opaque dark surface. Settings retain their own system appearance. Capture/accessory diagnostics live in Settings.
- Music keeps its original content height, with only 28 points added for navigation when tabs exist. Today has bounded height; Shelf retains its previous sizing rule. The transparent interaction canvas accommodates all pages without rebuilding the window.
- Waveform defaults are on for debug and off for release. Saved choices win in both configurations.

## Validation and evidence

The final debug suite passed: 88 tests listed, with the three opt-in rendering/timing tests skipped in the normal run. The targeted tab-rendering and timing checks also passed separately. Debug/release app builds and packaging passed; the release-mode saved-preference test explicitly verified the off-by-default release behavior. Transition coverage exercises superseded capture setup, duplicate playback/route notices, sleep-style suspension during setup, failure/retry, late samples, remote suspension/local resumption policy, interaction cleanup, page sizing, and saved waveform preferences. Native rendering and timing tests run separately so rendering cannot delay unrelated hover-timer tests.

The isolated native tab matrix passed for Music/Today/Shelf selections under Aqua, Dark Aqua, and both increased-contrast appearances. PNGs in `.build/ui-checks/tabs-*.png` were visually inspected for readable selected/unselected labels.

A controlled 250-ms AppleScript occupied the main actor for approximately 255 ms on the original inline path. In the final isolated check, the main-actor interaction ran after approximately 35 ms while the worker completed at approximately 308 ms. One cold worker invocation itself took about 80 seconds to finish framework/script initialization while the main actor remained available; this is not a hardware transfer latency measurement. Timings must not be represented as a measured phone/AirPods speedup.

The rebuilt app launched after Bluetooth registration moved off main. Repeating the speakers/HDMI round trip no longer showed the old main-thread output-reload storm in its sample; remaining main-thread work was predominantly rendering/SwiftUI/accessibility. The waveform-observation and surface-update changes address that extra work. After the final rendering changes, an ordinary island expansion succeeded and exposed Music/Today/Shelf, playback controls, scrubber, and the correct speakers label. Subsequent attempts during route changes encountered stale accessibility IDs amid changing playback state, so complete end-to-end transition interaction is not claimed verified.

Raw samples are retained locally in `.build/diagnostics/`:

- `minnow-connect-before.sample.txt`: attempted Connect transfer; no completed phone transition.
- `minnow-output-before.sample.txt`: initial speakers/HDMI round trip.
- `minnow-after-output-attempt.sample.txt`: persistent old-process notification storm.
- `minnow-rebuilt-start.sample.txt`: Bluetooth registration semaphore stall.
- `minnow-output-after.sample.txt`: output round trip after worker/listener changes.

Debug Instruments intervals use subsystem `com.minnow`, category `DeviceTransitions`, interval `Transition`: output enumeration/selection, Bluetooth registration, capture start/stop/reconciliation, playback AppleScript/API refresh, and island reconciliation. They contain operation names/timing, not tokens or track metadata.

## Remaining hardware checks

No connected AirPods/Bluetooth output was listed in Sound settings. Complete Mac → phone → Mac, speakers → AirPods → speakers, rapid alternation, disconnect during setup, capture recovery, and expansion/scrubbing/tab interaction throughout those transitions still need a real hardware pass. Confirm waveform and normal quit after sleep/wake. Check native glass, hover/focus, live system appearance changes, and reduced transparency on the actual island. Speakers were restored after the HDMI checks. Do not treat the automated tests or HDMI sample as proof that every reported hardware freeze is fixed.
