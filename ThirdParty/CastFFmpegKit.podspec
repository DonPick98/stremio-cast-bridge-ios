Pod::Spec.new do |s|
  s.name = 'CastFFmpegKit'
  s.version = '0.11.2'
  s.summary = 'Pinned LGPL FFmpegKit video backend with native subtitle rendering.'
  s.homepage = 'https://github.com/akashskypatel/ffmpeg-kit-builders'
  s.author = 'Akash Patel and FFmpeg contributors'
  s.license = { :type => 'LGPL-3.0-or-later' }
  s.platform = :ios, '16.1'
  s.source = { :http => 'https://github.com/akashskypatel/ffmpeg-kit-builders/releases/download/v0.11.2-ios/bundle-video-ios-universal-lgpl.xcframework.zip', :sha256 => '772310d94274a5721e302960bc3f6aab706115409cb03dd2839d67fd4f718891' }
  s.prepare_command = 'mv bundle-video-ios-universal-lgpl.xcframework ffmpegkit.xcframework'
  s.vendored_frameworks = 'ffmpegkit.xcframework'
end
