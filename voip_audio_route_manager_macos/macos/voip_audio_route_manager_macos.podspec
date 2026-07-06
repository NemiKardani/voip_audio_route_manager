#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint voip_audio_route_manager_macos.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'voip_audio_route_manager_macos'
  s.version          = '1.1.2'
  s.summary          = 'macOS implementation of voip_audio_route_manager. Handles audio route changes and preferred device selection using native AVAudioSession configuration.'
  s.description      = <<-DESC
 VoIP Audio Route Manager: A production-ready Flutter package for advanced audio output device management and routing for VoIP communication applications.
                       DESC
  s.homepage         = 'https://github.com/NemiKardani/voip_audio_route_manager'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'nemikardani6867@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files = 'voip_audio_route_manager_macos/Sources/voip_audio_route_manager_macos/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'voip_audio_route_manager_macos_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
