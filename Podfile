platform :ios, '16.1'
target 'CastRemote' do
  use_frameworks!
  pod 'google-cast-sdk', '4.8.6'
  pod 'MobileVLCKit', '3.7.5'
  probe = ENV['CAST_ENGINE_ASS_TEST'] == '1'
  pod 'CastFFmpegKit', :podspec => (probe ? 'ThirdParty/CastFFmpegKitAssProbe.podspec' : 'ThirdParty/CastFFmpegKit.podspec')
end
