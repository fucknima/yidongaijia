# 爱家直连（iOS）

这是一个不经过你的小服务器的 iOS 客户端：手机直接调用移动爱家当前使用的云端接口，拿到带签名的 MPEG-TS 实时地址，再在手机本地用 MobileVLCKit 解码 H.265/AAC。

## 当前能力

- 移动手机号 + 密码登录
- 自动读取账号下的摄像头
- 可选填写 `mac_id` 或摄像头名称；留空使用列表中的第一台
- 自动获取设备 `jwtoken`
- 获取实时地址并在本机播放
- 每 20 秒直接向云端发送保活请求
- 保活失败时自动重新获取播放地址并重连
- 从后台回到前台时主动丢弃旧实时地址并重新取流，避免从几分钟前的缓存位置继续播放
- 播放界面提供上下左右云台控制
- 按日期查询内存卡录像，启动云端回放并在手机本机解码；回放期间自动保活
- 可选记住登录：手机号和摄像头选择保存到本地设置，密码保存到 iOS 钥匙串
- 诊断日志记录登录阶段、HTTP 状态/耗时/响应结构、保活、重连、VLC 播放器状态和错误；最多保留 4,000 行，导出前自动脱敏密码、令牌、签名、Cookie、手机号和 URL 查询参数
- 不依赖 173 服务器或局域网摄像头地址

## 在 Mac 上构建

这个仓库是在 Windows 上生成的，Windows 没有 Xcode，因此这里不能直接产出可安装的 iOS IPA。需要一台 Mac：

```bash
cd iOS/AijiaDirect
pod install
open AijiaDirect.xcworkspace
```

在 Xcode 中选择真机，给 Target 设置自己的 Apple Developer Team，然后运行。首次启动后在 App 内输入移动爱家账号和密码。

如果 Xcode 提示 Bundle Identifier 已被占用，把 com.example.AijiaDirect 改成你自己的唯一标识即可。

## 没有 Mac：使用 GitHub Actions

仓库根目录已经带有 .github/workflows/build-ios.yml。把整个项目上传到 GitHub 后，在仓库的 Actions 页面选择 Build AijiaDirect iOS IPA，点击 Run workflow。任务会在 GitHub 的 macOS runner 上自动安装 CocoaPods、编译设备版并上传 AijiaDirect-unsigned-ipa 工件。

下载工件并解压得到 IPA 后，在 Windows 上可用 [AltStore Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 或 [Sideloadly](https://sideloadly.io/) 使用自己的 Apple ID 重新签名并安装。免费 Apple ID 的侧载有效期和数量受 Apple 限制；如果需要长期稳定使用，建议用自己的 Apple Developer 账号走 TestFlight。

## 依赖和限制

- 需要 macOS、Xcode、CocoaPods。
- 播放依赖 [MobileVLCKit 3.4.0](https://github.com/videolan/vlckit)。它用于处理浏览器通常不能直接播放的 H.265 MPEG-TS 流。
- 移动爱家接口不是公开稳定 SDK；接口、签名规则或服务器策略改变后，客户端需要跟着调整。
- 密码只写入 iOS 钥匙串；诊断日志不会写入完整手机号、密码、令牌或签名 URL。
- 这是个人局域网/个人账号使用的直连客户端；如要发布到 App Store，需要自行检查 VideoLAN 组件的许可证和再分发要求。

## 目录

- `AijiaDirect/Services/AijiaAPI.swift`：云端登录、摄像头列表、设备令牌、实时/历史地址、云台和保活。
- `AijiaDirect/Services/PlayerViewModel.swift`：登录持久化、播放/回放状态、云台、历史查询、重连和保活定时器。
- `AijiaDirect/Services/DiagnosticsLogger.swift`：隐私安全诊断日志和导出。
- `AijiaDirect/Services/CredentialStore.swift`：钥匙串登录凭据存取。
- `AijiaDirect/Views/VLCPlayerView.swift`：MobileVLCKit 的 SwiftUI 包装。
