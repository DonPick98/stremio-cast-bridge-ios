# Technical checkpoint: Cast Bridge 0.6.2 (12)

## Current application

Validated media-engine source: 7edf7fa7b6ba925b2c813e931093b2a81e2ffc07. The main release additionally includes a display-only guard for unknown resolution.
Production build: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41327486735
Native validation: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41327486801

The terminal icon beside Settings copies local playback diagnostics for the preceding ten minutes, bounded to 600 events. The cache survives an app restart and prunes expired entries. Numeric errors, source/stream revisions, codec/dimensions/cadence, selected track keys, preparation attempts, producer exit, receiver state, requested positions and receiver-reported positions help distinguish source, conversion and Cast failures. Real-Debrid HTTP status and API code are recorded without response bodies. The clipboard item is local-only and expires after one hour. Nothing is sent automatically. URLs, credentials, titles, caption text and raw third-party error descriptions must never be logged.

Legacy MPEG-4 ASP, MPEG-2 and WMV2 can use FFmpeg software decoding and H.264 VideoToolbox encoding directly into the bounded output socket. VLC H.264 and VP8 remain fallback attempts. Burned subtitles use VLC; software decoding is explicitly selected for legacy MPEG-4 input. SD input is not upscaled and fractional cadence is retained. A new source or failed preparation clears the previous stream's quality description.

The existing revision-based source/stream state, queued latest seek, retained play/pause intention and canonical film/episode resume key are unchanged. Compatible H.264 remains packet-copied through FFmpeg, avoiding VLC packetizer B-frame loss. The system media card remains the only Lock Screen playback surface; old ActivityKit cards are closed when opening the app.

## Validation

The codec matrix captures the actual EmbeddedMediaEngine gateway for all 28 cases and waits for natural EOF. Five gateway scenarios and ten strict dimensions/cadence/audio/seek audits add up to 43 media outputs. A MPEG-4 ASP fixture at 720x480 and 30000/1001 fps includes B frames, quarter-pixel motion, two audio tracks and SRT. Tests cover normal playback, burned subtitles and non-keyframe seek with alternate audio. Original H.264 1080p frame hashes are checked for identity.

The 65-second offscreen transfer probe checks delivered-byte pause/resume, a rapid pause/play pair, the audio helper and actual worker cancellation. Pause measurement waits for in-flight network operations to drain, then requires a stable delivered-byte count and subsequent resumed delivery.

Diagnostic tests cover URL exclusion, deduplication, history bounds, expiry and restoration. Production packaging is checked for matching app/extension version, arm64, icon assets, required frameworks and absence of validation markers.

Three MPEG-4 outputs from the iOS engine were additionally played on a physical classic Chromecast using a guarded PC relay. Normal video, subtitle overlay and alternate-audio seek output all reached progressing PLAYING state. The receiver was restored to its idle screen. These checks are distinct from iPhone UI and locked-screen acceptance.

## Delivery and remaining acceptance

The release artifact must have matching app/extension version 0.6.2 (12). Regenerate its SHA256 for each build; the user-facing release notes contain the delivered file's hash.

The exact privately sourced file reported by the user has not been acquired or tested. Synthetic success does not prove that file is readable or that every device can convert every stream in real time. Use the new copied diagnostic report if the same source still fails. Installation, the copy-button flow and full locked-phone playback remain physical iPhone acceptance checks. Keep the phone powered on and on the receiver network during local conversion; force-quitting stops the local producer.

No credentials or personal media URLs belong in source control, diagnostics or handoffs. See THIRD_PARTY_NOTICES.md for pinned upstream libraries and relinking instructions.
