#!/usr/bin/env python3
"""
Timestamp-based health-check server for tempo-monitor RPC sidecars.
Reads configuration from environment variables (no args needed at runtime).
"""
import json, os, time, http.server, socketserver, urllib.request

RPC_URL        = os.environ.get("RPC_URL",         "http://localhost:8545")
LEADER_URL     = os.environ.get("LEADER_URL",      "")
MAX_AGE_SECS   = int(os.environ.get("MAX_AGE_SECS",    "30"))
MAX_DRIFT_SECS = int(os.environ.get("MAX_DRIFT_SECS",  "30"))
HEALTH_PORT    = int(os.environ.get("HEALTH_PORT",     "8080"))

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
        if self.path != "/health":
            self.send_error(404); return
        ok, reason = check()
        self.send_response(200 if ok else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(reason.encode("utf-8"))
    def log_message(self, *args): pass

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    s = Server(("0.0.0.0", HEALTH_PORT), Handler)
    print(f"Listening 0.0.0.0:{HEALTH_PORT}  RPC={RPC_URL}  LEADER={LEADER_URL or '-'}  MAX_AGE={MAX_AGE_SECS}s  MAX_DRIFT={MAX_DRIFT_SECS}s", flush=True)
    s.serve_forever()
