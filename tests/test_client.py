import io
import os
import tempfile
import time
import unittest
import urllib.error
from unittest import mock

import client


class FakeResponse:
    def __init__(self, body, headers=None, status=200):
        self._body = io.BytesIO(body)
        self.headers = headers or {}
        self.status = status
        self.read_sizes = []

    def read(self, size):
        self.read_sizes.append(size)
        return self._body.read(size)

    def close(self):
        self._body.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False


class EndlessResponse(FakeResponse):
    def __init__(self):
        super().__init__(b"")

    def read(self, size):
        self.read_sizes.append(size)
        return b"x"


class LimitedHttpResponseTests(unittest.TestCase):
    def test_success_body_is_read_with_a_hard_limit(self):
        response = FakeResponse(b'{"version":"1.14"}', {"Content-Type": "application/json"})

        with mock.patch.object(client, "MAX_HTTP_RESPONSE_BYTES", 64), mock.patch.object(
            client._opener, "open", return_value=response
        ):
            result = client.http_request("http://127.0.0.1:9090", "/version", "")

        self.assertTrue(result["ok"])
        self.assertEqual(result["data"], {"version": "1.14"})
        self.assertTrue(response.read_sizes)
        self.assertLessEqual(max(response.read_sizes), 65)

    def test_oversized_success_body_is_rejected_at_the_read_source(self):
        response = FakeResponse(b"x" * 18)

        with mock.patch.object(client, "MAX_HTTP_RESPONSE_BYTES", 16), mock.patch.object(
            client._opener, "open", return_value=response
        ):
            result = client.http_request("http://127.0.0.1:9090", "/version", "")

        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 413)
        self.assertIn("16-byte limit", result["error"])
        self.assertEqual(response.read_sizes, [17])

    def test_continuous_success_body_stops_after_limit_plus_one_bytes(self):
        response = EndlessResponse()

        with mock.patch.object(client, "MAX_HTTP_RESPONSE_BYTES", 16), mock.patch.object(
            client._opener, "open", return_value=response
        ):
            result = client.http_request("http://127.0.0.1:9090", "/version", "")

        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 413)
        self.assertEqual(len(response.read_sizes), 17)
        self.assertEqual(response.read_sizes[-1], 1)

    def test_oversized_content_length_is_rejected_before_reading(self):
        response = FakeResponse(b"ignored", {"Content-Length": "17"})

        with mock.patch.object(client, "MAX_HTTP_RESPONSE_BYTES", 16), mock.patch.object(
            client._opener, "open", return_value=response
        ):
            result = client.http_request("http://127.0.0.1:9090", "/version", "")

        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 413)
        self.assertEqual(response.read_sizes, [])

    def test_oversized_http_error_body_is_also_rejected_with_bounded_reads(self):
        error_body = FakeResponse(b"e" * 18)
        http_error = urllib.error.HTTPError(
            "http://127.0.0.1:9090/version",
            500,
            "Server Error",
            {},
            error_body,
        )

        with mock.patch.object(client, "MAX_HTTP_RESPONSE_BYTES", 16), mock.patch.object(
            client._opener, "open", side_effect=http_error
        ):
            result = client.http_request("http://127.0.0.1:9090", "/version", "")

        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 413)
        self.assertIn("16-byte limit", result["error"])
        self.assertEqual(error_body.read_sizes, [17])


@unittest.skipUnless(os.name == "posix", "PTY log capture is POSIX-only")
class LimitedLogCaptureTests(unittest.TestCase):
    def test_continuous_log_stream_is_bounded_by_size_and_time(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fake_sing_box = os.path.join(temp_dir, "sing-box")
            with open(fake_sing_box, "w", encoding="utf-8") as executable:
                executable.write(
                    "#!/usr/bin/env python3\n"
                    "import os\n"
                    "while True:\n"
                    "    os.write(1, b'INFO[1] continuous log line\\n')\n"
                )
            os.chmod(fake_sing_box, 0o700)

            started = time.monotonic()
            with mock.patch.dict(
                os.environ, {"PATH": temp_dir + os.pathsep + os.environ.get("PATH", "")}
            ), mock.patch.object(client, "MAX_LOG_CAPTURE_BYTES", 256), mock.patch.object(
                client, "MAX_LOG_CAPTURE_SECONDS", 0.5
            ):
                result = client.get_logs("http://127.0.0.1:9091", "")
            elapsed = time.monotonic() - started

        self.assertTrue(result["online"])
        self.assertLess(elapsed, 1.5)
        captured_bytes = sum(len(entry["raw"].encode("utf-8")) + 1 for entry in result["logs"])
        self.assertLessEqual(captured_bytes, 256)


if __name__ == "__main__":
    unittest.main()
