# Minnow V1

Native macOS island for Apple Music and Spotify. Requires macOS 14+ and Swift 6.4.

## Build and launch

From this folder:

```sh
zsh scripts/build-app.sh
open .build/Minnow.app
```

Quit the previous Minnow instance first. The build script creates and locally signs a development app; it does not install or launch it. Launch the bundle above rather than an older copy in Applications. Release signing, notarization, and distribution are separate work.

The active source is the complete `Sources/MacDynamicBar` directory. SwiftPM compiles its Swift files together as one app target. The obsolete monolithic file and excluded prototype definitions have been removed. Use the project as a whole; this version cannot be installed by replacing one Swift file.

## Feature branch and structure

Work is on `feat/island-events`. Commit `e020c7e` checkpoints the working music island before changes; `4ca3a6a` splits it without changing behavior (all 19 existing tests passed at that checkpoint).

- `App/`: startup and menu bar.
- `Island/`: shared surface, shape, animation, display windows, hover state, visibility, and coordination.
- `Media/`: music content, Apple Music/Spotify playback, account linking, scrubbing, outputs, and audio levels.
- `Settings/`: saved preferences and native settings interface.
- `Events/`: event values, popup queue, and reusable popup content.
- `Battery/`: event-driven Mac power monitoring and battery alert policy.
- `AirPods/`: Bluetooth connection monitoring, recognition, and duplicate suppression.

Sports and Weather can later submit presentation data through the same event coordinator. They are not implemented in this branch.

## Menu

1. Hide Island / Show Island
2. Source → Auto, Music, Spotify
3. Audio-Reactive Waves
4. Refresh Playback
5. Settings…
6. Quit Minnow

Hide stops displaying the island and suspends waveform capture; it leaves the music application playing. Auto follows the most recently started player. Music and Spotify keep the selected player fixed.

## Settings

The settings window follows the supplied 1:21 PM Canopy reference: dark sidebar, search, source tiles, rounded groups, and five pages.

- **General:** launch at login, open settings on launch, automatic/all/main/individual displays, enable island, hide in fullscreen, menu icon visibility, haptics, slight hover expansion (default), full-player hover expansion, reset preferences.
- **Media:** media enable, Auto/Music/Spotify source cards, Heart/Shuffle/Repeat/None, cover visibility and motion, explicit badge/colour, heart colour from artwork, live waveform and retry, pause collapse, pause hiding (instant/delay/never), collapse after seeking, Spotify account.
- **Appearance:** Standard/Glass Inset/Soft Gradient material selection and Apple Pill/Notch shape, glass, clear-to-dark background tint/opacity, background blur, automatic/custom sizing, notch width and height offsets, system Reduce Motion support.

Choose **Appearance → Layout → Glass Inset** for option C. Standard remains the default and existing installations stay on their current appearance. Glass Inset uses an opaque black camera header, compact wings, and ten-point outer frame; the expanded player has a separate inset native glass panel. The black shell has a cutout so an opaque backing does not block the material. Its panel and rim resize with the existing surface spring. The Glass Tint slider adjusts the inset; switching back restores the existing Standard glass/blur settings. macOS 14–25 use blurred material in the same layout. Native material appearance still needs a live playback check.

Preferences persist and apply live. General reset keeps Spotify credentials and actual macOS login-item registration. Reopen Minnow from Finder to reach Settings when its menu icon is hidden. Hiding/disabling the media surface does not pause music in the desktop app.

Fullscreen hiding watches macOS system presentation options as well as Space/application changes, then checks the frontmost app's window bounds on each display. It also handles the camera strip reserved above native fullscreen windows, regardless of whether playback is playing or paused. Fullscreen games or apps with unusual window arrangements still need live verification. All displays share one playback/capture session.

### Differences and deferred controls

- **Hide from Screen Capture:** shown unavailable. Apple's current documentation calls the old NSWindow sharing exclusion a legacy constant that macOS no longer uses; Minnow does not promise that screen recorders will omit it.
- **EQ:** shown unavailable. Processing another app's audio requires a separate routing/processing engine. Existing playback capture only measures sound; it does not alter output.
- **Animate Artwork:** applies gentle movement to the static cover while playing. It does not download video artwork, which the desktop scripting interfaces do not supply.
- **Explicit labels:** read from the optional Spotify connection only when the API track URI matches the desktop track. Apple Music's scripting data here does not expose an explicit-content flag. Unknown status never produces a guessed badge.
- Lockscreen, weather, sports feeds, and sound effects tied to lock/unlock remain deferred.

