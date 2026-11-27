Pod::Spec.new do |s|
  s.name             = 'handdraw_smart_path'
  s.version          = '0.1.0'
  s.summary          = 'On-device text layout detection for HandDraw Studio.'
  s.description      = <<-DESC
Apple Vision adapter used by the cross-platform HandDraw Smart Path engine.
                       DESC
  s.homepage         = 'https://example.invalid/handdraw-smart-path'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'HandDraw Studio' => 'dev@handdraw.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'handdraw_smart_path/Sources/handdraw_smart_path/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'
  s.frameworks = 'Vision', 'AppKit'
end
