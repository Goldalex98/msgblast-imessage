"""Spike (e), preliminary: how the HomeChat edge answers a plain, non-browser client.

Run on the Mac by Alex after he adds "homechat_probe_url" to .local/spikes/config.json:
  python3 -I companion/spikes/reach.py
One GET, no redirects followed. Prints only the path of a report that never contains the URL.
"""
from __future__ import annotations

import argparse
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spikelib  # noqa: E402

USER_AGENT = "msgblast-imessage-spike/0"
ALLOWED = frozenset({"ok", "http", "dns", "tls", "timeout", "other", "cloudflare", "caddy", "none"})


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # urllib then raises HTTPError carrying the 3xx status and its headers


def no_redirect_opener() -> urllib.request.OpenerDirector:
    return urllib.request.build_opener(NoRedirect)


def _error_kind(error: BaseException) -> str:
    reason = error.reason if isinstance(error, urllib.error.URLError) else error
    if isinstance(reason, socket.gaierror):
        return "dns"
    if isinstance(reason, ssl.SSLError):
        return "tls"
    if isinstance(reason, (socket.timeout, TimeoutError)):
        return "timeout"
    return "other"


def _server_kind(server: Optional[str]) -> str:
    value = (server or "").strip().lower()
    if not value:
        return "none"
    if "cloudflare" in value:
        return "cloudflare"
    if "caddy" in value:
        return "caddy"
    return "other"


def probe_reach(url: str, timeout_s: float = 10.0, opener=None,
                clock: Callable[[], float] = time.monotonic) -> dict:
    if urllib.parse.urlsplit(url).scheme not in ("http", "https"):
        raise spikelib.ProbeError(4, "homechat_probe_url must be an http(s) URL")
    request = urllib.request.Request(url, method="GET", headers={"User-Agent": USER_AGENT})
    opener = opener or no_redirect_opener()
    status, hdrs, kind = None, None, "other"
    start = clock()
    try:
        response = opener.open(request, timeout=timeout_s)
        status, hdrs = response.status, response.headers
        response.close()
    except urllib.error.HTTPError as error:
        status, hdrs = error.code, error.headers
    except (urllib.error.URLError, OSError) as error:
        kind = _error_kind(error)
    elapsed_ms = int(round((clock() - start) * 1000))
    if status is not None:
        kind = "ok" if status < 400 else "http"
    get = hdrs.get if hdrs is not None else (lambda key, default=None: default)
    location_host = urllib.parse.urlsplit(get("Location") or "").hostname or ""
    return {
        "status": status,
        "error_kind": kind,
        "cf_ray": bool(get("CF-Ray")),
        "access_redirect": bool(status and 300 <= status < 400
                                and (location_host == "cloudflareaccess.com"
                                     or location_host.endswith(".cloudflareaccess.com"))),
        "server_kind": _server_kind(get("Server")),
        "elapsed_ms": elapsed_ms,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=None)
    args = parser.parse_args()
    url = spikelib.load_config(args.config).get("homechat_probe_url")
    if not url:
        raise spikelib.ProbeError(3, 'Add "homechat_probe_url" to .local/spikes/config.json first.')
    print(spikelib.write_report("reach", probe_reach(url), ALLOWED))
    return 0


if __name__ == "__main__":
    sys.exit(spikelib.run_main(main))
