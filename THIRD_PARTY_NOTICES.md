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
