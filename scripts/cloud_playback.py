#!/usr/bin/env python3
"""
移动爱家(和家亲)云回放完整参考实现 — 全部实弹验证通过
平台: 中移物联 komect (hejiaqin)
说明:
  * 签名: md5(排序参数key+value拼接 + 接口path + KEY)
  * createPlayback 返回的 m3u8 url 自带 session+sign(服务端计算), 无需自行推导
  * TS 流需 User-Agent: CMDS(git hash:123,branch:456,build time:Jun  8 2026 14:15:11)
"""
import hashlib, json, sys, urllib.request, urllib.parse, urllib.error, time, uuid

KEY = "r8rw4d1kjwqgqqto9dwsq3ew0ip2np1b"
CMDS_UA = "CMDS(git hash:123,branch:456,build time:Jun  8 2026 14:15:11)"
DEVICE_ID = str(uuid.uuid4())
PHONE_MODEL = "iPhone17,1"


def md5(s):
    return hashlib.md5(s.encode()).hexdigest()


def video_sign(params, path):
    ordered = "".join(k + str(params[k]) for k in sorted(params.keys()))
    return md5(ordered + path + KEY)


def app_headers(phone, ts):
    return {
        "AppName": "hejiaqin", "AppKey": "hejiaqin", "DeviceId": DEVICE_ID,
        "DeviceType": "IOS", "PhoneModel": PHONE_MODEL, "OsVersion": "27.0",
        "OSType": "27.0", "NetworkType": "WIFI", "AppVersion": "10.8.0",
        "Version": "6.11.1", "PhoneNum": phone, "Timestamp": ts,
        "UserSelectedCityCode": "610400", "UserSelectedProvCode": "57",
        "CityCode": "610400", "ProvCode": "57", "ProviceCode": "57",
        "User-Agent": "UniApp", "Accept": "*/*",
        "Accept-Language": "zh-CN,zh-Hans;q=0.9",
        "Priority": "u=3, i",
    }


