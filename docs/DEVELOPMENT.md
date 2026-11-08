# Development

## Requirements

- macOS 14 or later
- A Swift 6.4 toolchain (`swift-tools-version: 6.4` in `Package.swift`)

## Build and run

```sh
zsh scripts/build-app.sh
open .build/Minnow.app
```

The script builds the Swift package, generates the app icon, assembles `Minnow.app` (copying `Support/Info.plist`),
validates the plist and signs the bundle. It does not install or launch the app. Quit any running copy first and
launch the freshly built bundle, not an older copy in `/Applications`.

| Variable | Purpose |
|---|---|
| `MINNOW_BUILD_CONFIGURATION` | `debug` (default) or `release` |
| `MINNOW_SIGN_IDENTITY` | A code-signing identity, for example `"Apple Development: Your Name (TEAMID)"`. The default is ad-hoc signing. |

A persistent signing identity keeps macOS privacy permissions attached to the app across rebuilds. With ad-hoc
signing, the identity changes whenever the executable changes, so permissions may need to be granted again.

## Run from VS Code

Open the folder containing `Package.swift`, open `Sources/MacDynamicBar/App/MacDynamicBar.swift`, then choose a
configuration in Run and Debug:

- **Debug Minnow**: build, package, sign and launch (F5 to debug, Control+F5 to run without debugging)
- **Release Minnow**: the same with an optimised build
- **Minnow Settings Preview**: opens the settings window in isolation, without starting playback or device
  monitoring

The workspace sets `swift.autoGenerateLaunchConfigurations` to `false` so the Swift extension does not replace
these bundle-aware configurations. The entry point depends on the rest of the package; it is not a standalone
script.

## Tests

```sh
swift test
```

The suite uses Swift Testing. A slower offscreen scene-render test is opt-in and should run separately from the
timing-sensitive hover tests:

```sh
MINNOW_RENDER_SCENE=1 swift test --filter musicSceneRendersWithoutStartingPlaybackOrDeviceMonitoring
```

Automated tests cover geometry, state machines, policies and persistence. Anything that depends on hardware or
system permissions is verified by hand: see the checklist below.

## Manual verification checklist

1. Launch `.build/Minnow.app` and confirm the menu bar item and all settings pages.
2. With a song playing, check transport controls, seeking, source selection (Auto, Music, Spotify) and output
   switching.
3. Change sizing, opacity and layout, close and reopen settings, relaunch, and confirm preferences persist.
4. Check hide and show, hover, pause delays, display reconnection, fullscreen hiding and sleep and wake.
5. Connect and disconnect AirPods: confirm one popup per connection, none at launch for already-connected
   devices, and no duplicates.
6. Move the app to a stable location and test launch at login.

## Troubleshooting

**Audio waveform stays idle and the app reports ScreenCaptureKit error `-3801`.** A rebuilt development app can
keep a stale entry in *System Settings → Privacy & Security → Screen & System Audio Recording*. Remove the Minnow
entry, add the current `.build/Minnow.app`, then quit and reopen Minnow. The Media settings page shows live
capture status and offers a retry that does not change your saved preference.

**Bluetooth popups never appear.** Check *Privacy & Security → Bluetooth*, and the status text on the Popups
settings page.

## Optional Spotify account link

Playback, controls, artwork and seeking use the Spotify desktop app and need no login. The optional account
link enables Liked Songs, repeat-one and explicit-content labels. Register this redirect URI in your own Spotify
developer app:

```
http://127.0.0.1:8888/spotify/callback
```

No client secret is stored in or required by the app.

## Naming

The Swift package and executable target are called `MacDynamicBar`, the project's original working name. The app
bundle and everything user-facing is **Minnow**.
