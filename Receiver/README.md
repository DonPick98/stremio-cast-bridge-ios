# Independent Cast Bridge captions

This receiver uses Google's CAF media player for the existing video stream and
Stremio's MIT caption helpers for a separate WebVTT/libass overlay. It does not
load, seek, pause or transcode video when selecting or synchronizing text tracks.
Bitmap subtitles still use the native burn-in fallback and can require a reload.

## Build and host

Run `npm ci --ignore-scripts`, `npm test`, and `npm run build` in this directory.
Deploy every file under `dist/` unchanged to an HTTPS directory, for example
`/cast-receiver/`. Keep the licenses directory and THIRD_PARTY_NOTICES.txt.
The HTML must be publicly accessible without a login or an SPA redirect.
Use gzip/Brotli for receiver.js; keep its content type JavaScript. No server-side
conversion, credentials or movie URLs are needed by this hosted page.

Allow Google's official CAF script, blob workers/fonts and WebAssembly in this
page's content security policy. Permit HTTP connections to the phone on the LAN;
do not upgrade those HTTP requests to HTTPS. The receiver validates that caption
URLs are private IPv4 addresses under a token-scoped `/captions/` directory.

## Google activation

A Custom Web Receiver needs its own registered Google Cast application ID.
Register the HTTPS index.html URL in the Google Cast SDK Developer Console and
register the test Chromecast serial before testing an unpublished receiver.
Do not use Stremio's, DashCast's or another developer's application ID.

Google charges a one-time US$5 developer account registration fee if the account
does not already exist; no payment is performed by this repository. Google says
account processing can take up to 48 hours. Documentation:

- https://developers.google.com/cast/docs/registration
- https://support.google.com/cast-developer/answer/4512496?hl=en

Run the iOS build workflow manually with `receiver_app_id` set to the assigned
eight-digit hexadecimal ID. It is embedded in the application and Bonjour
discovery entitlement together. The default `CC1AD845` intentionally retains
legacy playback and does **not** activate this new caption path.

## Caption protocol and lifecycle

The `urn:x-cast:app.castbridge.captions` namespace carries versioned JSON.
Each media LOAD includes `customData.bridge` with epoch, source-time offset and
the token-scoped phone state URL. Selection messages contain immutable caption
URLs, absolute coverage, optional ASS font URLs, delay and saved appearance.
The receiver also polls the state endpoint with its actual media clock. Sender
SDK reconnection alone therefore does not stop captions while the phone's
local service remains available. iOS background execution must be device-tested.

FFprobe selects exact subtitle stream indices. FFmpeg exports bounded 90-second
source-time windows; coverage is published after a bounded extraction succeeds,
including intervals without dialogue. Seeking back requests a new window.
Original styled ASS is optional; default WebVTT preserves user appearance.
Errors remain caption errors and never trigger a video retry in this component.

## Validation scope

Node tests cover cancellation, delayed responses, immutable URL reuse, timeline
offsets, stale generations, parser completion and error isolation. Native tests
export ASS/WebVTT at zero and after a seek, sparse and silent intervals, attached
fonts, cancellation and the local HTTP service. The browser harness exercises
the actual Stremio parser/libass renderer with a synthetic video.

These checks do not replace physical Chromecast playback, font/performance and
locked-phone testing after application registration.
