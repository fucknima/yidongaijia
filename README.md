# 移动爱家摄像头桥接

把移动爱家云端返回的动态直播流转换为稳定的本地 HTTP 地址，再交给 go2rtc 输出 WebRTC 和 RTSP。日常查看不需要打开移动爱家 App，但摄像头仍依赖移动云端。本设备当前返回 MPEG-TS 封装的 H.265/AAC 流，桥接服务会保留云端实际格式。

## 服务地址

- go2rtc 网页：`http://192.168.31.173:1984/`
- RTSP：`rtsp://192.168.31.173:8554/aijia`
- 桥接健康检查仅在服务器本机监听：`http://127.0.0.1:18080/health`

## 配置

服务器使用 `/etc/aijia-bridge.env` 保存账号，文件权限应为 `0600`。必填项：

```ini
AIJIA_PHONE=移动爱家账号手机号
AIJIA_PASSWORD=移动爱家账号密码
```

如果账号绑定了多台摄像头，可填写接口返回的摄像头 ID：

```ini
AIJIA_CAMERA_ID=
```

修改后执行：

```bash
systemctl restart aijia-bridge
systemctl restart go2rtc-aijia
```

查看状态：

```bash
systemctl status aijia-bridge --no-pager
systemctl status go2rtc-aijia --no-pager
curl http://127.0.0.1:18080/health
```

取流协议参考了已归档的开源项目 [XiaoMiku01/hass-hjq](https://github.com/XiaoMiku01/hass-hjq)。云端接口发生变化时，桥接程序也需要相应更新。
