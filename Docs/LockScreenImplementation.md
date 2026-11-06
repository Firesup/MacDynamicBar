# Lock screen implementation — development build

## Available controls

Settings → Lock Screen:

- **Lock Screen Player (Experimental)** installs the actual lock/unlock-driven player. Off by default until hardware verification. This is separate from Open Music Scene Preview.
- **Online Lyrics · LRCLIB** opts in to sharing track title, artist, album and duration with lrclib.net. Requests are track-bound, cancellable, duration-matched and memory-cached with a 30-entry bound. Imported local LRC remains supported. This uses the documented LRCLIB API, not a private Spotify endpoint.
- Battery, Weather, Calendar and Reminders have individual visibility toggles. macOS retains its native clock/date and authentication UI. Minnow does not hide or redraw those components.
- Settings → Today contains explicit Calendar and Reminders connect buttons, independent enable controls, and persisted source selections. The island Today page and lock-screen title/count summaries consume the same typed snapshots. The existing lockCalendar and lockReminders toggles remain independent privacy opt-ins; both default off. No completion control is exposed on the lock-screen strip. See CalendarReminders.md.
- Weather uses Apple WeatherKit and explicit latitude/longitude. A WeatherKit-enabled App ID, membership, entitlement and valid signing are required before live weather can succeed. The current ad-hoc bundle has no such provisioning; failure is shown as unavailable. Production attribution and provider provisioning must be completed before shipping weather.
- Timer uses a deadline and computes remaining time at display time; the initial UI provides start-five-minutes and stop controls. It is not a full timer management feature yet.

Settings → Events:

- Brightness Key HUD (Experimental) isolates dynamic DisplayServices access and watches brightness-key events. Unsupported symbols/displays fail without changing brightness. It does not suppress native HUDs, and Control Center changes without key events are not observed.
- Paired AirPods can be refreshed and connected with an explicit button. Connection happens off the main thread. Nearby case discovery and left/right/case battery readings remain unimplemented.

## Real lockscreen presentation

A dedicated nonactivating NSPanel is created at the shielding window level only after a lock state is detected and the feature is enabled. `canBecomeVisibleWithoutLogin` allows display without taking over authentication. The card has a liquid-glass surface on macOS 26+, with material fallback on older systems. Artwork press expands the cover; the lyrics button adds a synchronized lyrics column. Playback and seeking reuse the shared media session.

Only the card, expanded artwork and visible lyrics accept pointer events; the remaining transparent canvas is configured to pass through. Native widget strips are completely click-through. The panel cannot become the key or main window. A lock-scoped one-second watchdog checks for a missed unlock and updates hit regions. Unlock, stop and display changes close/demote the panels; sleep suspends them and wake rechecks the lock state. Initial overlay geometry is bounded to the selected screen and reserves a lower region for authentication. Rendering and hit testing share geometry, with expansion state per display; display preference changes rebuild the panels. This must be verified at real device sizes and OS scaling settings.

This implementation depends in part on distributed lock notifications and an observed session-state dictionary key. Keep this compatibility-sensitive layer isolated. A passing geometry test does not prove that input events reach these controls while macOS is actually locked.

## Verification performed and outstanding

Compilation and automated geometry/metadata/preference tests are run locally. No automation has locked the user's computer, entered a password, or sent a message. The real lockscreen has not yet been visually or interactively verified in this session. Do not claim the player is a 1:1 reproduction: glass rendering, scaling, artwork animations, pointer routing, automation while locked, and popovers still need live comparison with the supplied references.

Manual sequence:

1. Quit the old Minnow and any overlapping Canopy/Notchy lockscreen overlay; launch the rebuilt Minnow.app.
2. Play a track; enable Lock Screen Player. Enable Online Lyrics if desired.
3. Use macOS Lock Screen. Verify small card, click the cover to expand, toggle lyrics, use transport/seek, then click outside and type into the actual macOS password field.
4. Unlock through macOS. Verify no shielded panel remains above desktop applications. Repeat sleep/wake, external-display removal and disabling the feature.
5. Test privacy toggles with real calendar data only after granting permissions. Test brightness and paired-AirPods connection on hardware.

## Not complete from the five-phase roadmap

Focus integration, per-earbud/case batteries and nearby-case discovery, incoming/inline Messages, FaceTime/phone/Teams/Zoom/WhatsApp call adapters, FDA-backed notification history, WidgetKit extension targets, alternate HUD placements and native-HUD suppression remain unimplemented. These must not be advertised as working merely because their data model or settings page exists. A 1:1 visual match remains an acceptance target, not a verified result.
