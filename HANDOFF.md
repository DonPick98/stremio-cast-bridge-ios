# Technical checkpoint: Cast Bridge 0.6.1 (11)

## Playback and state

Google Cast SDK controls the receiver. MobileVLCKit reads metadata and performs required video/subtitle conversion. FFmpegKit copies compatible original video into fragmented MP4 and selects or converts audio. Both use the bounded anonymous output socket and selected-device-only HTTP gateway. Nonzero seeks discard negative preroll before rebasing; external WebVTT follows the original-media offset. Compatible video is not passed through VLC's H.264 packetizer.

Every source and stream preparation has a revision. Cancelled work and late errors cannot update a later choice. The canonical resume key belongs to the film/episode, independently of source, quality and add-on. The old engine's offset is captured before replacement. Requested positions remain visible until the receiver confirms them. Repeated seeks coalesce to the latest target, including requests received during preparation. The latest play/pause intention survives late status callbacks. Subtitle-driven conversion is reconsidered when the selected tracks change.

The system media card is the only Lock Screen playback surface. Opening this version ends legacy ActivityKit cards. The extension is retained for upgrade compatibility, but no new ActivityKit activity is requested.

## Verified candidate

Application source: 8f101dd365e38de132b5839dbeaf44dba4822a53.
Production build and regression tests: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41316645170
Native validation: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41316645209

All 30 baseline decoded outputs and eight quality/seek cases passed. The 1080p 23.976 test retained all 96 decoded frames with identical hashes. Converted cadence was checked at 23.976, 25, 29.97 and 720p/60. Both selected audio tones and non-keyframe seek timing were checked. The copy path uses FFmpeg directly to avoid packetizer B-frame losses.

The offscreen simulator probe transferred 7,406,817 bytes over 65.092 seconds, including 1,966,080 bytes after 50 seconds. Delivery pause/resume, a rapid pause/play pair, the audio helper and actual worker cancellation passed. The VLC conversion path also checks live libvlc state so cached ES-added notifications cannot hide natural EOF.

Seven physical receiver protocol checks passed: 1080p, 720p60, rapid source/audio replacement at 5.5 seconds, five pause/play pairs, backward seek, external subtitles on/off and an end-delimited rebuilt stream. These PC-driven receiver checks are separate from iPhone UI acceptance.

## Delivery and remaining device acceptance

The unsigned arm64 IPA has matching app/extension version 0.6.1/11, icon assets, media frameworks, license resources, Lock Screen command APIs and no validation marker. SHA256: e67b37e9edffa7a87e139a1f720c820f757f9265aef4e0805aabda526d62d71f.

Physical iPhone installation, legacy-card removal, rapid UI operations and locked-screen playback remain user acceptance checks. Synthetic simulator results do not certify a full-length high-bitrate/HDR movie on every iPhone. Stream-copy seeking is bounded by video keyframes; the measured seek fixtures differed by 0.5 seconds.

No credentials or personal source URLs belong in source control, diagnostics or handoffs. See THIRD_PARTY_NOTICES.md for pinned libraries and relinking instructions.
