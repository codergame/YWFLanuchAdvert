Pod::Spec.new do |s|
  s.name             = 'YWFLanuchAdvert'
  s.version          = '0.1.0'
  s.summary          = '启屏广告 SDK，固定 JSON 布局，素材 zip 支持断点续传。'
  s.description      = <<-DESC
YWFLanuchAdvert 是 iOS 启屏广告 SDK。宿主配置域名后即可拉取广告。
布局使用固定 JSON，支持坐标、线性、停靠三种方式，以及图片、按钮和 HTML。
素材 zip 通过 HTTP Range 断点续传，下载完成且处于投放时段才展示。
展示时长为整数，只有剩余时间等于 0 时才询问 delegate 是否跳转。
                       DESC
  s.homepage         = 'https://github.com/codergame/YWFLanuchAdvert'
  s.license          = { :type => 'MIT', :file => 'ios/LICENSE' }
  s.author           = { 'YWF' => 'dev@ywf.local' }
  s.source           = { :git => 'https://github.com/codergame/YWFLanuchAdvert.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.source_files = 'ios/YWFLanuchAdvert/**/*.{swift,c,h}'
  s.public_header_files = 'ios/YWFLanuchAdvert/Support/ywf_inflate.h'
  s.libraries = 'z'
  s.frameworks = 'UIKit', 'WebKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }
end
