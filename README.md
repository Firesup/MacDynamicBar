# Minnow

Minnow is a native macOS app that puts music controls and everyday information in a small island at the top of your display. It works with Apple Music and Spotify and can also show calendar events, reminders, and an optional file shelf.

**Minnow is a work in progress.** Features and appearance may change, and playback transfers, Bluetooth device switching, and experimental lock-screen behavior are still being tested. This is a development build, not a finished release.

## How it works

Minnow runs from the menu bar. Hover over the island for a small preview, or click it to expand. Settings let you choose the music source, displays, hover behavior, shape, materials, and sizing. Preferences are saved and apply live.

- **Music:** view the current track and artwork, play or pause, skip tracks, scrub through a song, and choose a Mac audio output. Auto source selection follows the most recently started player. Basic Apple Music and Spotify controls use the desktop apps; an optional Spotify account connection adds Liked Songs, repeat-one, and playback/device information.
- **Today:** connect Calendar and Reminders, choose which calendars and lists to display, view upcoming events and reminders, and mark reminders complete. Today can stay available when music is paused or Media is disabled.
- **Shelf:** enable a place for local file and folder references. Add items with the file picker or drag them onto the island, then open, drag out, or share them through AirDrop. Removing an entry leaves the original file untouched.
- **Appearance and events:** choose a notch or pill shape, dark or glass surfaces, and optional connection popups and system feedback. The island uses light labels on its dark surfaces and responds to accessibility display settings.
- **Experimental lock-screen player:** an optional lock-state overlay provides media controls, artwork, lyrics, and selected widgets. A separate Music Scene preview can be opened while unlocked. These features are still under development.

The optional live waveform measures the selected player's audio without changing or rerouting playback. It defaults **on in development builds** and **off in release builds**, while respecting saved preferences. Confirmed remote Spotify playback shows the destination device and suspends unnecessary local Spotify capture. Silence alone does not indicate remote playback; ambiguous computer devices remain unknown.

## How to run

### Requirements

- macOS 14 or later.
- Swift 6.4 or later, with Xcode or Command Line Tools configured for building macOS apps.
- Apple Music or Spotify installed for the corresponding playback controls.

### Build and launch

From the repository folder containing `Package.swift`:

```sh
zsh scripts/build-app.sh
open .build/Minnow.app
```

Quit any previous Minnow instance before launching the rebuilt app. The script compiles the complete Swift package, generates the app icon, and packages and locally signs `.build/Minnow.app`. Run that bundle to use the current build.

To build an optimized release configuration:

```sh
MINNOW_BUILD_CONFIGURATION=release zsh scripts/build-app.sh
open .build/Minnow.app
```

Both configurations write to the same app bundle. The default signature is ad hoc; this command does not create a notarized distribution. To use an installed signing certificate, set `MINNOW_SIGN_IDENTITY` when running the build script.

### First launch

Open Settings from Minnow's menu bar icon to select a player and enable optional features. Hiding the island does not pause playback in the music app.

Allow Automation access for Apple Music or Spotify when prompted. The waveform needs macOS System Audio Recording or Screen & System Audio Recording permission; Bluetooth features, Calendar, and Reminders require their corresponding permissions. Enable and connect only the features you want to use.

Basic Spotify playback does not require a Web API login. For optional account features, use **Settings → Media → Connect Spotify** with a Spotify developer app's public Client ID and the exact registered redirect URI:

```text
http://127.0.0.1:8888/spotify/callback
```

No client secret is needed. Account features depend on Spotify's account and API access requirements.

If audio capture stops working after a rebuild, check its status in Media settings and use **Retry Audio Capture**. An ad-hoc rebuild can invalidate the existing macOS capture permission; re-add the current `.build/Minnow.app` in Privacy & Security and reopen it if necessary.

### Run from VS Code

Open the repository folder in VS Code with Swift debugging support. Choose **Debug Minnow** in Run and Debug and press **F5**, or **Control+F5** to run without debugging. **Release Minnow** builds the optimized configuration. **Minnow Settings Preview** opens isolated settings without starting playback or device monitoring.
