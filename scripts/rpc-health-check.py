#!/usr/bin/env python3
"""
Timestamp-based RPC node health check for tempo-monitor.

Logic (timestamp-based, not block-height):
  - Stale check : healthy if  now − latest_block.timestamp <= MAX_AGE_SECS
  - Drift check : healthy if  leader_block.timestamp − local_block.timestamp <= MAX_DRIFT_SECS

Usage:
  # Check a local node only (stale check)
  RPC_URL=http://localhost:8545 MAX_AGE_SECS=30 python3 rpc-health-check.py

  # Check a follower against a leader (stale + drift check)
  RPC_URL=http://localhost:8545 \
    LEADER_URL=http://validator-0:8545 \
    MAX_AGE_SECS=30 \
    MAX_DRIFT_SECS=30 \
    python3 rpc-health-check.py

  # Override port
  HEALTH_PORT=8080 python3 rpc-health-check.py

Traefik uses GET /health — returns 200=healthy, 503=unhealthy.
The body of the 503 response contains a human-readable reason.
"""

import http.server
import json
import os
import socketserver
import time
import urllib.error
import urllib.request

# ── Config ────────────────────────────────────────────────────────────
RPC_URL        = os.environ.get("RPC_URL",         "http://localhost:8545")
LEADER_URL     = os.environ.get("LEADER_URL",      "")   # empty = no drift check
MAX_AGE_SECS   = int(os.environ.get("MAX_AGE_SECS",    "30"))
MAX_DRIFT_SECS = int(os.environ.get("MAX_DRIFT_SECS",  "30"))
HEALTH_PORT    = int(os.environ.get("HEALTH_PORT",     "8080"))
# ─────────────────────────────────────────────────────────────────────


def rpc_call(url: str, method: str, params: list = None) -> dict | None:
    """Make a JSON-RPC 2.0 POST; return the parsed result or None on error."""
    payload = json.dumps({
        "jsonrpc": "2.0",
        "id":      1,
        "method":  method,
        "params":  params or [],
    }).encode()

    try:
        req = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception:
        return None


def latest_block_timestamp(url: str) -> float | None:
    """
    Return the Unix timestamp of the latest block at url, or None if unreachable.
    Tempo returns the timestamp as a hex string in seconds.
    """
    result = rpc_call(url, "eth_getBlockByNumber", ["latest", False])
    if result and result.get("result") and "timestamp" in result["result"]:
        try:
            return int(result["result"]["timestamp"], 16)
        except ValueError:
            pass
    return None


def check() -> tuple[bool, str]:
    """
    Returns (ok, reason).
      ok=True  → HTTP 200 (healthy)
      ok=False → HTTP 503 (unhealthy)
    """
    now = time.time()

    local_ts = latest_block_timestamp(RPC_URL)
    if local_ts is None:
        return False, "local_rpc_unreachable"

    # Stale check: block is too old
    age = now - local_ts
    if age > MAX_AGE_SECS:
        return False, f"local_block_stale_{age:.0f}s"

    # Drift check: follower is too far behind leader
    if LEADER_URL:
        leader_ts = latest_block_timestamp(LEADER_URL)
        if leader_ts is not None:
            drift = leader_ts - local_ts
            if drift > MAX_DRIFT_SECS:
                return False, f"drift_too_large_{drift:.0f}s"
            return True, f"ok_drift_{drift:.0f}s"

    return True, f"ok_age_{age:.0f}s"


class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/health":
            self.send_error(404, "Not Found")
            return

        ok, reason = check()

        if ok:
            self.send_response(200)
        else:
            self.send_response(503)

        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(reason.encode("utf-8"))

    def log_message(self, format, *args):  # noqa: ARG002
        pass


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    server = ThreadedServer(("0.0.0.0", HEALTH_PORT), HealthHandler)
    print(f"Health check server listening on 0.0.0.0:{HEALTH_PORT}", flush=True)
    print(f"  RPC_URL        = {RPC_URL}", flush=True)
    print(f"  LEADER_URL     = {LEADER_URL or '(none — stale check only)'}", flush=True)
    print(f"  MAX_AGE_SECS   = {MAX_AGE_SECS}", flush=True)
    print(f"  MAX_DRIFT_SECS = {MAX_DRIFT_SECS}", flush=True)
    server.serve_forever()
