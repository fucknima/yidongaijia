#!/usr/bin/env python3
"""Expose a stable local HTTP stream for a China Mobile Aijia camera."""

from __future__ import annotations

import hashlib
import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


BASE_LOGIN_URL = "https://base.hjq.komect.com/base/user/passwdLogin"
VIDEO_LOGIN_URL = "https://video.komect.com/user/login/loginByHJQToken"
CAMERA_LIST_URL = "https://video.komect.com/camera/core/api/bind/queryList"
CAMERA_TOKEN_URL = "https://video.komect.com/camera/auth/getToken"
VIDEO_SIGN_KEY = "r8rw4d1kjwqgqqto9dwsq3ew0ip2np1b"
CLIENT_HEADERS = {
    "AppName": "hejiaqin",
    "DeviceId": "abc",
    "DeviceType": "ANDROID",
    "Version": "6.11.1",
}
LOG = logging.getLogger("aijia-bridge")


class ApiError(RuntimeError):
    pass


def md5(value: str) -> str:
    return hashlib.md5(value.encode("utf-8")).hexdigest()


def sha1(value: str) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()


def video_sign(params: dict[str, str], url: str) -> str:
    text = "".join(key + params[key] for key in sorted(params))
    text += urllib.parse.urlparse(url).path + VIDEO_SIGN_KEY
    return md5(text)


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    data: bytes | None = None,
    timeout: int = 20,
) -> tuple[dict[str, Any], Any]:
    request = urllib.request.Request(
        url,
        data=data,
        headers=headers or {},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return payload, response.headers
    except urllib.error.HTTPError as exc:
        raise ApiError(f"HTTP {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise ApiError(f"request failed: {type(exc).__name__}") from exc


def require_data(payload: dict[str, Any], action: str) -> Any:
    if "data" not in payload or payload["data"] is None:
        message = str(payload.get("msg") or payload.get("message") or "unknown error")
        raise ApiError(f"{action}: {message}")
    return payload["data"]


def normalize(value: Any) -> str:
    return "".join(char.lower() for char in str(value) if char.isalnum())


class AijiaClient:
    def __init__(self, phone: str, password: str, camera_selector: str = "") -> None:
        self.phone = phone
        self.password = password
        self.camera_selector = normalize(camera_selector)
        self.hjq_token = ""
        self.pass_id = ""
        self.video_token = ""
        self.camera: dict[str, Any] | None = None
        self.live_url = ""
        self.last_error = ""
        self.lock = threading.RLock()

    def _login_base(self) -> None:
        body = json.dumps(
            {
                "virtualAuthdata": md5(self.password),
                "authType": "10",
                "userAccount": self.phone,
                "authdata": sha1("fetion.com.cn:" + self.password),
            }
        ).encode("utf-8")
        payload, headers = request_json(
            BASE_LOGIN_URL,
            method="POST",
            headers={"Content-Type": "application/json"},
            data=body,
        )
        data = require_data(payload, "Aijia login")

        cookie_headers = headers.get_all("Set-Cookie") or []
        cookie_value = ""
        for header in cookie_headers:
            first_part = header.split(";", 1)[0]
            if "=" in first_part:
                cookie_value = first_part.split("=", 1)[1]
                if cookie_value:
                    break
        if not cookie_value or not data.get("passId"):
            raise ApiError("Aijia login did not return a usable token")

        self.hjq_token = cookie_value
        self.pass_id = str(data["passId"])

    def _login_video(self) -> None:
        if not self.hjq_token:
            self._login_base()
        timestamp = str(int(time.time() * 1000))
        params = {
            "HJQToken": self.hjq_token,
            "nonce": timestamp + "abcde",
            "passId": self.pass_id,
            "time": timestamp,
            "userId": self.phone,
        }
        params["sign"] = video_sign(params, VIDEO_LOGIN_URL)
        headers = CLIENT_HEADERS | {"Content-Type": "application/x-www-form-urlencoded"}
        payload, _ = request_json(
            VIDEO_LOGIN_URL,
            method="POST",
            headers=headers,
            data=urllib.parse.urlencode(params).encode("ascii"),
        )
        data = require_data(payload, "video login")
        token = data.get("token")
        if not token:
            raise ApiError("video login did not return a token")
        self.video_token = str(token)

    def _camera_list(self) -> list[dict[str, Any]]:
        if not self.video_token:
            self._login_video()
        timestamp = str(int(time.time() * 1000))
        params = {
            "nonce": timestamp + "m5kjt",
            "number": "100",
            "page": "1",
            "time": timestamp,
            "user_id": self.phone,
        }
        params["sign"] = video_sign(params, CAMERA_LIST_URL)
        url = CAMERA_LIST_URL + "?" + urllib.parse.urlencode(params)
        headers = CLIENT_HEADERS | {"AuthorizationToken": self.video_token}
        payload, _ = request_json(url, headers=headers)
        cameras = require_data(payload, "camera list")
        if not isinstance(cameras, list) or not cameras:
            raise ApiError("camera list is empty")
        return cameras

    def _select_camera(self, cameras: list[dict[str, Any]]) -> dict[str, Any]:
        if not self.camera_selector:
            return cameras[0]

        fields = ("mac_id", "mac_addr", "mac_name", "cmei", "device_id", "sn")
        for camera in cameras:
            if any(normalize(camera.get(field, "")) == self.camera_selector for field in fields):
                return camera
        raise ApiError("configured camera ID was not found in this account")

    def _get_device_jwtoken(self, camera: dict[str, Any]) -> str:
        jwt = str(camera.get("jwtoken", ""))
        if jwt:
            return jwt

        mac_id = str(camera.get("mac_id", ""))
        if not mac_id or not self.video_token:
            raise ApiError("camera record is missing device credentials")

        timestamp = str(int(time.time() * 1000))
        params = {
            "macId": mac_id,
            "nonce": str(100000 + int(timestamp) % 900000),
            "time": timestamp,
        }
        params["sign"] = video_sign(params, CAMERA_TOKEN_URL)
        headers = CLIENT_HEADERS | {"AuthorizationToken": self.video_token}
        payload, _ = request_json(
            CAMERA_TOKEN_URL + "?" + urllib.parse.urlencode(params),
            headers=headers,
        )
        token_data = payload.get("data")
        if isinstance(token_data, dict):
            jwt = str(token_data.get("jwtoken", ""))
        else:
            jwt = str(payload.get("jwtoken", ""))
        if not jwt:
            message = str(payload.get("msg") or payload.get("message") or "unknown error")
            raise ApiError(f"device token: {message}")

        camera["jwtoken"] = jwt
        return jwt

    def _get_live_url(self, camera: dict[str, Any]) -> str:
        base_url = str(camera.get("baseUrl", "")).rstrip("/")
        mac_id = str(camera.get("mac_id", ""))
        if not base_url or not mac_id:
            raise ApiError("camera record is missing stream credentials")
        jwt = self._get_device_jwtoken(camera)

        url = base_url + "/dcs/device/getLiveAddress"
        timestamp = str(int(time.time() * 1000))
        params = {
            "macId": mac_id,
            "nonce": timestamp + "gs08t",
            "requestTime": timestamp,
            "time": timestamp,
        }
        params["sign"] = video_sign(params, url)
        headers = CLIENT_HEADERS | {
            "AuthorizationToken": self.video_token,
            "AuthorizationJwtoken": jwt,
        }
        payload, _ = request_json(url + "?" + urllib.parse.urlencode(params), headers=headers)
        data = require_data(payload, "live address")
        live_url = data.get("flv")
        if not live_url:
            raise ApiError("live address response did not contain FLV")
        return str(live_url)

    def open_stream(self) -> Any:
        with self.lock:
            for attempt in range(2):
                try:
                    if not self.live_url:
                        if not self.camera:
                            self.camera = self._select_camera(self._camera_list())
                        self.live_url = self._get_live_url(self.camera)
                    request = urllib.request.Request(
                        self.live_url,
                        headers={"User-Agent": "aijia-bridge/1.0"},
                    )
                    upstream = urllib.request.urlopen(request, timeout=30)
                    self.last_error = ""
                    return upstream
                except Exception as exc:
                    self.live_url = ""
                    if attempt == 0:
                        self.hjq_token = ""
                        self.pass_id = ""
                        self.video_token = ""
                        self.camera = None
                        continue
                    self.last_error = str(exc)
                    raise
        raise ApiError("unable to open stream")

    def invalidate_stream(self) -> None:
        with self.lock:
            self.live_url = ""

    def keep_alive(self) -> None:
        with self.lock:
            if not self.camera or not self.video_token:
                return
            base_url = str(self.camera.get("baseUrl", "")).rstrip("/")
            jwt = str(self.camera.get("jwtoken", ""))
            mac_id = str(self.camera.get("mac_id", ""))
            url = base_url + "/dcs/device/keepOpenLiveAddress"
            timestamp = str(int(time.time() * 1000))
            params = {
                "macId": mac_id,
                "nonce": timestamp + "gs08t",
                "time": timestamp,
            }
            params["sign"] = video_sign(params, url)
            headers = CLIENT_HEADERS | {
                "AuthorizationToken": self.video_token,
                "AuthorizationJwtoken": jwt,
                "Content-Type": "application/x-www-form-urlencoded",
            }
            request_json(
                url,
                method="POST",
                headers=headers,
                data=urllib.parse.urlencode(params).encode("ascii"),
            )

    @property
    def camera_name(self) -> str:
        with self.lock:
            return str((self.camera or {}).get("mac_name", ""))


class BridgeState:
    def __init__(self, client: AijiaClient, keepalive_seconds: int) -> None:
        self.client = client
        self.keepalive_seconds = keepalive_seconds
        self.active_clients = 0
        self.lock = threading.Lock()

    def change_clients(self, delta: int) -> None:
        with self.lock:
            self.active_clients += delta

    def client_count(self) -> int:
        with self.lock:
            return self.active_clients

    def keepalive_loop(self) -> None:
        while True:
            time.sleep(self.keepalive_seconds)
            if self.client_count() == 0:
                continue
            try:
                self.client.keep_alive()
            except Exception as exc:
                self.client.last_error = str(exc)
                LOG.warning("stream keepalive failed: %s", exc)


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: BridgeState) -> None:
        super().__init__(address, BridgeHandler)
        self.state = state


class BridgeHandler(BaseHTTPRequestHandler):
    server: BridgeServer

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == "/health":
            self._health()
        elif path == "/stream.flv":
            self._stream()
        else:
            self.send_error(404)

    def _health(self) -> None:
        client = self.server.state.client
        payload = json.dumps(
            {
                "status": "ok",
                "active_clients": self.server.state.client_count(),
                "camera": client.camera_name,
                "stream_ready": bool(client.live_url),
                "last_error": client.last_error,
            },
            ensure_ascii=False,
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _stream(self) -> None:
        state = self.server.state
        state.change_clients(1)
        response_started = False
        try:
            with state.client.open_stream() as upstream:
                content_type = upstream.headers.get("Content-Type", "video/x-flv")
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                response_started = True
                while chunk := upstream.read(64 * 1024):
                    self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            LOG.error("stream proxy failed: %s", exc)
            if not response_started and not self.wfile.closed:
                try:
                    self.send_error(502)
                except (BrokenPipeError, ConnectionResetError):
                    pass
        finally:
            state.client.invalidate_stream()
            state.change_clients(-1)

    def log_message(self, format_string: str, *args: Any) -> None:
        LOG.debug(format_string, *args)


def env_required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"missing required environment variable: {name}")
    return value


def main() -> None:
    logging.basicConfig(
        level=os.getenv("AIJIA_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    phone = env_required("AIJIA_PHONE")
    password = env_required("AIJIA_PASSWORD")
    selector = os.getenv("AIJIA_CAMERA_ID", "")
    listen = os.getenv("AIJIA_LISTEN", "127.0.0.1")
    port = int(os.getenv("AIJIA_PORT", "18080"))
    keepalive = int(os.getenv("AIJIA_KEEPALIVE_SECONDS", "20"))

    state = BridgeState(AijiaClient(phone, password, selector), keepalive)
    threading.Thread(target=state.keepalive_loop, daemon=True).start()
    server = BridgeServer((listen, port), state)
    LOG.info("bridge listening on http://%s:%d", listen, port)
    server.serve_forever()


if __name__ == "__main__":
    main()
