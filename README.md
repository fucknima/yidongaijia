# 爱家直连（iOS 第三方客户端）

本项目是移动爱家的第三方 iOS 客户端，不是中国移动、移动爱家或其关联公司的官方应用、SDK，也不代表上述任何一方。客户端由 iPhone 直接访问移动爱家云端接口，获取播放地址后在本机解码，不经过本项目的桥接服务器。

请只在你有权使用的账号和摄像头上运行。云端接口、签名规则和服务策略可能变化；本项目不提供或绕过官方授权，也不保证接口长期稳定。

当前只支持手机号和密码登录，短信验证码登录已经移除。

## 实现原理

```text
SwiftUI 登录界面
    ↓
PlayerViewModel（主线程状态与任务管理）
    ↓
AijiaAPI（URLSession async/await）
    ↓
移动爱家基础认证 → 视频服务认证 → 摄像头列表
    ↓
设备 jwtoken → 实时/回放地址
    ↓
MobileVLCKit 在 iPhone 本机解码播放
```

1. 基础认证请求 `base.hjq.komect.com/base/user/passwdLogin`。密码不以明文放入请求，而是计算 MD5 和 `fetion.com.cn:密码` 的 SHA1，成功后取得 `passId` 与会话 Cookie。
2. 视频服务登录请求 `video.komect.com/user/login/loginByHJQToken`，使用基础会话、手机号和 `passId` 换取视频服务令牌。
3. 调用摄像头列表接口，根据 `mac_id`、名称或 ID 选择设备；设备缺少 `jwtoken` 时再请求设备令牌。
4. 调用设备的实时地址接口，获得云端 MPEG-TS/H.265/AAC 地址，交给 MobileVLCKit 播放。
5. 播放期间定时保活；会话失效或网络失败时重新认证并重取地址。历史回放通过云端回放传输和跳转接口完成，云台控制也直接请求云端。

所有网络请求都在 `AijiaAPI` 中异步执行，`PlayerViewModel` 负责取消旧任务、避免过期任务覆盖新状态和驱动 SwiftUI。密码可选保存到 iOS 钥匙串，诊断日志会脱敏手机号、密码、令牌、Cookie、签名和 URL 参数。

## 构建

`iOS/AijiaDirect/` 是唯一的源码工作树，GitHub Actions 直接从该目录构建，不再解压 ZIP 或复制覆盖文件。

没有 Mac 时，在仓库的 **Actions** 页面运行 **Build AijiaDirect iOS IPA**。工作流会在 macOS runner 上安装 CocoaPods、编译未签名设备版并上传 `AijiaDirect-unsigned-ipa`。下载后需要用自己的 Apple ID 或开发者证书重新签名，未签名 IPA 不能直接安装。

在 Mac 上也可以直接打开：

```bash
cd iOS/AijiaDirect
pod install
open AijiaDirect.xcworkspace
```

## 目录

- `iOS/AijiaDirect/`：完整 iOS 工程源码。
- `.github/workflows/build-ios.yml`：直接编译工作树并上传 IPA 的工作流。

## 开源许可

本项目基于 [MIT License](LICENSE) 开源。
