# 云回放（云端录像）接口逆向与实现笔记

本文记录对移动爱家/和家亲（komect，`hejiaqin`）云端录像（云回放）接口的逆向过程、签名规则、播放链路与调试经验，供后续维护参考。所有结论均经过实弹请求验证。

> 注意：以下接口、签名与密钥为第三方逆向所得，可能随时变化；请仅在你拥有权限的账号与设备上使用。

## 一、总体架构

```text
基础认证 (base.hjq.komect.com)
   ↓ HJQToken + passId
视频服务认证 (video.komect.com /user/login/loginByHJQToken) → videoToken
   ↓ AuthorizationToken
摄像头列表 /camera/core/api/bind/queryList → macId
   ↓ AuthorizationToken + AuthorizationJwtoken (设备令牌)
云回放会话 /camera/playback/createPlayback → session + 预签名 m3u8 URL
   ↓ 直接 GET（无需额外签名）
m3u8（HLS 播放列表，含带 token 的 TS 分段 URL）
   ↓
TS 分段（MPEG-TS / H.265 2304x1296 / AAC）
```

## 二、签名规则

视频服务（`video.komect.com` 与 `accesslf2.region.video.komect.com:2443`）的接口签名：

```text
sign = md5( 按 key 字典序拼接的 "key值" 序列 + 接口path + 密钥 )
密钥 = r8rw4d1kjwqgqqto9dwsq3ew0ip2np1b
```

- 参数与 `sign` 一起放在 query 中；`sign` 本身不参与签名。
- `nonce` 通常取 `时间戳ms + 固定后缀`（如 `gs08t`、`m5kjt`、`abcde`）。
- **部分接口的业务参数放在 JSON body 里，但签名只覆盖 query**（如告警列表接口），这是最容易踩的坑。
- **`createPlayback` 特殊**：POST 请求，所有参数（`macId`、`userId`、`startTime`、`endTime`、`nonce`、`time`）全部放在 query 且全部参与签名，body 为空。此前一直 SIGN_ERROR 就是因为把业务参数塞进了 body、或签名没有覆盖全部 query 参数。

附带：`alarm/alarms/calendar`（云录像日历）签名与标准规则一致（已用抓包样本比对验证）。

## 三、云回放播放链路

### 1. 云录像日历

```http
GET https://video.komect.com/alarm/alarms/calendar
  ?alarm_type=&category=1&dev_sn={macId}
  &end_time={毫秒}&start_time={毫秒}&user_id={手机号}
  &nonce=...&sign=...&time=...
Header: AuthorizationToken
```

响应 `data` 为有云录像的日期（**epoch 秒**，本地 0 点）。区间内没有录像时服务器会省略 `data` 字段（按空数组处理）。

注意参数必须传**毫秒**——曾把秒当毫秒传，服务器返回 `code:0` 但 data 为空，排查了很久。

### 2. 创建播放会话（核心）

```http
POST https://video.komect.com/camera/playback/createPlayback
  ?macId={macId}&userId={手机号}
  &startTime={毫秒}&endTime={毫秒}
  &nonce={ts}gs08t&time={ts}&sign={md5覆盖全部query参数+path+密钥}
Header: AuthorizationToken + AuthorizationJwtoken
Body: 无
```

响应：

```json
{"code":0,"data":{
  "session":"<UUID>",
  "url":"https://stream-sx02.jtzs.sn.chinamobile.com:9443/stream/openstream/media/channels/{macId}/playback/{startMs}_{endMs}.m3u8?session=<UUID>&sign=<服务端计算的18字节签名>",
  "start":..., "end":..., "duration":..., "expire":..., "regionId":..., "channelId":"{macId}"
},"msg":"Success"}
```

关键结论：

- **m3u8 URL 的 `sign` 由服务端下发，客户端不需要也不能自己推导**（18 字节，猜测为自定义结构）。之前的 "破解 18 字节签名" 方向是死路。
- `session` 由服务端签发，**不能用客户端随机 UUID** 伪造（媒体服务器校验 "session not found"）。
- 服务器会把请求窗口**对齐到真实录像的分段边界**（响应里的 `start`/`end` 是修正后的）。

### 3. 拉取 m3u8

