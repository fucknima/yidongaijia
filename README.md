# 移动爱家第三方客户端与桥接服务

本仓库包含两个可以独立使用的部分：

- `aijia-direct-source-posix.zip`：爱家直连 iOS 客户端的完整源代码归档。
- `bridge.py`、`go2rtc.yaml.example` 等：把云端直播流转成本地 HTTP、WebRTC 或 RTSP 的桥接服务。

## 重要说明

爱家直连是第三方客户端，不是中国移动、移动爱家或其关联公司的官方应用、SDK，也不代表上述任何一方。客户端直接访问移动爱家当前使用的云端接口，接口、签名规则和服务策略变化时可能需要同步调整代码。

请只在你有权使用的账号和摄像头上运行。账号密码由用户自行输入；选择“记住登录”时，密码保存到 iOS 钥匙串。项目不会提供或绕过官方授权，也不保证云端接口长期可用。

当前 iOS 客户端只保留手机号和密码登录，短信验证码登录已经移除；README、源代码归档和 GitHub Actions 构建输入保持同步。

## iOS 客户端

客户端手机直连云端，获取实时或历史回放地址，并在本机使用 MobileVLCKit 解码。无需部署本项目的桥接服务器。

主要功能：

- 密码登录、保存钥匙串凭据和自动连接
- 获取账号下的摄像头列表并选择设备
- 实时流播放、云台控制和历史回放
- 保活、前后台刷新、重连和诊断日志导出

源码位于 `aijia-direct-source-posix.zip`。没有 Mac 时可以使用仓库中的 GitHub Actions 工作流构建未签名 IPA：

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build AijiaDirect iOS IPA** 并运行工作流（或推送会触发构建）。
3. 下载 `AijiaDirect-unsigned-ipa` 工件，再使用自己的 Apple ID 或开发者证书重新签名安装。

未签名 IPA 不能直接安装；侧载有效期和设备数量由 Apple 账号类型决定。正式发布前还需要自行检查 Apple、MobileVLCKit 及相关接口的许可和再分发要求。

## 桥接服务

桥接服务把云端返回的动态直播地址转换为稳定的本地地址，再交给 go2rtc 输出 WebRTC 和 RTSP。摄像头仍依赖移动爱家云端。

### 配置

复制 `aijia.env.example` 为 `/etc/aijia-bridge.env`，并将权限设为 `0600`：

```ini
AIJIA_PHONE=移动爱家账号手机号
AIJIA_PASSWORD=移动爱家账号密码
AIJIA_CAMERA_ID=
```

然后重启服务：

```bash
systemctl restart aijia-bridge
systemctl restart go2rtc-aijia
systemctl status aijia-bridge --no-pager
curl http://127.0.0.1:18080/health
```

默认示例地址为 `http://127.0.0.1:18080/health`、`rtsp://127.0.0.1:8554/aijia`。请按自己的网络和 go2rtc 配置修改，不要把账号密码提交到仓库。

## 目录

- `build-overrides/`：GitHub Actions 构建时使用的四个 iOS 源文件，必须与源代码归档保持一致。
- `aijia-direct-source-posix.zip`：可在 Mac/Xcode 中打开和修改的 iOS 工程源代码。
- `bridge.py`：桥接服务。
- `test_bridge.py`：桥接服务测试。
