# Minnow capability roadmap

The user's supplied Notchy feature list is the capability benchmark. It is not evidence that every feature shares the same API, permission model or reliability. Feature status must distinguish advertised behavior, independently inspected implementation and hardware verification. Preserve the native presentation and modular structure as these integrations are added.

## Order and completion gates

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

The repo has a modular island, compact spacing, a smaller side capsule, an event queue, volume observation, an unlocked music-scene preview and local LRC parsing. Real lockscreen rendering/interactivity, online lyrics, brightness, calls/messages, nearby AirPods, notification history, weather and WidgetKit extensions are not implemented. Charge-threshold alerts must remain separate from the removed persistent battery activity.

## Sources inspected

- Notchy feature/settings documentation: https://notchy.dev/help/settings/
- Notchy FAQ: https://notchy.dev/faqs/
- LRCLIB API documentation (including client identification and response schema): https://lrclib.net/docs and https://lrclib.net/docs.md
- Apple WidgetKit placements: https://developer.apple.com/documentation/widgetkit/widgets-and-complications-collection
- Actual lockscreen probe source and caveats: see LockscreenResearch.md.