Launch at login uses macOS ServiceManagement and needs the bundled app at a stable location. Glass uses the native glass view on macOS 26+ and a blurred material on older systems.

Playback controls have explicit white icons. The scrubber uses a muted full-length track and white elapsed bar. Dragging previews the position and seeks once on release; changing songs or sources cancels the drag. The output picker lists connected Mac audio outputs in a transient native popover. Clicking another app dismisses it and collapses the player; selecting an output also dismisses it.

The automatic expanded size is now 408 × 136 points below the notch (previously 400 × 174). Artwork is 40 points; the title is 14-point semibold and the artist row is 12-point semibold. Spacing and padding are tighter, while playback and output buttons retain their existing hit areas. Existing manual dimensions are preserved; use Automatic Sizing for the new defaults.

## Hover, contrast, shape, and links

- **General → Slight Hover Expansion** is on by default. **Expand on Hover** overrides it to open the full player. Turning both off disables hover resizing. Click-pinned expansion still works.
- Labels and timestamps use brighter, heavier lettering with a subtle glyph shadow. Rectangular text backings have been removed. The policy follows system increased contrast and does not sample the wallpaper or start screen capture.
- **Appearance → Layout → Soft Gradient** fades black into the actual wallpaper or windows behind the player. **Background Visibility** controls transparency from 0% to 85%, independently of Glass Tint. The default is 45%. The compact surface and camera header stay black. System Reduce Transparency keeps the surface opaque.
- **Appearance → Island Shape → Notch** connects the expanded surface to the display's top edge with concave shoulders; **Apple Pill** keeps rounded upper corners. Shape and material are independent and saved. Existing installations keep their current material and Apple Pill shape.
- In the expanded metadata row, the Spotify label opens the desktop app. With account metadata for the exact desktop track, individual artist names open their artist pages. Otherwise the label explicitly offers an artist search. Track changes invalidate the old artist links.

Spotify artist and search URIs were tested live through the desktop URL handler: both opened the expected Spotify artist/search view. Full island-button click routing, output-popover dismissal, glass contrast on real wallpaper, and fullscreen transitions still require a live test of the rebuilt Minnow app.

Spotify desktop playback, controls, artwork and seeking do not require Web API login. Liked Songs and repeat-one use the existing optional Spotify account connection in Media Playback. The redirect registered for that developer app must match `http://127.0.0.1:8888/spotify/callback`. No client secret belongs in this app.

Allow Automation access for the music applications when prompted. Audio-reactive waves also need macOS capture access and display the system capture indicator while active. Disable waves to stop audio capture.

## Validation

`swift test` covers geometry, hover/pinning, delayed hover exit during scrubbing, persistent preferences/custom sizing, layout migration and switching, inset geometry around the camera, seek clamping/invalid input, default-versus-full hover, automatic contrast, Spotify URI encoding and stale-track metadata, connected-notch geometry, and output-picker state reset.

Native compilation and 36 default checks plus a separately enabled scene-render check passed in this workspace. The app bundle and Info.plist were checked. The three popup contents were rendered offscreen and visually reviewed at the smallest supported width. A running Minnow instance was not replaced or relaunched, so end-to-end island UI checks remain unverified. Live player permissions, hardware output changes, Spotify account writes, fullscreen Spaces, and login registration also need a live desktop check.

## Popups

Open **Settings → Popups** for AirPods Connections, Low Battery Alerts, Power Connected, and three preview buttons. All are enabled by default and persist independently. Preview values are explicitly labeled sample data; they do not connect devices, change power state, or start music.

- **AirPods:** connection callbacks use IOBluetooth, with a short settling delay and per-device disconnect listeners. Existing connected devices are seeded silently on launch/wake. Duplicate callbacks and short reconnect storms do not repeat the popup. Recognition uses known Apple SDP device IDs when cached and AirPods names as a fallback; unrecognized or unusually renamed models may be missed. SF Symbols provide AirPods/Pro/Max artwork in an iOS-inspired popup; this is not Apple's private pairing sheet or its 3D animation. Connection status is separate from being selected as the Mac's audio output.
- **AirPods battery:** not implemented in this stage. Real connection events show no percentage. The preview's 82% is sample data. Per-earbud/case percentages still need hardware investigation; no private API or guessed reading is used.
- **Mac battery:** public IOKit power-source notifications; 20% and 10% alerts are emitted once per discharge cycle, including an initial low reading. Crossing both at once shows only the more urgent alert. External power resets the warnings. Plugging in reports the percentage and distinguishes charging from connected-but-not-charging. Launching already plugged in produces no connection popup. Invalid readings and desktop Macs produce none.
- **Presentation:** one popup at a time, with a bounded priority queue. Low battery can preempt a connection/charging popup. Scrubbing or using the output selector defers incoming events; stale deferred events expire. Dismissal (automatic after two seconds by default (configurable from 1–10 seconds), close button, header click, or outside click) restores the previous player presentation. Playback itself continues untouched.
- **Visibility:** respects manual hiding, chosen displays, fullscreen hiding, sleep/session inactivity, and Reduce Motion. Hidden events are discarded rather than replayed later. Popups can appear independently of Media being disabled or hidden on pause, then restore the prior hidden media state. No new polling timer is used for device or power monitoring; one-shot tasks handle settling and dismissal.

