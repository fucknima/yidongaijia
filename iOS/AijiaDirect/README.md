# 爱家直连（iOS 第三方客户端）

这是移动爱家的第三方 iOS 客户端，不是中国移动、移动爱家或其关联公司的官方应用或 SDK，也不代表上述任何一方。App 直接访问移动爱家云端接口，获取实时或历史回放地址，再使用 MobileVLCKit 在 iPhone 本机解码；不需要桥接服务器。

当前只支持手机号和密码登录，短信验证码登录已移除。请只在你有权使用的账号和摄像头上运行。云端接口、签名规则和服务策略可能变化，本项目不提供或绕过官方授权，也不保证接口长期稳定。

## 实现原理

```text
SwiftUI → PlayerViewModel → AijiaAPI → 移动爱家云端
                                      ↓
                         实时/回放地址 → MobileVLCKit 本机播放
```

- 基础账号密码认证取得 `passId` 和会话 Cookie。
- 视频服务认证取得视频令牌，再读取摄像头列表。
- 必要时获取设备 `jwtoken`，再请求实时或历史回放地址。
- 请求参数按接口规则签名；播放期间定时保活，失效后重新认证和取流。
- 密码可选保存到 iOS 钥匙串，诊断日志会脱敏敏感信息。

## 在 Mac 上构建

```bash
pod install
open AijiaDirect.xcworkspace
```

在 Xcode 中选择真实设备并设置自己的 Apple Developer Team。若 Bundle Identifier 被占用，请将 `com.example.AijiaDirect` 改成自己的唯一标识。

## GitHub Actions

仓库工作流直接编译 `iOS/AijiaDirect/` 工作树，在 macOS runner 上安装 CocoaPods 并上传未签名 IPA。未签名 IPA 需要使用自己的 Apple ID 或开发者证书重新签名后安装。

## 主要文件

- `AijiaDirect/Services/AijiaAPI.swift`：认证、摄像头、设备令牌、实时/回放地址和保活。
- `AijiaDirect/Services/PlayerViewModel.swift`：登录、播放、回放、重连和任务状态。
- `AijiaDirect/Services/CredentialStore.swift`：钥匙串凭据存取。
- `AijiaDirect/Services/DiagnosticsLogger.swift`：脱敏诊断日志。
- `AijiaDirect/Views/VLCPlayerView.swift`：MobileVLCKit 播放器包装。
