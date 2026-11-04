# Subtitle pipeline and open-source adaptations

## Pinned references

- `dioKaratzas/swift-subtitle-kit`, MIT, revision `728d62dac9fbda7fabd299eed3673ce36c85c267`: cursor-based SRT cue boundaries and case-insensitive ASS field matching. Adapted in `Sources/SubtitleDocument.swift` for Swift 5/Foundation. The whole Swift 6 package is not linked.
- `dagronf/SwiftSubtitles`, MIT, revision `485c6f1fc71235041198a8bb893fa22f807451a6`: non-lossy NSString encoding detection from the demo's `String+decoding.swift`. Adapted with a UTF-8 fast path and explicit UTF-32-before-UTF-16 BOM handling.
- `jellyfin/jellyfin-chromecast`, revision `915a3f598e8dd6ead7fa2ff5ef1fc4df654ca18a`: external WebVTT subtitle profile reviewed as an architecture reference. No Jellyfin GPL source is copied.
- FFmpegKit/VideoLAN and the existing custom receiver remain pinned as documented in `THIRD_PARTY_NOTICES.md`.

Both MIT notices are embedded in the source/repository and listed in the iOS target's resources. Preserve notices when modifying or redistributing the adaptation.

## Delivery rules

Text tracks extracted from the file and external files become complete UTF-8 WebVTT documents, served with the existing local HTTP/CORS hosts to the default free Cast receiver. A failed preparation preserves the functioning selection. Incremental empty windows are valid during silence; an empty complete download is not a ready subtitle document. Cache entries are checked on read, including files written by older builds.

Bitmap tracks such as PGS use the existing FFmpeg video overlay. They cannot be made into correct text captions by a text parser. The original unknown `vlc_3` codec still needs identification; these adaptations do not prove that historical file works.

The optional custom receiver can preserve ASS styles using the existing Stremio/libass code. The default receiver receives readable WebVTT, so original ASS typography and animation are not promised. No new server, paid Cast registration or receiver deployment is required by this parser change.

## Adaptation-specific changes

SRT accepts indexed or unindexed cues, missing blank separators, nonconsecutive indices, one/two-digit clock components and one-to-three fractional digits. Fractions are right-padded (`.1` means 100 ms), and clocks remain bounded with minutes/seconds below 60. Empty cues are omitted when usable cues exist. Numeric payload lines in unindexed files are preserved. Existing WebVTT settings/markup are validated, rather than stripping all text tags.

ASS field/section matching tolerates case and surrounding whitespace while preserving commas in the text column. Conversion to WebVTT keeps the existing readable-text policy.

Encoding detection is bounded by the existing 1 MiB download limit, requests non-lossy conversion and rejects decoded NUL characters. Detection of every legacy character set is not guaranteed. External ZIP archives, OCR of bitmap subtitles and automatic font/style preservation on the default receiver are not added by this change.

## Validation and open work

`Tests/OpenSourceSubtitleTests.swift` adapts synthetic upstream scenarios and adds local safety/compatibility cases. Existing catalogue, URLProtocol transport, cache, preferences, native decoding and caption pixel tests remain enabled.

At the build31 source checkpoint no new Swift/iPhone test has passed: macOS jobs from build30 were still queued without a runner. Read actual workflow results before delivery. The existing native continuity gate for a 125 ms initial HEVC/EAC3 video gap is unchanged and unresolved; it is independent of successful text parsing. Hardware casting remains unverified.
