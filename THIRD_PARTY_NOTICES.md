# Embedded media engine

Cast Bridge uses MobileVLCKit 3.7.5 from VideoLAN, an Objective-C/Swift wrapper around libVLC. Copyright belongs to VideoLAN and the respective contributors.

- License: GNU Lesser General Public License 2.1 or later; component licenses are included in the upstream distribution.
- Source: https://code.videolan.org/videolan/VLCKit (3.0 branch; release archive identifies revisions `a213fd11-6de05adc`).
- Official mirror: https://github.com/videolan/vlckit
- Pinned binary archive: https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.7.5-a213fd11-6de05adc.tar.xz
- SHA256: `a76f7a6cfcde4209b56f943e6e18400659d8a7a93ff482f8b1d059468d11e6be`.
- Build and packaging source: https://github.com/videolan/vlckit/blob/3.0/buildMobileVLCKit.sh
- License text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

The complete Cast Bridge application source and Xcode project are available in this repository. To relink a modified library, rebuild VLCKit from the upstream source, replace the MobileVLCKit CocoaPods framework with that build, then build the application using the supplied Xcode workspace. The codec fixtures are generated from synthetic video and audio; they contain no third-party movies.

Cast Bridge is independent of VideoLAN. It does not redistribute VideoLAN branding.

## FFmpegKit Extended

The LGPL base build of FFmpegKit Extended copies compatible original video packets into fragmented MP4 and selects or converts audio, including TrueHD/MLP omitted from the pinned VideoLAN distribution. Output uses a bounded local socket. Video conversion can receive selected video/audio/subtitle packets through a private Matroska loopback stream. All processing runs on the phone.

- Copyright Akash Patel, FFmpeg authors and contributors.
- License: LGPL 3.0 or later. Included texts: ThirdPartyLicenses/LGPL-3.0.txt and GPL-3.0.txt (referenced by LGPL).
- Source/build scripts: https://github.com/akashskypatel/ffmpeg-kit-builders/tree/fac2076d06a473b8e1c1ed5a1fabe52ee974a5c0
- Release: v0.11.2-ios, bundle-base-ios-universal-lgpl.xcframework.zip.
- SHA256: 2c152562cd107281cf2a8034ac8eb45629497f5eec2fb346f29ba9d0a62bde5f.
- The pinned build declares CONFIG_GPL=0, CONFIG_NONFREE=0, CONFIG_TRUEHD_DECODER=1, CONFIG_AAC_ENCODER=1 and CONFIG_SECURETRANSPORT=1.

The dependency is dynamically linked. To relink a modified version, build the same base LGPL variant from the supplied upstream scripts, replace the archive in ThirdParty/CastFFmpegKit.podspec, run pod install and rebuild this app from source. CastFFmpegBridge.h declares only the public C ABI needed by this integration; no library binary is modified.


## Independent caption receiver

Receiver/vendor/stremio contains MIT-licensed parsing/rendering code from Stremio/stremio-video at 7a7462bedfa51dc8303fbc4f59f16e03d0badb85 (Smart Code OOD). The receiver uses vtt.js 0.13.0 (Mozilla, Apache 2.0) and @stremio/libass-wasm 4.2.7 (libass and dependency licenses). Full notices and upstream sources are in Receiver/THIRD_PARTY_NOTICES.txt and deployment licenses/. No Stremio application ID or service credentials are reused.
