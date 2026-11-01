# Technical checkpoint: Cast Bridge 0.6.3 (13)

## Source and validation

Validated media-engine source: f7eae139a3f06266f9597a6266ca08967ac486e3.
Native integration: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41338472674
Initial production compile and regression tests: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41338472694

The main release adds controller request-order guards, preservation of delay during text extraction, a text-only fallback selection guard, explicit timing names and numeric raw receiver position in diagnostics. These changes leave the validated media engine and timestamp transformation unchanged; the main production workflow compiles and runs the resolver, subtitle catalogue, timing, resume, indexed-extraction and privacy-related parser checks.

The native suite passes 29 actual-gateway codec cases, five gateway scenarios and ten strict video-quality/audio/seek cases, with 34 decoded baseline outputs. A new burned-text case starts at a non-keyframe seek position. Caption integration verifies 21 timing variants, actual HTTP cue timestamps after a seek, half-second delay changes and retained video EOF. The offscreen transfer probe also checks real delivery pause/resume and worker shutdown.

A guarded physical classic Chromecast test loads one video with 21 text tracks, switches +0.5/-0.5/zero using EDIT_TRACKS_INFO, confirms active track IDs and advancing playback without replacing the media session or reloading video, then restores the idle screen. The receiver prefetches all caption variants, so total memory and download size are bounded by the text limit and the 21-track window.

## OpenSubtitles and Stremio

SubtitleCatalog uses the same official opensubtitles-v3.strem.io add-on as Stremio, through the documented subtitles resource. It includes the exact content ID and optional filename, byte size and OpenSubtitles hash. The hash uses two validated 64 KiB ranges; it never downloads the movie merely to identify subtitles. Results retain language, subtitle filename, release and optional FPS. Exact episode names are ranked above conflicting episode/pilot names. FPS similarity is a hint, never an automatic speed conversion.

Source-provided external tracks appear alongside online results. The app retains embedded-track discovery. It can unwrap a Stremio localhost subtitle-conversion URL only to its HTTPS upstream and performs its own bounded text conversion. It cannot read a subtitle selection already made in a separate Stremio player unless the source/handoff supplies that information.

SubtitleDocument handles SRT, ASS text and WebVTT with size limits and encoding checks. WebVTTTimeline applies delay and the original-media seek offset exactly once, clips elapsed cues and shifts inline timestamps. External caption text is served only to the selected receiver by the existing private gateway.

## Timing and state

The UI offers half-second steps, five-second steps, reset and a coarse slider up to +/-300 seconds. The delay is saved per film/episode, source and caption. SubtitleWindow provides 21 immutable half-second track variants within +/-5 seconds of its center, allowing fine changes through active track IDs. Coarse changes outside that window coalesce before rebuilding the stream at the retained position. Burned overlays use VLC's subtitle delay API.

Requests arriving during subtitle acknowledgements retain queued seeks. Latest choices and timing are applied after acknowledgements; stale downloads and source generations cannot publish into later selections. Failed subtitle changes do not overwrite the last functioning source while downloading an alternative.

Supported indexed MKV text tracks are extracted by the exact selected subtitle ordinal with a 12-second preparation deadline. Unsupported compression, missing indexes, graphical subtitles and incomplete cue metadata can require the overlay fallback. Indexed extraction is best effort and is not a guarantee of complete captions for arbitrary MKV files.

Out-of-range or completed saved positions restart instead of clamping playback to the final second. Unscoped old per-file resume keys are not migrated into a new content identity. Actual raw receiver time must advance before an autoplay LOAD is considered started; paused loads do not require movement. Persistent overlay buffering triggers explicit recovery without the failed subtitle. Other persistent local buffering has a bounded retry and a visible error rather than endless automatic reloads.

## Diagnostics and acceptance

The local ten-minute diagnostic report still excludes credentials, URLs, titles and subtitle content. New events include track codecs, catalogue/download stages and the requested delay. Numeric raw receiver position is recorded separately from the estimated position.

Physical iPhone UI, long locked-screen playback and synchronization of privately sourced content remain user acceptance checks. The protocol test does not certify the exact private video or subtitle release. Keep the phone powered and on the receiver network for local serving/conversion. See THIRD_PARTY_NOTICES.md for pinned LGPL media dependencies and relinking information.
