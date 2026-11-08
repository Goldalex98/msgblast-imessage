from __future__ import annotations

import email.message
import json
import socket
import ssl
import sys
import unittest
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "companion/spikes"))

import reach  # noqa: E402
import spikelib  # noqa: E402

URL = "https://sentinel-host.example.invalid/probe"


def headers(**values) -> email.message.Message:
    message = email.message.Message()
    for key, value in values.items():
        message[key.replace("_", "-")] = value
    return message


class FakeResponse:
    def __init__(self, status, hdrs):
        self.status = status
        self.headers = hdrs

    def close(self):
        pass


class FakeOpener:
    def __init__(self, result):
        self.result = result
        self.requests = []

    def open(self, request, timeout=None):
        self.requests.append((request, timeout))
        if isinstance(self.result, BaseException):
            raise self.result
        return self.result


class ReachTests(unittest.TestCase):
    def probe(self, result):
        ticks = iter([100.0, 100.25])
        opener = FakeOpener(result)
        report = reach.probe_reach(URL, timeout_s=10.0, opener=opener, clock=lambda: next(ticks))
        return report, opener

    def test_ok_through_cloudflare(self):
        report, opener = self.probe(FakeResponse(200, headers(server="cloudflare", cf_ray="abc-EWR")))
        self.assertEqual(report, {"status": 200, "error_kind": "ok", "cf_ray": True, "access_redirect": False,
                                  "server_kind": "cloudflare", "elapsed_ms": 250})
        request, timeout = opener.requests[0]
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(request.get_header("User-agent"), "msgblast-imessage-spike/0")
        self.assertEqual(timeout, 10.0)

    def test_access_redirect(self):
        error = urllib.error.HTTPError(URL, 302, "Found",
                                       headers(location="https://team.cloudflareaccess.com/cdn-cgi/access/login",
                                               server="cloudflare", cf_ray="x"), None)
        report, _ = self.probe(error)
        self.assertEqual(report["status"], 302)
        self.assertTrue(report["access_redirect"])
        self.assertEqual(report["error_kind"], "ok")

    def test_http_error_and_caddy(self):
        report, _ = self.probe(urllib.error.HTTPError(URL, 403, "Forbidden", headers(server="Caddy"), None))
        self.assertEqual((report["status"], report["error_kind"], report["server_kind"]), (403, "http", "caddy"))
        self.assertFalse(report["access_redirect"])
        self.assertFalse(report["cf_ray"])

    def test_network_errors(self):
        cases = [
            (urllib.error.URLError(socket.timeout()), "timeout"),
            (socket.timeout(), "timeout"),
            (urllib.error.URLError(ssl.SSLError()), "tls"),
            (urllib.error.URLError(socket.gaierror(8, "nodename nor servname provided")), "dns"),
            (urllib.error.URLError(ConnectionRefusedError()), "other"),
        ]
        for error, kind in cases:
            report, _ = self.probe(error)
            self.assertEqual((report["status"], report["error_kind"], report["server_kind"]), (None, kind, "none"))

    def test_rejects_non_http_url(self):
        with self.assertRaises(spikelib.ProbeError):
            reach.probe_reach("file:///etc/passwd", opener=FakeOpener(FakeResponse(200, headers())))

    def test_default_opener_does_not_follow_redirects(self):
        opener = reach.no_redirect_opener()
        handler = next(h for h in opener.handlers if isinstance(h, reach.NoRedirect))
        self.assertIsNone(handler.redirect_request(None, None, 302, "Found", headers(), "https://elsewhere/"))

    def test_report_has_no_url(self):
        error = urllib.error.HTTPError(URL, 302, "Found", headers(location=URL + "/next"), None)
        for result in (FakeResponse(200, headers(server="sentinel-host")), error):
            report, _ = self.probe(result)
            dumped = json.dumps(report)
            self.assertNotIn("sentinel-host", dumped)
            self.assertNotIn("example.invalid", dumped)
            spikelib.assert_counts_only(report, reach.ALLOWED)


if __name__ == "__main__":
    unittest.main()
