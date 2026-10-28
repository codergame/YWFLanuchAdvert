# YWFLanuchAdvert

iOS 启屏广告 SDK，以及部署在 Tomcat 10.1 上的编辑后台。宿主只改域名即可拉配置。素材 zip 支持断点续传，下载完成且处于投放时段才展示。

## iOS

最低 iOS 13。Pod 名是 `YWFLanuchAdvert`，Swift 和 Objective-C 都能调用。

```swift
YWFLanuchAdvert.shared.delegate = self
YWFLanuchAdvert.shared.start(domain: "https://ad.example.com")
YWFLanuchAdvert.shared.setDefaultLayout(fileName: "default_splash.json", bundle: .main)
YWFLanuchAdvert.shared.show(on: window) {
    // delegate 允许跳转后进入首页
}
```

```objc
[YWFLanuchAdvert.shared startWithDomain:@"https://ad.example.com"];
[YWFLanuchAdvert.shared setDefaultLayoutWithFileName:@"default_splash.json" bundle:NSBundle.mainBundle];
[YWFLanuchAdvert.shared showOnWindow:self.window completion:^{}];
```

展示时长是 `Int`。大于 0 时每秒减 1，只有剩余时间 `== 0` 才调用：

```objc
- (BOOL)ywfLanuchAdvertShouldJumpWhenTimeReachedZero:(YWFLanuchAdvert *)advert;
```

返回 `YES` 关闭启屏并执行 completion。返回 `NO` 广告继续停留。未实现该方法时按允许跳转处理。负数不会自动跳转。用户点跳过会直接结束，不再询问 delegate。

HTML 节点可以改用宿主自己的 `WKWebView`。每个 HTML 节点调用一次，需要返回一个还没加入视图层级的新实例。返回 `nil` 或未实现时，SDK 自己创建：

```objc
- (nullable WKWebView *)ywfLanuchAdvertCustomWebView:(YWFLanuchAdvert *)advert;
```

本地 Example：

```bash
cd ios/Example
pod install
open YWFLanuchAdvertExample.xcworkspace
```

发布到 CocoaPods trunk 时，在仓库根目录执行：

```bash
pod lib lint --allow-warnings
pod trunk push YWFLanuchAdvert.podspec
```

源码仓库是 https://github.com/codergame/YWFLanuchAdvert 。

## 后台

JDK 11，WAR 部署到 Tomcat 10.1 及以上。数据库是 SQLite，文件在 `LAUNCHADVERT_HOME`（默认 `$CATALINA_BASE/launchadvert`）。

```bash
cd server/admin-ui && npm install && npm run build
cd .. && mvn -q package
```

把 `server/target/lanuchadvert.war` 放到 Tomcat 的 `webapps/ROOT.war`。也可以：

```bash
docker build -t lanuchadvert server
docker run --rm -p 8080:8080 -v lanuchadvert-data:/data/launchadvert lanuchadvert
```

打开 `http://127.0.0.1:8080/`。默认账号 `admin` / `admin`，用环境变量 `LAUNCHADVERT_ADMIN_USER` 和 `LAUNCHADVERT_ADMIN_PASSWORD` 修改。

编辑分三步：

1. 规划样式，上传图片或 HTML，点「存储广告」。服务器把散文件打成 zip。
2. 下载 zip，自行放到 CDN，填写 https 链接。测试可以改用服务器上的 zip 地址。CDN 文件的 MD5 必须和生成包一致。
3. 填写生效时间段，展示时长选 3、5、8 秒或自定义整数（可为负），然后发布。

SDK 的素材地址只接受 https。`localhost`、`127.0.0.1` 可以用 http，方便连本机 Tomcat 做测试。

布局格式见 [schema/splash-layout.schema.json](schema/splash-layout.schema.json)，示例见 [schema/sample-splash.json](schema/sample-splash.json)。
