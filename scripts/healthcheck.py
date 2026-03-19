#!/usr/bin/env python3
"""
Health-check + reverse-proxy sidecar for tempo-monitor RPC nodes.

GET  /health  →  timestamp-based health check (responded locally)
*    /*       →  reverse-proxied to the real RPC node (RPC_URL)

This allows Traefik to use the sidecar as both a health-check target and
the backend for client traffic.
"""
import json, os, time, http.server, socketserver, urllib.request, urllib.error

RPC_URL        = os.environ.get("RPC_URL",        "http://localhost:8545")
LEADER_URL     = os.environ.get("LEADER_URL",     "")
MAX_AGE_SECS   = int(os.environ.get("MAX_AGE_SECS",   "30"))
MAX_DRIFT_SECS = int(os.environ.get("MAX_DRIFT_SECS", "30"))
HEALTH_PORT    = int(os.environ.get("HEALTH_PORT",    "8080"))

PROXY_HEADERS_DROP = frozenset(("host", "transfer-encoding"))

def rpc(method, url, params=None):
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params or []}).encode(),
            headers={"Content-Type":"application/json"},
            method="POST")
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()).get("result")
    except Exception:
        return None

def latest_block_timestamp(url):
    result = rpc("eth_getBlockByNumber", url, ["latest", False])
    if result and "timestamp" in result:
        try: return int(result["timestamp"], 16)
        except ValueError: pass
    return None

def check():
    now = time.time()
    local_ts = latest_block_timestamp(RPC_URL)
    if local_ts is None:
        return False, "local_rpc_unreachable"
    age = now - local_ts
    if age > MAX_AGE_SECS:
        return False, f"local_block_stale_{age:.0f}s"
    if LEADER_URL:
        leader_ts = latest_block_timestamp(LEADER_URL)
        if leader_ts is not None:
            drift = leader_ts - local_ts
            if drift > MAX_DRIFT_SECS:
                return False, f"drift_too_large_{drift:.0f}s"
            return True, f"ok_drift_{drift:.0f}s"
    return True, f"ok_age_{age:.0f}s"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._handle_health()
        else:
            self._proxy()

    def do_POST(self):
        self._proxy()

    def do_OPTIONS(self):
        self._proxy()

    def _handle_health(self):
        ok, reason = check()
        self.send_response(200 if ok else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(reason.encode("utf-8"))

    def _proxy(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else None

        headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in PROXY_HEADERS_DROP
        }

        req = urllib.request.Request(
            RPC_URL + self.path,
            data=body,
            headers=headers,
            method=self.command,
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp_body = resp.read()
                self.send_response(resp.status)
                for k, v in resp.getheaders():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(resp_body)
        except urllib.error.HTTPError as e:
            resp_body = e.read()
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in ("transfer-encoding", "connection"):
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(resp_body)
        except Exception:
            self.send_error(502, "Bad Gateway")

    def log_message(self, *args): pass

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    s = Server(("0.0.0.0", HEALTH_PORT), Handler)
    print(
        f"Listening 0.0.0.0:{HEALTH_PORT}  RPC={RPC_URL}  "
        f"LEADER={LEADER_URL or '-'}  MAX_AGE={MAX_AGE_SECS}s  "
        f"MAX_DRIFT={MAX_DRIFT_SECS}s",
        flush=True,
    )
    s.serve_forever()
