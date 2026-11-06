# Upstream MKV subtitle extractor

MIT, copyright (c) 2026 Shy.
Source: https://github.com/cryguy/mkv-subtitle-extractor
Pinned commit: dbe77e997de9d305d2b45b237352a3dec51b5bb5

Sources preserved under src/. Cast Bridge's bridge.ts accepts only ASS/SSA with
complete Cues verified against NUMBER_OF_FRAMES for the exact TrackUID. It skips
fonts (the existing text-only conversion does not need them), rejects content
encodings and falls back to full FFmpeg demux if unsupported. The upstream batch
grouper is capped at256KiB spans to bound each read. All native HTTP requests
validate status206, Content-Range, file size and available validators before body,
with cancellation, size/request/time budgets. No untrusted script is fetched.

Build offline using Node24: node Scripts/bundle-mkv-extractor.mjs.
The generated Resources/MKVSubtitleExtractor.js runs in JavaScriptCore with a
bounded URLSession read bridge. The bridge never accepts a source URL from JS.
A 52-compatible full extraction starts concurrently: the first validated complete
result wins and cancels the loser. Partial indexes never become full subtitles.

