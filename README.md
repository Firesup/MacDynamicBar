# Minnow

A small, native macOS player that lives in the notch. Minnow shows what is playing in Apple Music or Spotify,
puts playback controls and seeking a click away, and surfaces system moments such as an AirPods connection in
the same space.

![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift 6.4](https://img.shields.io/badge/Swift-6.4-orange)
![Status: in development](https://img.shields.io/badge/status-in%20development-blue)

**Interactive demo:** a browser recreation of the island (not the native app) is on the
[portfolio site](https://abisan-portfolio.vercel.app/#projects).

## Why it exists

Changing a track or checking what is playing usually means leaving whatever you are working on. Minnow keeps
that information and control in a fixed, glanceable place at the top of the screen, and stays out of the way
when it is not needed.

## Features

**Music**
- Apple Music and Spotify, with Auto, Music or Spotify source selection
- Playback controls, artwork, and a scrubber that previews while dragging and seeks once on release
- Audio-output picker with personalised Bluetooth device names
- Audio-reactive waveform measured from playing audio
- Optional Spotify account link for Liked Songs, repeat-one, explicit labels and artist links

**Island**
- Compact, hover and expanded presentations, in Apple Pill or connected Notch shape
- Three materials (Standard, Glass Inset, Soft Gradient) with adjustable tint, blur and sizing
- Multiple displays, automatic hiding in fullscreen, launch at login
- Respects system Reduce Motion and Reduce Transparency

**Events and productivity**
- AirPods connection popups and volume feedback, through a prioritised, expiring popup queue
- Today page for Calendar events and Reminders (opt-in; reminders complete only on request)
- Shelf for dragging files onto the island, with Quick Look thumbnails and AirDrop sharing (off by default)

**Experimental** (opt-in or user-triggered): lock-screen player, synced lyrics, brightness feedback, phone-call
diagnostic, weather widget. See the [roadmap](docs/ROADMAP.md).

## Build and run

Requires macOS 14 or later and a Swift 6.4 toolchain.

```sh
zsh scripts/build-app.sh
open .build/Minnow.app
```

Allow Automation access for Music and Spotify when prompted. Details, signing options, VS Code setup and
troubleshooting are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Engineering notes

The parts I found most interesting to build:

- **A priority queue for transient events.** Monitors emit value types, and one coordinator orders them by
  priority, drops duplicates and expired events, preempts without replaying superseded popups, and defers
  presentation while the user is mid-interaction.
- **A presentation state machine** (compact, hover, expanded, pinned) with a debounced exit that is suppressed
  during scrubbing, output selection and drag and drop.
- **Isolating blocking AppleScript** behind a serial worker with an async interface, so controlling Music and
  Spotify does not block the UI.
- **Policies as pure value types with injected clocks**, which makes reconnect-storm suppression, popup
  expiry and device naming unit-testable without hardware.
- **Explicit capability handling.** The app shows an unavailable state rather than guessing: no explicit badge
  without a matching Spotify track, no AirPods battery from an unverified source.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) has the system diagram and the reasoning behind each decision.

## Testing

```sh
swift test
```

Swift Testing covers layout and geometry, the hover state machine, persisted preferences, seek handling, the
popup queue and event policies, device naming, Shelf persistence, and Today snapshots. Behaviour that depends on
hardware or system permissions is verified manually; the checklist is in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Permissions and privacy

Minnow has no analytics or telemetry. Each permission it requests, and every case where it makes a network
request, is listed in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

## Project layout

```
Sources/MacDynamicBar/
  App/  Island/  Media/  Events/  AirPods/  Battery/  SystemHUD/
  Today/  Shelf/  LockScreen/  MusicScene/  Widgets/  Settings/  Integrations/
Tests/MacDynamicBarTests/
Support/Info.plist
scripts/build-app.sh
docs/
```

The Swift package is named `MacDynamicBar`, the project's original working name. The app is **Minnow**.

## Status

In active development, with no public release yet. Release signing and notarisation are planned work.

## Acknowledgements

Minnow is an independent implementation on Apple's public APIs. [Boring Notch](https://github.com/TheBoredTeam/boring.notch)
(GPL-licensed) and Notchy's public documentation were used only as references for what features exist in this
category; no code from either was copied or translated. Synced lyrics use the [LRCLIB](https://lrclib.net) API.

## Author

Built by Abisan Vijayakaran, Computer Science at Wilfrid Laurier University.
[Portfolio](https://abisan-portfolio.vercel.app/) · [LinkedIn](https://www.linkedin.com/in/abisanvijayakaran/)
