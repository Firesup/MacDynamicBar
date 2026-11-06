# Shelf — second delivery milestone

Implemented after the Calendar/Reminders completion check-in, following the user's request to continue onward. This is independent native Apple-API code; no Boring Notch GPL source was copied or translated.

## Behavior and ownership

- One ShelfStore is owned by IslandCoordinator and shared by island windows and Settings. Settings → Shelf defaults off. The Music/Today switch gains Shelf only when enabled; there is no layout editor.
- Files and folders are added through NSOpenPanel or file-URL item providers. HTTP URLs and unreadable sources are rejected; resolved duplicate paths are coalesced. The shelf is bounded to 30 references.
- ShelfJSONPersistence atomically saves versioned bookmark records to `~/Library/Application Support/Minnow/Shelf.json`. It does not store file copies. Corrupt manifests are left unchanged and shown as an error, rather than overwritten during an add.
- NativeShelfFileAccess creates read-only security-scoped bookmarks and resolves them without permission UI. Stale bookmarks are renewed. Missing/inaccessible entries remain visible and removable. Scoped leases are balanced; disabling Shelf releases ordinary access and cancels thumbnail work.
- QuickLookThumbnailing provides thumbnails; an icon remains visible if a thumbnail is unavailable. Callback generations prevent removed/disabled entries from reappearing. File URL drag providers hold an independent access lease for their lifetime.
- Open and Show in Finder are direct user actions. AirDrop uses NSSharingService.sendViaAirDrop after a direct share-button press, checks capability, and retains independent file access until success/failure/cancellation. No recipient is selected and nothing is sent automatically.
- Removing a reference never deletes/moves its source file. Save failures leave the previous shelf intact. Disabling Shelf leaves saved references intact.

## Presentation and lifecycle

A file drag entering the island temporarily opens Shelf. A canceled/exited drag restores the previous page and presentation; an accepted drop keeps Shelf open. Dragging/importing/native sharing defer queued popups. Existing priority/dismissal behavior is retained. Shelf is accessible with Media disabled or hidden after pause, and is never added to lock-screen panels.

App activation and wake refresh file availability without a polling loop. In-flight imports are rejected after a disable/re-enable transition. Thumbnails are memory-only and bounded by the entry limit. Individual file access failures are displayed without inventing available files or successful shares.

## Verification and manual gates

Automated tests cover bookmark persistence/restoration, duplicates, source-file preservation, stale renewal, missing files, capacity, non-file URLs, load/save failures, file-URL provider import/export, stale imports, opt-in persistence, drop cancellation/popup deferral and native-hosted rendering. A native security-scoped bookmark round trip uses a disposable test file. No user files are shared by tests.

Native-hosted minimum-width render: `.build/ui-checks/shelf.png`. This tests rows and controls with synthetic references. It does not prove Quick Look provider output, real Finder dragging, sandbox extensions handed to another application, AirDrop visibility/recipient selection/transmission, or real island pointer routing. Those remain manual checks on the built app. No live AirDrop transfer was performed.

Manual sequence: enable Shelf; add a disposable local image/PDF/folder; inspect real thumbnails; drag into the physical notch and back to Finder/another app; cancel a drag and verify page restoration; restart; rename/move/remove a source; remove a Shelf reference and verify the source remains. Open AirDrop with a disposable file only when desired, and validate actual transfer with a chosen recipient. Test unavailable AirDrop, canceled sharing, multiple displays, sleep/wake and disabling during a drop. Calendar, Music, popup priority and lock-screen privacy remain separate regression gates.
