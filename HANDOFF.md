# Candidate 0.7.2 (19) — recovery work in progress

Branch: `fix/playback-recovery-20261103`, baseline `b9a17b0` / 0.7.1 (18).

Implemented for validation: queued bounded recovery across reconnects, failed-producer health, clock-based stall detection, restoration of the previous stream after candidate preparation fails, a shared background audio coordinator with interruption/route/reset handling, structured request/output/subtitle errors and battery/thermal snapshots. Regression cases cover disconnected recovery and a stationary receiver clock.

Build/CI and native integration results must be appended after they actually run. No physical iPhone/Chromecast acceptance or battery improvement is claimed. The codec/cause of the user's vlc_3 overlay failure remains unknown; new diagnostics preserve more detail. Keep CB-005/010/011/014 open until their evidence and acceptance are complete.

---

# Stato corrente e registro condiviso — 2026-11-03

Prima di riprendere il progetto, leggere [AGENTS.md](AGENTS.md) e il
[registro canonico dei problemi, issue #1](https://github.com/DonPick98/stremio-cast-bridge-ios/issues/1).
Il registro contiene 14 voci iniziali con evidenze, priorità, criteri di accettazione
e istruzioni per aggiornarle durante ogni sessione. Il numero delle voci può crescere:
consultare sempre la issue corrente.

Baseline analizzata: **0.7.1 (18)** sul branch **native/embedded-media-engine**,
commit **1e1965632597594ab6a6574f70732ba3e9d15560**. Il branch main è ancora
basato sulla **0.7.0 (17)**. Verificare versione e HEAD attuali prima di lavorare.

L'utente segnala interruzioni durante il normale uso di altre app, sottotitoli
integrati non funzionanti, errore con esterni della fonte e scomparsa dei controlli.
Il log del 2026-11-03 mostra una perdita della sessione con uscita FFmpeg -32,
recupero ritardato e quattro preparazioni overlay fallite per vlc_3. OpenSubtitles
funziona. La causa iniziale dell'interruzione e il codec di vlc_3 restano da accertare.

Questa attività ha salvato diagnosi e istruzioni di continuità: **non ha applicato
correzioni funzionali né eseguito un nuovo collaudo fisico**. Aggiornare gli stati
nella issue quando viene implementata o verificata una correzione.

---

## Checkpoint storici

Le sezioni seguenti sono conservate come storia delle verifiche dichiarate nei
checkpoint precedenti. Non certificano automaticamente la baseline 0.7.1 o build successive.

# Technical checkpoint: Cast Bridge 0.7.0 (17) - FREE receiver

## Current user decision

Use Google's Default Media Receiver (CC1AD845). The delivered app requires no
Google Cast developer registration, payment, new receiver hosting or Sites change.
The optional Receiver/ experiment is inactive with the default build configuration;
do not make its registration or publication a prerequisite for this release.

## Validated source and artifact

Application source: 3347dd93738202e7de6b163dc5684ff130010582.
Production build: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41359477925
Native integration: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41359477933
Unsigned IPA SHA256: bc98bd6521ae53c5baccd7d14297b9a8db32e7527937caecd373f0ebdb151f69.
The actual IPA plist was checked: 0.7.0, build17, receiverCC1AD845, matching Bonjour,
background audio mode, icon, ffmpegkit framework and activity extension.

## Free subtitle route

Embedded text tracks are selected using FFprobe's actual stream index with codec/
language validation, then exported by the pinned FFmpeg library to complete WebVTT.
Extraction is cancellable, has a 120-second deadline and a 1 MiB output limit, and
uses the existing remote-playback audio mechanism while preparing in background.
Six complete documents can be cached for the current source; changing source
invalidates workers and cache. Never pass a bounded 90-second window to the
standard receiver as though it were a complete movie subtitle.

The movie can start/continue while text is prepared. Pending/failed text does not
trigger a subtitle burn or stop video. An extraction failure stays a subtitle
error with retry/alternative subtitle choices. Actual bitmap tracks retain the
compatibility overlay path and its recovery.

Attaching a new, unregistered text track can require one video LOAD at the retained
position. Previously registered off/on and fine delay variants use active track IDs.
Arbitrary-language changes with zero reload are not guaranteed by the free route.
ASS/SSA becomes standard text; original ASS styling is hidden in the free UI.
Appearance and synchronization preferences remain persistent. Source-provided
subtitles and the existing Stremio/OpenSubtitles catalogue remain available.

Non-overlay conversions prefer FFmpeg/VideoToolbox to retain timestamps and frame
cadence; compatible video still uses packet copy. AV1 uses VLC because the pinned
FFmpeg build did not deliver valid decoded AV1 video on the tested platform.
Do not treat a successful process exit or metadata alone as valid video.

## Completed checks and acceptance gap

Both workflows succeeded. The native report passed 33 codec cases, five gateway
scenarios, 38 independently decoded A/V outputs, four timed caption-pixel checks
and ten strict video-quality/audio/seek checks. VP8 and AV1 each delivered 144/144
expected frames. Six ASS/WebVTT windows, two complete-document exports including a
late cue beyond 90 seconds, attached font bytes, cancellation and caption gateway
checks passed. The offscreen transfer/pause/resume/cleanup probe passed (65.08s).
Receiver experiment also has 14 Node tests and real browser rendering evidence,
but it is not part of the selected free activation path.

The new IPA has not yet been validated on the user's physical iPhone/Chromecast or
with that phone locked. The earlier physical standard-receiver tests do not prove
the new sender UI or private sources. Do not interrupt a movie for synthetic tests.
Use the local >_ diagnostics after actual failures; never commit personal source
manifests, Real-Debrid URLs/tokens, certificates or profiles.

---
## Historical 0.6.4 checkpoint (superseded where it conflicts with the above)

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