直接 GET 返回的 URL 即可（**媒体服务器不校验 User-Agent**，实测默认 UA 也能拉取；官方用 `CMDS(git hash:123,branch:456,build time:Jun  8 2026 14:15:11)`）：

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:1
#EXTINF:8.000000, no desc
https://playback01-sx02.jtzs.sn.chinamobile.com:9443/playback/{macId}/{epoch秒}.ts?token={每段独立}&session={session}
...
#EXT-X-ENDLIST
```

### 4. 播放分段

`GET https://playback01-.../playback/{macId}/{epoch}.ts?token=...&session=...` 返回 MPEG-TS。实测视频为 **HEVC 2304x1296（16:9）**，音频 AAC。

### 5. 边界与可靠性经验

- **片段窗口必须对齐分段**：分段 URL 文件名是截断的整秒（`1786095548.ts`），但真实分段起止带毫秒（如 `5548664~5565664`）。直接用整秒算窗口会让服务器偶发返回 `10501 record not exist`。正确做法：播放窗口 **±2 秒补齐**，并夹紧到当天会话返回的 `start`/`end` 区间内。
- `createPlayback` 偶发返回 **200 空 body**（瞬时故障），客户端应重试一次（换新 nonce 重新签名）。
- 会话有过期时间（`expire`，约 15 分钟）；切换片段建议重新创建会话而不是复用旧 URL。

## 四、调试经验（踩坑记录）

### 1. "左右黑边"（直播画面变窄）

排查过程：用 Python 抓取直播流与云录像流，解析 TS 里的 SPS，两者都是 **2304x1296（16:9）**——流的宽高比没有变化；播放器配置、IJK 二进制与回放路径完全一致（回放无黑边），最终定位是**页面布局**：在非滚动 VStack 里新增一个全宽入口卡片，把 16:9 播放框的可用高度挤爆，SwiftUI 压缩播放框导致左右留黑。修复：入口卡片改为并排布局，页面高度恢复原状。

教训：同样的画面问题，先做**二分排除**（对比不同内容源/路径，实测流内容），再怀疑布局/配置，不要只凭直觉猜播放器。

### 2. "内嵌黑屏、全屏正常"

单例播放器（一个 `IJKFFMoviePlayerController` 实例）只能挂到一个 surface。云回放时 `streamURL` 指向 m3u8 且 `isReplay=false`，被导航栈压在下面的**直播页播放框条件也成立**，两个 surface 抢播放器——视频渲染到了看不见的直播页宿主上。点全屏后全屏宿主挂载并抢走播放器视图，于是"全屏正常"。

修复：直播页播放框条件排除云回放状态（`!isCloudReplay`）。内存卡回放一直正常是因为它 `isReplay=true` 天然排除。

### 3. 签名校验错误（SIGN_ERROR）

- `createPlayback`：参数必须全在 query 且全参与签名、body 为空；签名后的参数要**真正拼进 URL**（曾只计算签名忘记拼接，服务器报 SIGN_ERROR）。
- 告警类接口（`getAlarmList` 等）走的是 **UniApp 层 EventSign 签名**（header `EventSign` + query `sign`，规则与 video_sign 不同），尚未破解，云回放未依赖它；日历接口与标准规则一致。

### 4. 解析 TS 流获取分辨率

抓包分析流内容时的要点：PAT/PMT 是 PSI 表（pointer_field 开头，**没有** `00 00 01` 起始码）；PES 负载可能跨 TS 包，SPS 需要按 PID 重组完整 ES 后再解析；HEVC 的 SPS（NAL type 33，起始码后 `42 01`）解析前要**去掉防竞争字节**（`00 00 03` → `00 00`）。

## 五、实现位置（iOS 工程）

- `AijiaAPI.swift`：`cloudCalendar` / `createCloudPlayback`（含重试）/ `cloudPlaylist`（m3u8 解析）/ `fetchCloudTS`。
- `PlayerViewModel.swift`：`loadCloudDays` / `loadCloudSegments`（按天建会话、分段合并成片段）/ `playCloudClip`（窗口补齐+夹紧）/ `stopCloudReplay`（自动恢复实时流）。
- `ContentView.swift`：`CloudReplayView`（30 天日期条 + 片段列表 + 内嵌播放器）。
- 参考脚本：`scripts/cloud_playback.py`（Python 全链路，可用于复现与排查）。
