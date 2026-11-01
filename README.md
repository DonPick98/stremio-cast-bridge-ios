# Cast Bridge iOS 0.6

iOS sender for Stremio video sources and Google Cast receivers. The app reads media tracks with MobileVLCKit and chooses direct playback, remuxing or local conversion automatically.

Compatible H.264 video is preserved where possible. Incompatible audio becomes AAC stereo. Video conversion uses H.264 VideoToolbox with VP8/Vorbis fallback, up to 1920x1080 at 30 fps. TrueHD/MLP audio uses the pinned LGPL FFmpegKit backend, connected to VLC over loopback HTTP.

The interface includes source sizes, playback controls, audio/subtitle selection, persistent subtitle appearance settings, and a Live Activity. Interactive Live Activity buttons require iOS 17; display requires iOS 16.1. Its seek bar has tap targets and 30-second buttons rather than a draggable slider.

When local conversion is active, the phone must remain powered on and connected to the receiver's network. Force-quitting interrupts conversion. Background support uses an audio playback session while the local stream is active. Simulator results do not certify physical-device screen-lock behavior.

Subtitle text can be rendered into locally converted video. External WebVTT is served through the selected-device-only gateway and retimed after seeks. Graphic subtitles and styled ASS tracks can retain their source appearance.

## Build

Use CastRemote.xcworkspace, scheme CastRemote, Release and iphoneos. CocoaPods pins all media dependencies. GitHub Actions produces an unsigned IPA with the app icon, Live Activity extension and license texts. Install with a compatible signing tool such as SideStore.

Production builds must leave CAST_ENGINE_VALIDATION empty. CAST_ENGINE_TESTING enables the synthetic simulator validation only.

The separate validation workflow covers 25 synthetic codec combinations, HTTP gateway output, HTTPS input and continuous network transfer in background. Compatibility depends on file integrity, source availability and hardware capacity; DRM is outside the supported path.

See [HANDOFF.md](HANDOFF.md) for technical validation status, [BUILD-WINDOWS.md](BUILD-WINDOWS.md) for build steps and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses and upstream sources.
