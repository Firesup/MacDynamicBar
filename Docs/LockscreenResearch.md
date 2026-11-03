# Real lockscreen presence: corrected feasibility finding

The earlier conclusion that Minnow could not add content to the real lockscreen was too broad. Lack of a WidgetKit lockscreen extension is not the same as inability to show a window there.

## Verified source findings

- Canopy 2 advertises music and lyrics on the lock screen: https://getcanopy.pro/
- Notchy advertises widgets and Now Playing on the macOS lock screen: https://notchy.dev/
- Atoll implements lockscreen widgets and identifies Alcove as an inspiration: https://github.com/Ebullioscopic/Atoll
- Perch publishes a concrete probe and its outcome: https://github.com/bhaweshverma50/perch/blob/main/docs/notes/lockscreen-spike.md

Perch's author reports an actual macOS 26 lockscreen probe: a borderless NSPanel with `canBecomeVisibleWithoutLogin = true` at `CGShieldingWindowLevel()` was visible. A screen-saver-level panel and a status-level panel were not. Its source uses lock/unlock distributed notifications to elevate and restore the window. This is primary implementation evidence, not proof that Canopy uses exactly the same code. No third-party implementation was copied into Minnow.

Crucially, that probe explicitly did NOT test interactive transport controls. Its success establishes display feasibility, not a completed interactive player. We have not run this probe on the user's Mac. No lock operation or high-level overlay was activated during this change.

## Next implementation gate

1. Dedicated opt-in lockscreen panel, separate from the desktop Music Scene and ordinary island windows.
2. Elevate only while the session is locked. Restore/hide on unlock, app termination, session switch and sleep. Add an independent bounded watchdog so a missed unlock event cannot strand a shielding-level panel over the desktop.
3. First test a small click-through media panel positioned clear of authentication controls. Leave macOS authentication intact. Do not collect passwords or imitate Touch ID.
4. Verify artwork updates and playback metadata while locked; current desktop AppleScript integrations may have different availability then.
5. Separately verify actual pointer and keyboard routing for playback and artwork expansion. Only then reuse the reference's larger artwork/lyrics layouts. The existing unlocked preview is not evidence of locked-screen interactivity.
6. Validate macOS versions, multiple displays, sleep/wake, fast user switching, and crash cleanup before enabling by default.

## System HUDs

This change adds event-driven volume observation through Core Audio, without swallowing media keys or suppressing Apple's own HUD. Fixed-volume outputs may expose no scalar and produce no island HUD. Brightness is not implemented yet: Hammerspoon's source demonstrates runtime DisplayServices/CoreDisplay access and legacy IOKit fallback, which needs an isolated compatibility adapter and hardware testing:
https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/screen/libscreen.m

These findings supersede the secure-lockscreen feasibility restriction in the earlier NativeSurfacePlan. Authentication replacement remains outside scope; media/widgets drawn alongside the real lockscreen are the intended goal.
