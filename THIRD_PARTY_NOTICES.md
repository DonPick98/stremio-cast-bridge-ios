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

Selected TrueHD/MLP audio is decoded and converted to AAC by the LGPL base build of FFmpegKit Extended, because the pinned VideoLAN iOS distribution omits that decoder. Other selected video/subtitle packets are copied unchanged through a private loopback HTTP stream to the VLC pipeline.

- Copyright Akash Patel, FFmpeg authors and contributors.
- License: LGPL 3.0 or later. Included texts: ThirdPartyLicenses/LGPL-3.0.txt and GPL-3.0.txt (referenced by LGPL).
- Source/build scripts: https://github.com/akashskypatel/ffmpeg-kit-builders/tree/fac2076d06a473b8e1c1ed5a1fabe52ee974a5c0
- Release: v0.11.2-ios, bundle-base-ios-universal-lgpl.xcframework.zip.
- SHA256: 2c152562cd107281cf2a8034ac8eb45629497f5eec2fb346f29ba9d0a62bde5f.
- The pinned build declares CONFIG_GPL=0, CONFIG_NONFREE=0, CONFIG_TRUEHD_DECODER=1, CONFIG_AAC_ENCODER=1 and CONFIG_SECURETRANSPORT=1.

The dependency is dynamically linked. To relink a modified version, build the same base LGPL variant from the supplied upstream scripts, replace the archive in ThirdParty/CastFFmpegKit.podspec, run pod install and rebuild this app from source. CastFFmpegBridge.h declares only the public C ABI needed by this integration; no library binary is modified.
