Pod::Spec.new do |s|
  s.name             = 'tray_kit'
  s.version          = '0.1.0'
  s.summary          = 'A system tray icon with a menu for Flutter.'
  s.description      = 'A menu bar item with a menu for Flutter on macOS.'
  s.homepage         = 'https://github.com/Termphin/tray_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Termphin contributors' => 'contact@termphin.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'tray_kit/Sources/tray_kit/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