Bluetooth access may be requested for the bundled app. If connections are not detected, inspect **System Settings → Privacy & Security → Bluetooth** and the status shown on the Popups page. `--settings-preview` does not start the device monitors or playback; preview buttons can still show sample island content.

## Hardware and UI verification still needed

1. Quit the previous instance and launch `.build/Minnow.app`; open Settings → Popups and try each preview.
2. Confirm music resumes its previous compact/expanded state after a popup, and verify previews wait while scrubbing or while the output picker is open.
3. Verify hide/show, fullscreen on each selected display, Media disabled, hide-on-pause, and sleep/wake. Hidden events must not replay.
4. Connect/disconnect your AirPods, Pro, or Max. Verify model artwork, device name, Bluetooth permission handling, no popup for already-connected devices on launch, and no duplicates. Renamed and newer models need specific hardware checks.
5. Plug/unplug the charger, including optimized charging (connected but not charging). Threshold logic is tested with synthetic readings; a real low-battery transition has not been observed in this session.

## Manual check

Open the built app and confirm the menu order and all three settings pages. Change sizing and opacity, close/reopen settings, and relaunch to confirm persistence. With a song playing, verify white transport icons, seeking, manual/Auto source selection, and output switching. Verify Hide/Show, hover, pause delays and display reconnects. Test launch at login after moving the app to a stable location.


## Native surface iteration

Branch: `feat/native-activity-surface`. See [implementation scope and staged plan](Docs/NativeSurfacePlan.md) for delivered behavior, platform limitations, reference links, and outstanding verification.

- Select **Appearance → Island Shape → Notch** to keep connected shoulders in compact, hover, and expanded states. New installations default to Notch; saved explicit appearance choices are retained.
- **Settings → Events** now includes **Collapse After** (two seconds by default), notification preview, activity visibility, and a clearly labelled activity preview. Mac charging is the first real activity source. Music stays primary while playing; charging appears in a separate side capsule. No other app's notifications or mirrored Live Activities are imported.
- **Settings → Music Scene → Open Music Scene Preview…** opens the unlocked-session reference scene. Click the album cover or Expand Artwork; import a current-track LRC file and turn Lyrics on. macOS authentication and the secure lockscreen are not replaced. Weather remains unconnected, and AirPods/Focus data is not fabricated.

Functional tests and popup snapshots run with the existing `swift test` command. The slower scene layout render is opt-in and should run separately from timing-sensitive hover tests:

```sh
MINNOW_RENDER_SCENE=1 swift test --filter musicSceneRendersWithoutStartingPlaybackOrDeviceMonitoring
```

Use the cache flags/environment from `scripts/build-app.sh` in restricted workspaces. The native scene's embedded AppKit controls and glass require a live window check; ImageRenderer snapshots do not fully render them.


## Compact spacing, HUDs, and revised lockscreen research

The compact Notch header now has 12-point horizontal insets and wider automatic wings so artwork and waveforms have breathing room. The activity capsule is 88 × 26 points (previously 116 × 30). Persistent battery/charging activities are removed; macOS handles low-battery and charging alerts. Battery readings still support the separate music-scene widget.

Volume feedback observes Core Audio scalar/mute changes and refreshes during repeated key presses, without intercepting keys or suppressing Apple's HUD. Outputs without a readable master volume scalar are unsupported for now. Brightness is pending a separate adapter. Events has a volume-HUD preview.

The earlier lockscreen feasibility conclusion is corrected in [LockscreenResearch.md](Docs/LockscreenResearch.md): a shielding-level NSPanel with `canBecomeVisibleWithoutLogin` has a demonstrated route to the real lockscreen. It still requires a dedicated opt-in prototype and hardware verification, especially for interactive controls. The existing unlocked Music Scene has not been relabelled as a working lockscreen.
