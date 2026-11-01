# Cast Bridge iOS 0.6.1

iOS sender for Stremio video sources and Google Cast receivers. The app reads media tracks with MobileVLCKit and chooses direct playback, remuxing or local conversion automatically.

Compatible H.264 video packets are copied by the pinned LGPL FFmpegKit backend, preserving the original picture and cadence while selecting or converting audio. Incompatible audio becomes AAC stereo. Video conversion uses H.264 VideoToolbox with VP8/Vorbis fallback, within receiver limits such as 1080p/30 or 720p/60. Unsupported audio and nonzero seeks can be normalized before video conversion through a private Matroska loopback stream.

FFmpeg remux and VLC conversion output travel through a bounded anonymous socket into the local HTTP gateway. The same upstream connection is retained from initialization through playback, and natural end of stream waits for the muxer to close its output descriptor. Copy-mode pause applies backpressure without closing the connection.

The interface includes source sizes, automatic playback after source selection, remembered audio/subtitle languages and persistent subtitle appearance settings. The iOS system media card is the single playback surface on the Lock Screen and in Control Center, with a draggable timeline and 30-second controls through MPNowPlayingInfoCenter and MPRemoteCommandCenter. Version 0.6.1 closes legacy ActivityKit cards when opened.

Compatible video is copied without re-encoding. Local video conversion preserves the source cadence unless it exceeds the receiver limit; fractional rates are not forced to 30 fps. The player displays the source resolution and frame rate and whether video is original or converted. Seek and track replacements retain the requested original-media position until the new receiver status confirms it. Cancelled source preparations cannot publish into later selections.

When local conversion is active, the phone must remain powered on and connected to the receiver's network. Force-quitting interrupts conversion. Background support uses an audio playback session restricted to active casting. Controls reconnect without reloading owned media; a pinned direct Cast connection provides a fallback for media commands. Simulator results do not certify physical-device screen-lock behavior.

Subtitle text can be rendered into locally converted video. External WebVTT is served through the selected-device-only gateway and retimed after seeks. Graphic subtitles and styled ASS tracks can retain their source appearance.

## Build

Use CastRemote.xcworkspace, scheme CastRemote, Release and iphoneos. CocoaPods pins all media dependencies. GitHub Actions produces an unsigned IPA with the app icon, Live Activity extension and license texts. Install with a compatible signing tool such as SideStore.

Production builds must leave CAST_ENGINE_VALIDATION empty. CAST_ENGINE_TESTING enables the synthetic simulator validation only.

The separate validation workflow covers 25 synthetic codec combinations, five gateway cases, eight resolution/cadence/seek cases and 65 seconds of continuous network transfer in background with pause/resume and cancellation. The copied 1080p test compares every decoded frame with its source. Compatibility depends on file integrity, source availability and hardware capacity; DRM is outside the supported path.

See [HANDOFF.md](HANDOFF.md) for technical validation status, [BUILD-WINDOWS.md](BUILD-WINDOWS.md) for build steps and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses and upstream sources.
