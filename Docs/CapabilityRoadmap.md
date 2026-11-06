# Minnow capability roadmap

The user's supplied Notchy feature list is the capability benchmark. It is not evidence that every feature shares the same API, permission model or reliability. Feature status must distinguish advertised behavior, independently inspected implementation and hardware verification. Preserve the native presentation and modular structure as these integrations are added.

## Earlier research tracks (retained for context)

| Phase | Work | Completion gate |
|---|---|---|
| 1 | Real lockscreen panel: clock/date, Now Playing, Mac battery, per-widget toggles, expandable art, transport hit regions | Verify on a genuinely locked Mac; clicks outside controls reach macOS authentication; unlock, sleep and display changes always remove or restore the panel correctly. Current Music Scene is only an unlocked preview. |
| 2 | LRCLIB synchronized lyrics in the island and lockscreen | Fetch on track change with title/artist/album/duration matching, identified client headers, bounded caching, cancellation and stale-result rejection. Handle instrumental/missing/plain-only responses. Render synchronized text using playback position. Verify service requirements before distribution. |
| 3 | Brightness/volume HUDs and optional alternate placements | Volume monitor already exists. Investigate display-specific brightness and native-HUD suppression separately; validate rapid changes, fixed-volume devices, unsupported displays and restoring OS behavior on quit. |
| 4 | Weather, timer, calendar/reminders and Focus | Separate data adapters and opt-in permissions; weather location/city selection; account for unavailable/stale data and Focus-driven alert policy. Timer display is computed from deadlines, not a decrementing counter. |
| 5 | AirPods manager | Test actual case discovery, per-bud/case battery and connection methods on real Apple models. A connected-device popup does not prove nearby discovery or one-tap connection support. No invented percentages. |
| 6 | Messages, FaceTime/phone, Teams/Zoom/WhatsApp | App-specific Accessibility probes first. Verify sender/body/caller extraction and routing. Preview inline reply/answer/decline actions without executing them. Sending, answering or declining requires a direct user gesture. Distinguish calls from music using explicit call state. |
| 7 | Optional notification history mirror | Inspect the current macOS data source and actual Full Disk Access requirements. Keep this independent of Accessibility-based banners. Minimize stored message content and expose clear disable/clear controls. No promise of a stable cross-app public notification API. |
| 8 | Drive eject, charge-threshold alerts, desktop widgets | Drive detection/eject uses a dedicated adapter and reports actual eject results. Full-charge alerts are opt-in because the user currently wants power alerts handled by macOS. WidgetKit requires a real bundled extension target, shared snapshot storage and correct signing; floating desktop panels are not equivalent to WidgetKit widgets. |

## Integration boundaries

- LockScreenPresentation owns only lockscreen windows, lifecycle, hit regions and cleanup. It consumes existing media/widgets state instead of creating another music session.
- Event sources emit typed data to the shared coordinator. They never own the island window.
- Notification history and transient app UI extraction are distinct providers with distinct permissions.
- Private/system-version-sensitive integrations live behind capability-checked adapters with an unavailable state. Do not enable an unverified adapter by default.
- Accessibility is not a global message/call API: each supported application's real UI needs verification. Permission granted does not guarantee the data or action exists.
- Desktop WidgetKit extension, main app and lockscreen presentation share value snapshots; do not attempt to move an arbitrary NSView into Notification Center.
- The absence of a documented app-extension API is not a finding of impossibility. Research existing implementations and document what is actually demonstrated, as corrected in LockscreenResearch.md.

## Current baseline

The repo has a modular island, compact spacing, a smaller side capsule, an event queue, volume observation, an unlocked music-scene preview, local LRC parsing, and the Calendar/Reminders Today milestone described below. Experimental real-lockscreen panels, optional LRCLIB lyrics, brightness-key feedback, paired-AirPods connection and widget service adapters are implemented; see LockScreenImplementation.md for their limits. Real locked-screen interaction and hardware behavior remain unverified. FaceTime/Phone now has a user-triggered Accessibility diagnostic and sample call popup; automatic detection and call actions are not implemented. Messages, nearby AirPods, notification history and WidgetKit extensions remain unimplemented. Live WeatherKit needs provisioning. Charge-threshold alerts must remain separate from the removed persistent battery activity.

