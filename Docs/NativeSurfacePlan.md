# Native activity surface and music scene

> Update: the lockscreen feasibility restriction below is superseded by [LockscreenResearch.md](LockscreenResearch.md). A real lockscreen overlay route has been identified. Persistent battery activities were also removed; macOS handles power alerts, and Minnow now observes volume changes for HUD feedback.

## Product boundary

Minnow is moving toward a unified event/activity surface. This iteration does not replace macOS Notification Center, import every app's notifications, take ownership of mirrored ActivityKit activities, suppress Apple's system indicators, or replace the secure login/lock screen. Those are different integrations from drawing a similar interface.

Apple's public UserNotifications APIs manage the calling app's notifications. ActivityKit/WidgetKit describe presentations belonging to their source app and mirrored presentations managed by the OS. The documented macOS widget placements do not provide an interactive secure-lockscreen extension point. No supported implementation route for the requested 1:1 secure-lockscreen integration was identified. This is an engineering finding from the documented APIs, not a claim that no private or unsupported technique exists.

The Music Scene is explicitly an unlocked-session preview. It must never be marketed as a security feature, request credentials, imitate an authentication prompt, change lock security preferences, or keep the real lock screen from appearing. A screensaver-only implementation would not satisfy the requested interactive lockscreen behavior either.

## Delivered in this iteration

- Notch shoulders remain connected when collapsed. Additional width preserves coverage of the camera housing. Pill remains an appearance option. New installations default to Notch; existing explicit shape selections remain saved.
- Automatic expanded music content is 408 × 136 points below the camera strip. Physical camera height is preserved. Custom size preferences remain respected.
- Events expand the surface and restore the prior presentation after two seconds by default. Settings allow 1–10 seconds. Existing AirPods and Mac power sources use this behavior. Notification preview demonstrates the shared presentation; it is not a cross-app notification listener.
- Compact AirPods and power presentations use SF Symbols, lighter type, tighter spacing and charge-appropriate low-battery iconography. These are native-inspired custom UI, not Apple's private pairing assets.
- A single shared activity store drives primary/side presentation. While music is playing and Media enabled, music stays primary and charging status occupies a separate side capsule. When music is idle, activity detail can occupy the main expanded island. Charging state comes from public power notifications; unplugging removes it. Activity preview is explicitly marked sample data and expires after 30 seconds. No sports data feed is connected.
- Music Scene has its own settings page and window. It shares the current playback/control session, native glass on supported systems with material fallback, clickable artwork expansion, a clock, date, Mac battery and local LRC lyrics. It does not create a separate playback source or start music when opened.
- LRC input is size-limited, track-bound, sorted, deduplicated and supports fractional/repeated timestamps and millisecond offsets. No lyrics are scraped or fetched from private Spotify endpoints.

## Outstanding work and acceptance gates

### 1. Native surface validation

Verify with the running app on a notched display and an external display: camera coverage in all states, reduced motion/transparency, smallest custom size, popup interaction deferral, manual/fullscreen hiding, and side-capsule click/popover dismissal. Verify display-edge behavior: the side capsule is omitted if it cannot fit, rather than placed offscreen. Current native compilation and offscreen rendering do not substitute for these checks.

### 2. Events and activities integrations

Add documented, opt-in sources with explicit permissions and availability. Feed adapters submit value data to the coordinator instead of owning windows. Cross-app notification harvesting, notification database scraping and UI extraction are not implemented. Do not tell users their existing Apple Sports activity has been imported. A future sports provider needs coverage/licensing/freshness decisions and a real update feed before release.

### 3. Music Scene visual and interaction validation

Compare the normal and expanded artwork compositions at 780 × 640 and 1100 × 760, on Retina displays, with real tracks and both light/dark wallpapers. Check glass on macOS 26+ and material fallback on older supported systems. Verify output popover, seeking, artwork toggling, local lyric track changes, font scaling and keyboard access. The offscreen scene render cannot faithfully capture embedded AppKit controls or live material; its image is a layout check, not proof of a 1:1 result.

### 4. Weather and accessory widgets

Prefer WeatherKit for a native Apple weather source, after configuring the App ID capability, signing, location consent or an explicit chosen location, and required attribution. An Apple Developer Program membership is required. No entitlement, key or membership is assumed in the current ad-hoc build. Weather remains visibly unconnected. AirPods earbud/case battery and Focus require separately verified sources; no sample reading should appear as live state.

### 5. Lyrics provider

Spotify has no public lyrics endpoint. For downloadable releases, evaluate a licensed lyrics service and its synced-text/display/caching rights. Keep provider authentication separate from UI; prefer a backend for provider secrets. Local LRC works independently and does not imply permission to redistribute copyrighted lyrics.

### 6. Secure lockscreen decision

This remains blocked pending a supported extension/integration mechanism. Do not replace it with a fake password screen or claim the Music Scene is the lockscreen. If Apple introduces suitable APIs, reuse the scene's feature views/data models behind a new presentation adapter and verify privacy and authentication boundaries on hardware. This gate is equally important to the island work and is not marked complete.

## Primary references

- https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy
- https://developer.apple.com/documentation/widgetkit/widgets-and-complications-collection
- https://developer.apple.com/documentation/activitykit
- https://support.apple.com/en-au/120684
- https://developer.apple.com/weatherkit/
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit
- https://community.spotify.com/t5/Spotify-for-Developers/Update-endpoint-for-lyrics/td-p/5355493
