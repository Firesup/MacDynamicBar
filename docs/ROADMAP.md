# Roadmap

Minnow is in active development and has not had a public release. Items are grouped by what exists in the code
today, not by what is promised.

## Implemented

- Apple Music and Spotify playback with controls, seeking, artwork, and audio-output selection
- Audio-reactive waveform
- Appearance options: three materials (Standard, Glass Inset, Soft Gradient) and two shapes (Apple Pill, Notch)
- Multi-display support, fullscreen hiding, launch at login
- AirPods connection popups and volume feedback, through a prioritised popup queue
- Today page for Calendar and Reminders
- Shelf: file drag and drop with Quick Look thumbnails and AirDrop sharing

## Experimental

These work in development builds but need broader hardware validation before being relied on.

- Lock-screen player, including interaction on the real lock screen
- Synced lyrics (local LRC files, optional online lookup)
- Brightness-key feedback
- Phone-call diagnostic (detection of FaceTime and Phone controls only)
- Weather widget (live data needs WeatherKit provisioning)

## Planned

- Camera mirror: on-demand preview, with the capture session released on dismissal and no background capture
- Per-display profiles with stable display identifiers
- Configurable gestures scoped to the island
- Layout presets and module ordering
- Broader Bluetooth events, with battery levels only from verified sources
- Production weather: provisioning, location selection, attribution and caching
- Capability-checked system HUD replacement
- Release distribution: Developer ID signing, notarisation and a downloadable build
- Extension contracts, once internal interfaces are stable