## Sources inspected

- Notchy feature/settings documentation: https://notchy.dev/help/settings/
- Notchy FAQ: https://notchy.dev/faqs/
- LRCLIB API documentation (including client identification and response schema): https://lrclib.net/docs and https://lrclib.net/docs.md
- Apple WidgetKit placements: https://developer.apple.com/documentation/widgetkit/widgets-and-complications-collection
- Actual lockscreen probe source and caveats: see LockscreenResearch.md.


## Current delivery milestones — November 5, 2026

Calendar/Reminders is the first product milestone in this continuation. The older numbered research tracks above are not a claim that their hardware gates have passed.

| Milestone | Scope | Status / acceptance gate |
|---|---|---|
| 1 · Calendar and Reminders | Typed EventKit snapshots; Today page; explicit connection; independent enable and persisted calendar/list selection; due, overdue and undated reminders; explicit completion with failure recovery | Implemented in this working tree. Automated validation and manual permission/hardware gates are recorded in CalendarReminders.md and ContinuationValidation.md. |
| 2 · Shelf | File drag/drop, thumbnails, persisted security-scoped file access, native AirDrop sharing | Implemented in this working tree after the Calendar milestone check-in. Defaults off. Native drag/thumbnail/AirDrop hardware acceptance remains manual; see Shelf.md. |
| 3 · Camera mirror | On-demand preview with explicit camera permission; release the capture session on dismissal | Pending. No background camera capture. |
| 4 · Display profiles | Per-display sizing, stable identifiers, disconnect/reconnect fallback | Pending. Existing display selection and sizing remain. |
| 5 · Island gestures | Configurable gestures scoped to the island hit region | Pending. Preserve native interactions elsewhere. |
| 6 · Transient power indicators | Optional charging and percentage presentation | Pending. Preserve the absence of persistent battery activities. |
| 7 · Bluetooth events | Broader connect/disconnect events; batteries only from verified sources | Pending. Preserve personalized AirPods naming and current connection handling. |
| 8 · Production weather | WeatherKit provisioning, location selection, attribution, caching and freshness | Pending. Existing development adapter is not production readiness. |
| 9 · Layout presets | Presets and module ordering | Pending. Calendar milestone uses only Music/Today, without a freeform editor. |
| 10 · HUD compatibility | Capability-checked HUD replacement; native suppression and keyboard-backlight research | Pending. Existing volume observation and experimental brightness feedback do not replace macOS HUDs. |
| 11 · Real lock screen | Actual lock/unlock, authentication routing, controls, sleep/wake and displays | Pending hardware validation. An unlocked scene is not evidence. |
| 12 · Extensions | Third-party contracts after internal interfaces stabilize | Pending. No executable extension API is exposed yet. |

## Boring Notch behavior reference and licensing boundary

Reference: [Boring Notch README](https://github.com/TheBoredTeam/boring.notch/blob/main/README.md), reviewed November 5, 2026. Only its public behavior/feature descriptions were used; no GPL implementation was copied or translated. Minnow's EventKit adapter and state services are independent Apple-API implementations.

- Upstream's checked/implemented feature list includes playback, Calendar, Reminders, mirror, charging percentage, gestures, Shelf/AirDrop, sizing and system HUD replacements. This is upstream's published implementation status, not a claim that we ran or verified its runtime behavior.
- Upstream's unchecked roadmap includes broader Bluetooth activity, weather, customizable layout, lock-screen widgets and extensions. Those items are not evidence of implemented upstream behavior.
- Minnow's completion gates are its own: a similarly named feature or upstream checkbox does not establish Minnow's permissions, reliability, visual equivalence or hardware compatibility.
