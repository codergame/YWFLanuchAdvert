require 'xcodeproj'

project = Xcodeproj::Project.new('YWFLanuchAdvertExample.xcodeproj')
target = project.new_target(:application, 'YWFLanuchAdvertExample', :ios, '13.0')
group = project.main_group.new_group('YWFLanuchAdvertExample', 'YWFLanuchAdvertExample')

%w[AppDelegate.swift SceneDelegate.swift ViewController.swift ObjCEntry.m].each do |name|
  target.add_file_references([group.new_file(name)])
end
group.new_file('ObjCEntry.h')
group.new_file('YWFLanuchAdvertExample-Bridging-Header.h')

%w[default_splash.json splash.png LaunchScreen.storyboard].each do |name|
  target.add_resources([group.new_file(name)])
end

settings = {
  'INFOPLIST_FILE' => 'YWFLanuchAdvertExample/Info.plist',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.ywf.YWFLanuchAdvertExample',
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => '13.0',
  'TARGETED_DEVICE_FAMILY' => '1,2',
  'SWIFT_OBJC_BRIDGING_HEADER' => 'YWFLanuchAdvertExample/YWFLanuchAdvertExample-Bridging-Header.h',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
  'GENERATE_INFOPLIST_FILE' => 'NO',
  'CLANG_ENABLE_MODULES' => 'YES'
}
target.build_configurations.each do |config|
  config.build_settings.merge!(settings)
end
project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
end
project.save
