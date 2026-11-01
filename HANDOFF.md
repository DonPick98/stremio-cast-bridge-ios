# Technical checkpoint: Cast Bridge 0.6.4 (14)

## Source and validation

Validated media-engine and controller source: d56b76bd27932bdb210fcefb7a2dd83ddc793c8f.
Native integration: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41346105625
Candidate production compile and regression tests: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41346105595

VLC 3's avformat demux exposed FFmpeg SUBRIP as undf after a seek. The overlay route now uses native Matroska demux for repaired inputs carrying subtitles. VLC 3 also refuses native Matroska on unseekable input. RewindableInputStream therefore adapts only the private loopback producer with an 8 MiB buffer and 2 MiB history through VLCKit's supported InputStream callback API. The callback advertises seeking with FASTSEEK=false, so the parser can revisit clusters without scanning to the movie end. Full buffers suspend the input task; trimming resumes it, and stop wakes blocked readers/writers. Both workflows test rewind, forward seek, byte continuity, EOF and blocked read/write cancellation before building. Other playback routes retain their prior demux. Initial default text selection now runs the same indexed extraction preflight as a manual selection; status callbacks cannot preempt it with an overlay. In-file captions in the selected language take priority over external source captions.

The native suite covers 31 actual-gateway codec cases, five gateway scenarios and ten strict video-quality/audio/seek cases, with 36 decoded baseline outputs. Two cases select the second subtitle and 440 Hz alternate audio, start at 3.25 seconds and require visible SRT/ASS captions only at the correct output time (checks at 1/4/7 seconds). This replaces reliance on the old seek fixture whose only cue had already elapsed. Caption integration retains 21 timing variants and the offscreen transfer probe retains delivery pause/resume and worker shutdown checks.

Automatic overlay recovery retains the user's language preference and exposes a persistent warning on the main screen. Only explicit UI subtitle choices write preferences; programmatic representation changes and recovery do not trigger the picker callback. The controller toggles already registered text captions through EDIT_TRACKS_INFO, without pausing/replacing the producer, changing the timeline or issuing LOAD. Re-selecting the cached embedded text reuses that representation. A different, unregistered text caption still requires LOAD; arbitrary-language switching without reload remains open.

The prior guarded physical Chromecast test verified one video with 21 text tracks and three delay switches without replacing the media session. It did not validate this version's iPhone UI or exact private subtitles. The latest read-only Wi-Fi check observed the user's video advancing; it was not interrupted to run synthetic tests.

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
