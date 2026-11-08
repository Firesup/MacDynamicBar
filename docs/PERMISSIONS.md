# Permissions and privacy

Each system permission Minnow asks for is tied to a specific feature, and the reason shown to you is written into
the app's `Info.plist` usage strings.

| Permission | Why it is needed | Notes |
|---|---|---|
| **Automation (Apple Events)** | Read the current track and control playback in Music and Spotify | Requested the first time the app talks to each player |
| **Screen & System Audio Recording** | Measure playing audio to animate the waveform | macOS shows its recording indicator while capture is active. Turning the waveform off stops capture. The app only measures levels; it does not save or alter audio. |
| **Bluetooth** | Detect AirPods connections to show a popup | It does not pair devices or scan for nearby ones |
| **Calendars** and **Reminders** (full access) | Show selected calendars and reminder lists in the Today page | Off until you connect each one. Only the calendars and lists you select are read. Reminders are marked complete only when you press the completion control. |
| **Files** (via the system picker and drag and drop) | Keep items on the Shelf | Stores security-scoped bookmarks, not copies. Removing an item from the Shelf never deletes the original file. Shelf is off by default and never appears on the lock screen. |
| **Login item** | Launch at login | Uses the macOS ServiceManagement API |

## Network access

The app contains no analytics or telemetry code. It makes network requests in four cases:

- **Spotify album artwork.** While Spotify is playing, the cover image is downloaded from the URL the Spotify
  desktop app reports. Only HTTPS URLs are accepted, the response must be an image, and downloads are capped at
  10 MB. No account link is needed for this.
- **Spotify account link (optional).** Used for Liked Songs, repeat-one and explicit labels. Credentials are
  kept in the macOS Keychain. The app contains no client secret.
- **Online lyrics (optional, off by default).** When enabled, the current track's metadata is sent to
  [lrclib.net](https://lrclib.net) to look up synced lyrics.
- **Weather widget (experimental).** Only runs if you enter coordinates in the widget settings. Those
  coordinates are sent to Apple's WeatherKit service.

## Experimental features

These are off by default and described as experimental in the app:

- **Lock-screen player.** An overlay shown while the Mac is locked. It does not replace the macOS lock screen
  or ask for credentials. Its behaviour on the real locked screen is still being validated on hardware.
- **Phone-call integration.** A user-triggered Accessibility diagnostic. It does not monitor calls in the
  background, does not save caller details and cannot answer or decline calls.
- **Brightness feedback.** Observes brightness-key changes. It does not replace the macOS brightness indicator.

## Data stored locally

Preferences, Shelf bookmarks, and optional Spotify credentials (in the Keychain). Nothing is stored remotely by
the app.
