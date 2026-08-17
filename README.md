# Coupé

Coupé is a native iPhone/iPad media-cutting companion: import existing audio or video, play it, hold to mark the portion worth keeping, optionally slide to lock the selection, then annotate, play, export, and share the resulting independent clip.

## V1 features

- Persistent SwiftData library with video thumbnails, media metadata, clip counts, and safe confirmed deletion.
- Video import from the system Photos picker and audio/video import from Files/document providers.
- App-owned storage under `Application Support/Coupe/Projects/<UUID>`; the database stores only relative paths.
- AVPlayer video/audio playback, seeking, long-duration time formatting, and a geometry-derived hold/slide-lock selector.
- Explicit idle, pressing, locked, finalizing, and failed selection states; locked stop and accessible locked-selection alternative.
- Independent source-range export with passthrough preference and highest-quality fallback, visible lifecycle, error preservation, and retry.
- Chronological clip list, persistent rename/annotation, exported-file playback, native sharing, and source-safe clip deletion.

## Architecture and project structure

The SwiftUI feature views live in `Coupe/Features/{Library,Editor,Clips}`. Reusable presentation is in `Components`; SwiftData entities and persisted raw-value enums are in `Models`; deterministic selection/time logic is in `Utilities`; and security-scoped/coordinated file handling, import, thumbnails, playback observation, and export are isolated in `Services`. `CoupeApp` owns the persistent model container. No third-party packages, network calls, recording permissions, analytics, or remote storage are used.

```text
Coupe/App entry       Coupe/CoupeApp.swift
Coupe/Models          SwiftData project and clip entities
Coupe/Services        managed storage, import, AV playback/export, thumbnails
Coupe/Features        Library, Editor, Clips
Coupe/Components      artwork and native share sheet
Coupe/Utilities       selection state machine and time formatting
CoupeTests            deterministic unit tests
```

## Requirements and supported media

- Xcode 26.3 or a compatible later Xcode, Swift 5, and the iOS 26.2 SDK/deployment target already configured by the original project.
- Photos supplies video. Files accepts system-recognized audio and movie types (commonly M4A, MP3, WAV, AIFF, MOV, and MP4); actual decoding/export support depends on the source codec and device AVFoundation support.
- A physical iPhone is strongly recommended for validating haptics, Photos/Files providers, one-handed gestures, playback, and sharing.

## Build and run

1. On macOS, clone the repository and open `Coupe.xcodeproj` in Xcode.
2. Select the **Coupe** scheme and an iOS 26.2-or-later simulator or connected device.
3. In **Signing & Capabilities**, retain automatic signing and select a team permitted to sign `com.hassanemeite.Coupe` (the checked-in team is intentionally preserved).
4. Choose **Product → Build** (`⌘B`), then **Product → Test** (`⌘U`).
5. Run (`⌘R`). The customer-facing home-screen and navigation name is “Coupé”; target, module, product, paths, and bundle ID remain ASCII `Coupe`.

## Physical-device checklist

- Confirm Photos video and Files audio imports copy successfully and remain available after relaunch.
- Confirm play, pause, seek, held selection, slide-to-lock, lift-after-lock, locked stop, and end-of-media finalization.
- Confirm light/strong haptics, small off-axis finger movement, VoiceOver labels, Dynamic Type, dark/light mode, and the accessible locked-selection button.
- Confirm ready audio/video clips play only their range, share through the native sheet, and retain title/annotation after force quit.
- Confirm deleting a clip preserves its source, while confirmed project deletion removes its full managed directory.

## Manual acceptance plan

1. Import a short video from Photos.
2. Import an audio file from Files.
3. Play each source.
4. Hold the central button for several seconds and release.
5. Confirm one clip is created with correct approximate boundaries.
6. Start another selection, drag to the lock, and release the finger.
7. Confirm selection continues after release.
8. Tap stop and confirm the locked selection ends.
9. Annotate and rename both clips.
10. Terminate and reopen the app; confirm projects, clips, and annotations remain.
11. Play each exported clip and verify it contains only the selected time range.
12. Share a ready audio clip and video clip.
13. Delete one clip and confirm the source remains.
14. Delete a project and confirm its managed files are removed.
15. Test playback reaching the end during a held selection.
16. Test a selection shorter than the minimum duration.
17. Test import/export failure messaging where possible.
18. Test the complete interaction on a physical iPhone, not only the simulator.

## Known V1 limitations

- There is no waveform editor, frame-accurate trimming UI, recording, cloud sync, authentication, transcription, filters, upload, or sharing extension.
- AVFoundation passthrough can align a cut to codec sample/keyframe boundaries. The stored source-relative range remains authoritative, but an exported boundary can differ slightly for some codecs.
- If passthrough is unavailable, Coupé requests AVFoundation's highest-quality compatible export. A device/source codec combination that supports neither remains a failed clip with its metadata intact and a retry action.
- AVAssetExportSession does not expose consistently useful progress through every modern async export path; V1 reports pending/exporting/ready/failed rather than an unreliable percentage.
- PhotosPicker transfer temporarily materializes the user-selected data solely while it is copied into Application Support; the temporary file is removed immediately afterward.
