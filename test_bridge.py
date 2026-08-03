import io
import unittest
import urllib.parse
from types import SimpleNamespace
from unittest.mock import Mock, patch

import bridge


class BridgeTests(unittest.TestCase):
    def test_video_sign_is_stable(self):
        params = {"time": "2", "macId": "A", "nonce": "1"}
        self.assertEqual(
            bridge.video_sign(params, "https://example.test/dcs/device/getLiveAddress"),
            "7ce189139ad78c666484b579604b08c6",
        )

    def test_normalize_camera_id(self):
        self.assertEqual(bridge.normalize("F8:73-1A"), "f8731a")

    def test_selects_requested_camera(self):
        client = bridge.AijiaClient("phone", "password", "AA:BB:CC")
        cameras = [
            {"mac_id": "11:22:33", "mac_name": "first"},
            {"mac_id": "AA-BB-CC", "mac_name": "second"},
        ]
        self.assertEqual(client._select_camera(cameras)["mac_name"], "second")

    def test_first_camera_is_default(self):
        client = bridge.AijiaClient("phone", "password")
        cameras = [{"mac_id": "one"}, {"mac_id": "two"}]
        self.assertEqual(client._select_camera(cameras)["mac_id"], "one")

    @patch("bridge.request_json")
    def test_keepalive_does_nothing_before_stream(self, request_json):
        client = bridge.AijiaClient("phone", "password")
        client.keep_alive()
        request_json.assert_not_called()

    @patch("bridge.request_json")
    def test_live_url_fetches_missing_device_token(self, request_json):
        request_json.side_effect = [
            ({"jwtoken": "device-token"}, {}),
            ({"data": {"flv": "https://stream.test/live"}}, {}),
        ]
        client = bridge.AijiaClient("phone", "password")
        client.video_token = "user-token"
        camera = {
            "baseUrl": "https://camera-api.test",
            "jwtoken": "",
            "mac_id": "camera-id",
        }

        self.assertEqual(client._get_live_url(camera), "https://stream.test/live")
        self.assertEqual(camera["jwtoken"], "device-token")

        token_url = request_json.call_args_list[0].args[0]
        token_query = urllib.parse.parse_qs(urllib.parse.urlparse(token_url).query)
        self.assertEqual(token_query["macId"], ["camera-id"])
        self.assertIn("nonce", token_query)
        self.assertIn("time", token_query)
        self.assertIn("sign", token_query)
        self.assertEqual(
            request_json.call_args_list[0].kwargs["headers"]["AppName"],
            "hejiaqin",
        )
        self.assertEqual(
            request_json.call_args_list[1].kwargs["headers"]["AuthorizationJwtoken"],
            "device-token",
        )

    def test_stream_proxy_invalidates_cached_address_when_upstream_ends(self):
        upstream = io.BytesIO(b"stream-data")
        upstream.headers = {"Content-Type": "video/MP2T"}
        client = Mock()
        client.open_stream.return_value = upstream
        state = bridge.BridgeState(client, keepalive_seconds=20)
        handler = bridge.BridgeHandler.__new__(bridge.BridgeHandler)
        handler.server = SimpleNamespace(state=state)
        handler.wfile = io.BytesIO()
        handler.send_response = Mock()
        handler.send_header = Mock()
        handler.end_headers = Mock()

        handler._stream()

        client.invalidate_stream.assert_called_once_with()
        self.assertEqual(state.client_count(), 0)


if __name__ == "__main__":
    unittest.main()