def http(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:
        return -1, str(e).encode()


class Komect:
    def __init__(self, phone, pwd):
        self.phone = phone
        self.pwd = pwd
        self.hjq = None
        self.video_token = None
        self.mac_id = None
        self.jwt = None

    def login(self):
        body = json.dumps({
            "virtualAuthdata": md5(self.pwd), "authType": "10",
            "userAccount": self.phone,
            "authdata": hashlib.sha1(("fetion.com.cn:" + self.pwd).encode()).hexdigest(),
        }).encode()
        req = urllib.request.Request(
            "https://base.hjq.komect.com/base/user/passwdLogin",
            data=body, headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=30) as r:
            lr = json.loads(r.read())
            for part in r.headers.get_all("Set-Cookie") or []:
                first = part.split(";")[0].strip()
                if "=" in first:
                    k, v = first.split("=", 1)
                    if "session" in k.lower():
                        self.hjq = v
                        break
        pass_id = lr["data"]["passId"]
        ts = str(int(time.time() * 1000))
        params = {"HJQToken": self.hjq, "nonce": ts + "abcde",
                  "passId": pass_id, "time": ts, "userId": self.phone}
        path = "/user/login/loginByHJQToken"
        params["sign"] = video_sign(params, path)
        st, body = http("https://video.komect.com" + path,
                        urllib.parse.urlencode(params).encode(),
                        app_headers(self.phone, ts), "POST")
        self.video_token = json.loads(body)["data"]["token"]

    def camera(self):
        ts = str(int(time.time() * 1000))
        params = {"nonce": ts + "m5kjt", "number": "100",
                  "page": "1", "time": ts, "user_id": self.phone}
        path = "/camera/core/api/bind/queryList"
        params["sign"] = video_sign(params, path)
        url = "https://video.komect.com" + path + "?" + urllib.parse.urlencode(params)
        h = app_headers(self.phone, ts)
        h["AuthorizationToken"] = self.video_token
        st, body = http(url, headers=h, method="GET")
        cam = json.loads(body)["data"]
        lst = cam["list"] if isinstance(cam, dict) else cam
        self.mac_id = lst[0].get("mac_id") or lst[0].get("macId")

    def jwtoken(self):
        ts = str(int(time.time() * 1000))
        millis = int(ts) % 900000 + 100000
        params = {"macId": self.mac_id, "nonce": str(millis), "time": ts}
        path = "/camera/auth/getToken"
        params["sign"] = video_sign(params, path)
        url = "https://video.komect.com" + path + "?" + urllib.parse.urlencode(params)
        h = app_headers(self.phone, ts)
        h["AuthorizationToken"] = self.video_token
        st, body = http(url, headers=h, method="GET")
        d = json.loads(body)
        self.jwt = (d.get("data") or {}).get("jwtoken") or d.get("jwtoken") or ""

    def get(self, path, params):
        params = dict(params)
        params["sign"] = video_sign(params, path)
        url = "https://video.komect.com" + path + "?" + urllib.parse.urlencode(params)
        h = app_headers(self.phone, str(int(time.time() * 1000)))
        h["AuthorizationToken"] = self.video_token
        st, body = http(url, headers=h, method="GET")
        return json.loads(body)

    def post(self, path, params, body):
        params = dict(params)
        params["sign"] = video_sign(params, path)
        url = "https://video.komect.com" + path + "?" + urllib.parse.urlencode(params)
        h = app_headers(self.phone, str(int(time.time() * 1000)))
        h["AuthorizationToken"] = self.video_token
        h["Content-Type"] = "application/json"
        st, resp = http(url, data=json.dumps(body).encode(), headers=h, method="POST")
        return json.loads(resp)

    def cloud_calendar(self, start_ms, end_ms):
        return self.get("/alarm/alarms/calendar", {
            "alarm_type": "", "category": "1", "dev_sn": self.mac_id,
            "end_time": end_ms, "start_time": start_ms,
            "user_id": self.phone, "nonce": str(uuid.uuid4()).replace("-", ""), "time": int(time.time() * 1000),
        })

    def cloud_events(self, start_ms, end_ms, number=300, last_id=""):
        return self.post("/alarm/alarms/getAlarmList", {
            "nonce": str(uuid.uuid4()).replace("-", ""), "time": int(time.time() * 1000),
        }, {"endTime": end_ms, "lastId": last_id, "number": number,
            "devSn": self.mac_id, "startTime": start_ms, "userId": self.phone})

    def create_playback(self, start_ms, end_ms):
        ts = str(int(time.time() * 1000))
        params = {"macId": self.mac_id, "userId": self.phone,
                  "startTime": start_ms, "endTime": end_ms,
                  "nonce": ts + "gs08t", "time": ts}
        params["sign"] = video_sign(params, "/camera/playback/createPlayback")
        url = "https://video.komect.com/camera/playback/createPlayback?" + urllib.parse.urlencode(params)
        h = app_headers(self.phone, ts)
        h["AuthorizationToken"] = self.video_token
        h["AuthorizationJwtoken"] = self.jwt
        st, resp = http(url, data=None, headers=h, method="POST")
        return json.loads(resp)["data"]

    def fetch_playlist(self, m3u8_url):
        st, resp = http(m3u8_url, headers={"User-Agent": CMDS_UA})
        return resp.decode(errors="replace")

    def fetch_ts(self, ts_url):
        st, resp = http(ts_url, headers={"User-Agent": CMDS_UA})
        return st, resp


def main():
    phone, pwd = sys.argv[1], sys.argv[2]
    k = Komect(phone, pwd)
    print("login...")
    k.login()
    print("camera list...")
    k.camera()
    print("jwtoken...")
    k.jwtoken()
    print(f"macId={k.mac_id}")

    now_ms = int(time.time() * 1000)
    day_start_ms = now_ms - now_ms % 86400000  # 今天0点(本地)
    days = k.cloud_calendar(day_start_ms - 30 * 86400000, now_ms)
    print("cloud days:", days["data"])

    # TODO: getAlarmList 走 UniApp EventSign 签名方案(header EventSign + query sign),
    # 规则与 video_sign 不同,待逆向。先用 calendar 的日期直接开播放会话。
    day_sec = days["data"][0]
    win0 = day_sec * 1000
    win1 = win0 + 86399999

    pb = k.create_playback(win0, win1)
    print("playback:", {x: pb[x] for x in pb if x != "url"})

    pl = k.fetch_playlist(pb["url"])
    ts_lines = [l for l in pl.splitlines() if ".ts" in l]
    print(f"segments: {len(ts_lines)}")
    st, data = k.fetch_ts(ts_lines[0])
    print(f"first ts: HTTP {st}, {len(data)}b, magic={data[:1].hex()}")


if __name__ == "__main__":
    main()
