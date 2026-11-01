Pod::Spec.new do |s|
  s.name = 'CastFFmpegKit'
  s.version = '0.11.2'
  s.summary = 'Pinned LGPL FFmpegKit backend for codecs absent from MobileVLCKit.'
  s.homepage = 'https://github.com/akashskypatel/ffmpeg-kit-builders'
  s.author = 'Akash Patel and FFmpeg contributors'
  s.license = { :type => 'LGPL-3.0-or-later' }
  s.platform = :ios, '16.1'
  s.source = { :http => 'https://github.com/akashskypatel/ffmpeg-kit-builders/releases/download/v0.11.2-ios/bundle-base-ios-universal-lgpl.xcframework.zip', :sha256 => '2c152562cd107281cf2a8034ac8eb45629497f5eec2fb346f29ba9d0a62bde5f' }
  s.prepare_command = 'mv bundle-base-ios-universal-lgpl.xcframework ffmpegkit.xcframework'
  s.vendored_frameworks = 'ffmpegkit.xcframework'
end
