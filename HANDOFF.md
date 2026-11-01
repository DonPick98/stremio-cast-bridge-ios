# Technical checkpoint: Cast Bridge 0.6.0 (10)

## Architecture

- Google Cast SDK owns receiver control and playback status.
- MobileVLCKit reads track metadata, remuxes compatible video and converts unsupported formats.
- AudioRepairPipe uses the pinned LGPL FFmpegKit backend for TrueHD/MLP. Selected video/subtitle packets are copied and selected audio becomes AAC stereo. Transport to VLC is HTTP bound exclusively to 127.0.0.1.
- LocalStreamProxy exposes exact-token routes only to the selected receiver. It validates and retains stream initialization before LOAD, preserves external WebVTT timing after seeks and bounds buffering.
- Native seeks rebuild the stream at the requested original-media position. Pause, duration and selected tracks remain associated with the original timeline.
- A background audio helper runs only during active local streaming. Receiver session suspension is disabled for that path.
- Credentials remain in Keychain. Stream URLs are not written to preferences. Test fixtures contain only generated images and tones.

## Validation status

The iOS binary has successfully converted TrueHD to AAC in an isolated file test. The prior FIFO transport failed and has been replaced by loopback HTTP; the new end-to-end result remains to be checked.

The earlier codec matrix passed 24 of 25 cases. Background transfer passed an earlier 15-second simulator probe, while later probes exposed a startup/session regression. Current validation additionally requires a continuous data span and bytes arriving after ten seconds.

Do not treat a successful build, PLAYING status, or an audio track header alone as evidence of decoded audio. Check actual output samples and complete video frames.

## Release checks

1. Run native-engine-probe.yml: 25 matrix cases, all gateway scenarios, HTTPS input and background transfer.
2. Run build-ios.yml: resolver, controls, subtitle, gateway and timeline tests; build iphoneos without CAST_ENGINE_TESTING.
3. Verify app and extension version 0.6.0 / 10, icon assets, media frameworks, license resources and absence of the validation marker in the production executable.
4. Verify downloaded artifact SHA256 before extracting the IPA.
5. Physical-device installation, screen lock and full-length playback remain separate acceptance checks.

Main remains on the previous release until the candidate passes the required checks. See THIRD_PARTY_NOTICES.md for pinned dependencies and rebuild instructions.
