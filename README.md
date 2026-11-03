# Cast Bridge iOS 0.7.2 (20) — diagnostic context candidate

Candidate on `fix/playback-recovery-20261103`, based on 0.7.1 (18). See [issue #1](https://github.com/DonPick98/stremio-cast-bridge-ios/issues/1) and [HANDOFF.md](HANDOFF.md) for verification status. Physical background/subtitle/battery acceptance is pending. The candidate includes a direct FFmpeg PGS overlay path. Native CI passed the synthetic startup/seek bitmap checks; the user’s physical source still needs validation.

iOS sender for Stremio video sources and Google Cast receivers. The app reads media tracks with MobileVLCKit and chooses direct playback, remuxing or local conversion automatically.

Compatible H.264 video packets are copied by the pinned LGPL FFmpegKit backend, preserving the original picture and cadence while selecting or converting audio. Incompatible audio becomes AAC stereo. Video conversion uses H.264 VideoToolbox with VP8/Vorbis fallback, within receiver limits such as 1080p/30 or 720p/60. Unsupported audio and nonzero seeks can be normalized before video conversion through a private Matroska loopback stream.

FFmpeg remux and VLC conversion output travel through a bounded anonymous socket into the local HTTP gateway. The same upstream connection is retained from initialization through playback, and natural end of stream waits for the muxer to close its output descriptor. Copy-mode pause applies backpressure without closing the connection.

Legacy MPEG-4 ASP, MPEG-2 and WMV2 sources can use software decoding plus H.264 VideoToolbox encoding through FFmpeg, retaining SD dimensions and fractional frame rate. VLC H.264 and VP8 remain bounded fallback attempts. PGS bitmap subtitles first use direct FFmpeg overlay plus H.264; other compatibility overlay paths use VLC.

The Codex terminal button beside Settings copies the last two minutes of local playback diagnostics. A bounded cache records safe event codes, track choices, media format, timeline requests, receiver state and numeric errors. Credentials, personal URLs, titles, subtitles and raw server/error text are excluded. The report is copied locally and never sent automatically.

The interface includes source sizes, automatic playback after source selection, remembered audio/subtitle languages and persistent subtitle appearance settings. The iOS system media card is the single playback surface on the Lock Screen and in Control Center, with a draggable timeline and 30-second controls through MPNowPlayingInfoCenter and MPRemoteCommandCenter. Version 0.6.1 closes legacy ActivityKit cards when opened.

Compatible video is copied without re-encoding. Local video conversion preserves the source cadence unless it exceeds the receiver limit; fractional rates are not forced to 30 fps. The player displays the source resolution and frame rate and whether video is original or converted. Seek and track replacements retain the requested original-media position until the new receiver status confirms it. Cancelled source preparations cannot publish into later selections.

When local conversion is active, the phone must remain powered on and connected to the receiver's network. Force-quitting interrupts conversion. Background support uses an audio playback session restricted to active casting. Controls reconnect without reloading owned media; a pinned direct Cast connection provides a fallback for media commands. Simulator results do not certify physical-device screen-lock behavior.

Separate subtitle text is served as WebVTT through the selected-device-only gateway and retimed after seeks. Bitmap subtitles require video overlay. ASS/SSA exported as standard text does not retain its original styling on the free default receiver.

## Subtitles

The in-app browser uses the [official Stremio OpenSubtitles v3 add-on](https://github.com/Stremio/stremio-official-addons/blob/master/index.json). It lists releases and languages, alongside subtitle URLs supplied by the selected Stremio source. Requests include the content identity, filename and file size when available; a bounded pair of 64 KiB range reads can add the OpenSubtitles file hash. No separate API key is required by this integration. This does not read the active selection or installed add-ons from another Stremio application.

HTTPS subtitle downloads accept bounded UTF-8, UTF-16 and legacy text encodings, normalize SRT/ASS to WebVTT and remain local. Fine timing changes use immutable half-second WebVTT track variants without reloading video. Larger adjustments rebuild at the preserved point. Delay is stored per content, source and subtitle; appearance preferences remain global.

Embedded tracks in the remembered subtitle language take priority over source-provided external captions; an explicit user choice to disable subtitles is still respected. Selecting a supported indexed MKV text track first attempts separate extraction of the exact subtitle ordinal, avoiding video conversion solely for text overlays. Extraction remains bounded and best effort; unsupported or unindexed tracks use the existing overlay path. A selected-device-only gateway serves the output. The repaired subtitle overlay route uses an 8 MiB loopback input buffer with 2 MiB of rewind history, allowing VLC's Matroska parser to inspect clusters without treating a chunked HTTP connection as seekable or downloading the entire video. Full buffers suspend the input task; cancellation wakes blocked readers and writers.

Initial automatic track selections use the same extraction preflight as manual selections. Repaired overlay input uses VLC's native Matroska demux: the pinned VLC 3 avformat bridge does not map FFmpeg SUBRIP/ASS codecs. A stalled overlay is stopped and playback resumes without that failed track, with a persistent warning on the main screen. Automatic recovery does not save an off preference. Startup is only confirmed after actual receiver media time advances, so a transient PLAYING acknowledgement does not cancel recovery.

Toggling an already registered separate text track uses EDIT_TRACKS_INFO without replacing the media URL, pausing the producer or issuing another LOAD. Re-selecting the currently cached embedded caption reuses it. A different caption not registered with the receiver still requires a media reload; arbitrary-language switching without reload is not implemented. Bitmap overlays still require rebuilding the video pipeline.

## Build

Use CastRemote.xcworkspace, scheme CastRemote, Release and iphoneos. CocoaPods pins all media dependencies. GitHub Actions produces an unsigned IPA with the app icon, Live Activity extension and license texts. Install with a compatible signing tool such as SideStore.

Production builds must leave CAST_ENGINE_VALIDATION empty. CAST_ENGINE_TESTING enables the synthetic simulator validation only.

The separate validation workflow covers 35 synthetic codec combinations through the actual playback gateway, five gateway cases, ten resolution/cadence/seek cases and over 60 seconds of continuous offscreen network transfer with pause/resume and cancellation. Six subtitle cases check SRT/ASS/PGS startup and post-seek output, selecting the second subtitle track and alternate audio and checking actual caption pixels at absent/present/absent times on a black picture; successful video decoding alone is insufficient. The copied 1080p test compares every decoded frame with its source. Compatibility depends on file integrity, source availability and hardware capacity; DRM is outside the supported path.

See [HANDOFF.md](HANDOFF.md) for technical validation status, [BUILD-WINDOWS.md](BUILD-WINDOWS.md) for build steps and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses and upstream sources.

