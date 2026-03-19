#!/usr/bin/env python3
"""
RPC node health check server for tempo-monitor.

Exposes GET /health which:
  - Queries eth_blockNumber from the local RPC node
  - Compares against the leader node (rpc-0 → validator-0)
  - Returns 200 if block height is within MAX_BLOCK_DIFF of leader
  - Returns 503 if lagging or unreachable

Traefik uses this to keep lagging RPC nodes out of the load-balancer pool.
"""

import http.server
import json
import os
import socketserver
import threading
import urllib.error
import urllib.request

# ── Config ────────────────────────────────────────────────────────────
RPC_URL     = os.environ.get("RPC_URL",      "http://localhost:8545")
LEADER_URL  = os.environ.get("LEADER_URL",   "http://tempo-validator-0:8545")
MAX_BLOCK_DIFF = int(os.environ.get("MAX_BLOCK_DIFF", "5"))
HEALTH_PORT = int(os.environ.get("HEALTH_PORT", "8080"))
# ─────────────────────────────────────────────────────────────────────

def rpc_call(url: str, method: str, params: list = None) -> dict | None:
    """Make a JSON-RPC 2.0 POST and return the parsed response body, or None on error."""
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
            return json.loads(resp.read())   # {jsonrpc, id, result}
    except Exception:
        return None


def get_block_height(url: str) -> int | None:
    """Return the current block height (int) from url, or None on failure."""
    result = rpc_call(url, "eth_blockNumber")
    if result and result.get("result"):
        try:
            return int(result["result"], 16)
        except ValueError:
            pass
    return None


def is_synced() -> bool:
    """
    Return True when this node is close enough to the chain tip.

    Strategy:
      1. Check eth_syncing on the local node — if False, it's fully caught up.
      2. Fall back: compare local block height vs leader (rpc-0 → validator-0).
         Mark unhealthy if more than MAX_BLOCK_DIFF behind.
    """
    # Fast path: local node reports fully synced
    syncing_result = rpc_call(RPC_URL, "eth_syncing")
    if syncing_result is not None:
        val = syncing_result.get("result")
        # "false" means NOT syncing → fully in sync
        if val is False:
            return True
        # Otherwise it could be an object describing sync progress — fall through

    # Slow path: compare block heights
    local  = get_block_height(RPC_URL)
    leader = get_block_height(LEADER_URL)

    if local is None:
        return False          # local RPC is down → unhealthy
    if leader is None:
        return True           # leader unreachable; don't penalise this node

    diff = leader - local
    return diff <= MAX_BLOCK_DIFF


class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/health":
            self.send_error(404, "Not Found")
            return

        if is_synced():
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(503)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"UNHEALTHY")

    # Silence request-noise in logs
    def log_message(self, format, *args):  # noqa: ARG002
        pass


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Allow multiple concurrent health-check requests."""
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    server = ThreadedServer(("0.0.0.0", HEALTH_PORT), HealthHandler)
    print(f"Health check server listening on 0.0.0.0:{HEALTH_PORT}", flush=True)
    print(f"  RPC_URL     = {RPC_URL}", flush=True)
    print(f"  LEADER_URL  = {LEADER_URL}", flush=True)
    print(f"  MAX_BLOCK_DIFF = {MAX_BLOCK_DIFF}", flush=True)
    server.serve_forever()
