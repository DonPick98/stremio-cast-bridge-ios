# Technical checkpoint: Cast Bridge 0.6.0 (10)

## Architecture

- Google Cast SDK owns receiver control and playback status.
- MobileVLCKit reads track metadata, remuxes compatible video and converts unsupported formats.
- AudioRepairPipe uses the pinned LGPL FFmpegKit backend for TrueHD/MLP. Selected video/subtitle packets are copied and selected audio becomes AAC stereo. Transport to VLC is HTTP bound exclusively to 127.0.0.1.
- LocalStreamProxy exposes exact-token routes only to the selected receiver. It validates and retains stream initialization before LOAD, preserves external WebVTT timing after seeks and bounds buffering.
- MediaOutputChannel transports VLC output over an anonymous socket. At input EOF the player is stopped with the transport still writable, allowing the muxer to flush its final fragment before the writer closes.
- Native seeks rebuild the stream at the requested original-media position. Pause, duration and selected tracks remain associated with the original timeline.
- A background audio helper runs only during active local streaming. Receiver session suspension is disabled for that path.
- Credentials remain in Keychain. Stream URLs are not written to preferences. Test fixtures contain only generated images and tones.

## Validation status

All 25 synthetic codec combinations passed decoded video/audio validation, including TrueHD, AC3, DTS, HEVC 10-bit, alternate audio selection and embedded text subtitles. Five converted synthetic cases played on a classic Chromecast, with video and tone confirmed by the tester.

The final background probe transferred 7,798,457 bytes over 65.399 seconds with the application offscreen, including 1,966,080 bytes after 50 seconds. Normal and back-to-back pause/resume, the playback audio helper and clean cancellation passed. Physical iPhone screen-lock behavior is a separate acceptance check.

All 30 decoded outputs and all five gateway EOF checks passed. The resulting five gateway files also played on a classic Chromecast. Resume always enqueues PLAYING, even while an asynchronous pause has not yet changed isPlaying; the background test includes that rapid-command regression.

Validated source: e27f3230a1308be3a70bb238d5edccea656dd034. Native validation: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41298204301 . Production build and regression checks: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41298204296 . The release tree adds documentation to that validated source.

Do not treat a successful build, PLAYING status, or an audio track header alone as evidence of decoded audio. Check actual output samples and complete video frames.

## Release checks

1. Run native-engine-probe.yml: 25 matrix cases, all gateway scenarios, HTTPS input and background transfer.
2. Run build-ios.yml: resolver, controls, subtitle, gateway and timeline tests; build iphoneos without CAST_ENGINE_TESTING.
3. Verify app and extension version 0.6.0 / 10, icon assets, media frameworks, license resources and absence of the validation marker in the production executable.
4. Verify downloaded artifact SHA256 before extracting the IPA.
5. Physical-device installation, screen lock and full-length playback remain separate acceptance checks.

The unsigned 0.6.0 (10) IPA has been checked for arm64, matching app/extension versions, icon assets, media frameworks, license resources, Lock Screen media APIs and absence of the self-test marker. See THIRD_PARTY_NOTICES.md for pinned dependencies and rebuild instructions.
