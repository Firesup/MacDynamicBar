# Lockscreen and waveform follow-up — November 3, 2026

## Online findings

- [Canopy 2](https://getcanopy.pro/) advertises music and lyrics before sign-in. Its public site does not reveal its window or audio implementation.
- [Notchy's Lock Screen settings](https://notchy.dev/help/settings/#lock-screen) describe a lockscreen pill, Now Playing widgets, movable placement clear of login controls, and separate unlocked layout previews. These feature descriptions do not establish how its private implementation works.
- [Atoll's lockscreen manager](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/managers/LockScreenManager.swift) separates lock events from unlock/session-active events. Its [panel manager](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/managers/LockScreenPanelManager.swift) uses a shielding-level window. Its [audio adapter](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/audio/AudioTap.swift) uses a Core Audio process tap and private aggregate device rather than depending on visible app windows.
- [Perch's actual lockscreen probe](https://github.com/bhaweshverma50/perch/blob/main/docs/notes/lockscreen-spike.md) reports that a shielding-level NSPanel with `canBecomeVisibleWithoutLogin` appeared on macOS 26; lower levels did not. That probe explicitly did not verify transport-button interactivity.
- [Apple's Core Audio tap documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and the installed SDK headers specify the native tap, process/bundle selectors, audio-capture usage description, private aggregate device and IO callback APIs used here. A tap can be unmuted so measuring audio does not silence or reroute music.
- [Spotify notification probe](https://gist.github.com/loretoparisi/6092634d34e97a062029b078215b6bdc) documents state, identity and playback-position fields. [Scrobblr's implementation notes](https://github.com/asharahmed/scrobblr/blob/main/DEVELOPMENT.md) describe Music's broadcast metadata and the limits of scripting/private MediaRemote access. Notification schemas are compatibility-sensitive; partial values need validation.

These sources were inspected for API/lifecycle behavior. No third-party implementation was copied into Minnow; its adapter and state reducer are independent implementations.

## Minnow problems identified

1. `setSessionActive(false)` called `lockScreen.suspend()`, which erased lock state and destroyed the overlay. A session-resign notification around locking could undo a preceding lock notification.
2. Ordinary desktop-window visibility alone suspended waveform capture, even when a separate lockscreen player needed it.
3. ScreenCaptureKit setup required finding the player in a display's shareable application list. That is the wrong dependency for lockscreen audio: the music process may still play when its windows are not available for capture.
4. A missing compatibility-sensitive session dictionary key was treated as an explicit unlock by the watchdog.
5. Playback broadcast handlers always ran AppleScript; scripting failure could turn a playing source into a paused/unavailable source during locking.

## Changes

- Dedicated lock lifecycle separates lock, sleep, return-to-session and console ownership. Missing session values preserve known state; waking without positive lock evidence never elevates an overlay. Canonical unlock or explicit unlock/session-active removes it. Session resignation gets a short settling check instead of unconditionally suspending the lockscreen.
- The existing shielding panels remain separate from normal island windows and reassert ordering while locked. A Settings status line and local unified-log events expose lifecycle/panel state without logging song titles or credentials.
- The shared capture session remains active when a real lockscreen player is presented, even if desktop surfaces are hidden. Sleep/fast user switching still suspends presentation.
- macOS 14.2+ uses per-player Core Audio process taps, private tap-only aggregate devices and float PCM analysis. macOS 26+ selects/restores the source by bundle ID. Older tap-capable systems translate the player PID to an audio process object. Samples remain local and ephemeral; only measured levels reach the UI. No microphone, global audio mix, file recording or system output change is added.
- macOS 14.0–14.1 retains ScreenCaptureKit as a compatibility fallback; locked audio on those versions is not promised.
- While locked, Music/Spotify broadcast notices update confirmed state/metadata without scripting. Unknown durations remain unknown, previous artwork is cleared on a new track, and partial notices do not borrow the old track ID. Full metadata/artwork is refreshed after unlock. Transport/seek while actually locked still requires hardware verification.

## Verification

Automated checks cover lifecycle ordering, missing lock evidence, sleep/wake, user switching, explicit/canonical unlock, notice parsing and existing geometry/interaction behavior. Native hardware results will be recorded here after the new build is exercised. An unlocked Music Scene is not verification of actual lockscreen visibility or input routing.
