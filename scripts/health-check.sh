#!/usr/bin/env bash
# Tempo node health check
# Usage: ./health-check.sh [RPC_URL]
set -euo pipefail

RPC_URL="${1:-http://localhost:8545}"
METRICS_URL="${METRICS_URL:-http://localhost:9090/-/healthy}"

# ── Colors ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  G='\033[0;32m' R='\033[0;31m' Y='\033[0;33m' B='\033[1m' D='\033[0;90m' N='\033[0m'
else
  G='' R='' Y='' B='' D='' N=''
fi

pass() { printf "  ${G}✔${N} %-30s %s\n" "$1" "$2"; }
fail() { printf "  ${R}✘${N} %-30s %s\n" "$1" "$2"; ERRORS=$((ERRORS + 1)); }
warn() { printf "  ${Y}⚠${N} %-30s %s\n" "$1" "$2"; }

ERRORS=0

printf "\n${B}Tempo Node Health Check${N}\n"
printf "RPC: %s\n" "$RPC_URL"
printf "%s\n\n" "$(printf '─%.0s' {1..60})"

if ! command -v curl &>/dev/null; then
  fail "curl" "not installed"; exit 1
fi

# ── Helper ───────────────────────────────────────────────────────────
rpc() {
  curl -sf -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":${2:-[]}}" \
    --connect-timeout 10 --max-time 10 2>/dev/null || true
}

hex2dec() { printf "%d" "$1" 2>/dev/null || echo "?"; }

jqr() {
  if command -v jq &>/dev/null; then
    echo "$1" | jq -r "$2" 2>/dev/null
  else
    echo "$1" | grep -o "\"result\":[^,}]*" | sed 's/"result"://' | tr -d '"'
  fi
}

# ── RPC ──────────────────────────────────────────────────────────────
BLOCK_RESP=$(rpc eth_blockNumber)
if [[ -n "$BLOCK_RESP" ]]; then
  pass "RPC reachable" "$RPC_URL"
  BLOCK_HEX=$(jqr "$BLOCK_RESP" '.result')
  if [[ -n "$BLOCK_HEX" && "$BLOCK_HEX" != "null" ]]; then
    pass "Block height" "$(hex2dec "$BLOCK_HEX")"
  else
    fail "Block height" "unexpected response"
  fi
else
  fail "RPC reachable" "$RPC_URL"
fi

# ── Metrics ──────────────────────────────────────────────────────────
if curl -sf --connect-timeout 3 --max-time 5 "$METRICS_URL" -o /dev/null 2>/dev/null; then
  pass "Metrics endpoint" "$METRICS_URL"
else
  fail "Metrics endpoint" "$METRICS_URL"
fi

# ── Peers ────────────────────────────────────────────────────────────
PEER_RESP=$(rpc net_peerCount)
if [[ -n "$PEER_RESP" ]]; then
  PEERS=$(hex2dec "$(jqr "$PEER_RESP" '.result')")
  if [[ "$PEERS" -ge 5 ]] 2>/dev/null; then
    pass "Peer count" "$PEERS"
  elif [[ "$PEERS" -gt 0 ]] 2>/dev/null; then
    warn "Peer count" "$PEERS (expected ≥5)"
  else
    warn "Peer count" "$PEERS"
  fi
else
  warn "Peer count" "unavailable"
fi

# ── Sync ─────────────────────────────────────────────────────────────
SYNC_RESP=$(rpc eth_syncing)
if [[ -n "$SYNC_RESP" ]]; then
  SYNC_VAL=$(jqr "$SYNC_RESP" '.result')
  if [[ "$SYNC_VAL" == "false" ]]; then
    pass "Sync status" "fully synced"
  else
    warn "Sync status" "syncing"
  fi
else
  fail "Sync status" "could not query"
fi

# ── Block Heights (all nodes) ────────────────────────────────────────
printf "\n${B}Block Heights${N}\n"
printf "%s\n" "$(printf '─%.0s' {1..60})"

EXEC_CONTAINER=""
for c in tempo-rpc-0-health tempo-rpc-1-health; do
  if docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
    EXEC_CONTAINER="$c"
    break
  fi
done

if [[ -z "$EXEC_CONTAINER" ]]; then
  warn "Block heights" "no health-check sidecar running, cannot query internal nodes"
else
  HEIGHTS_JSON=$(docker exec "$EXEC_CONTAINER" python3 -c "
import urllib.request, json, sys, concurrent.futures

nodes = [
    ('validator-0', 'http://10.0.0.1:8545'),
    ('validator-1', 'http://10.0.0.2:8545'),
    ('validator-2', 'http://10.0.0.3:8545'),
    ('validator-3', 'http://10.0.0.4:8545'),
    ('rpc-0',       'http://10.0.0.10:8545'),
    ('rpc-1',       'http://10.0.0.11:8545'),
    ('faucet',      'http://10.0.0.15:8545'),
]

def query(entry):
    name, url = entry
    try:
        req = urllib.request.Request(url,
            data=json.dumps({'jsonrpc':'2.0','id':1,'method':'eth_blockNumber','params':[]}).encode(),
            headers={'Content-Type':'application/json'}, method='POST')
        with urllib.request.urlopen(req, timeout=5) as r:
            res = json.loads(r.read()).get('result','')
            return name, int(res, 16) if res else -1
    except Exception:
        return name, -1

with concurrent.futures.ThreadPoolExecutor(max_workers=len(nodes)) as pool:
    results = dict(pool.map(query, nodes))

print(json.dumps(results))
" 2>/dev/null) || HEIGHTS_JSON=""

  if [[ -z "$HEIGHTS_JSON" ]]; then
    warn "Block heights" "failed to query nodes"
  else
    ORDERED_NODES="validator-0 validator-1 validator-2 validator-3 rpc-0 rpc-1 faucet"

    jq_height() { echo "$HEIGHTS_JSON" | jq -r ".\"$1\" // -1" 2>/dev/null || echo "-1"; }

    # Find highest validator height for drift calculation
    MAX_V=0
    for name in validator-0 validator-1 validator-2 validator-3; do
      h=$(jq_height "$name")
      if [[ "$h" -gt "$MAX_V" ]] 2>/dev/null; then MAX_V="$h"; fi
    done

    printf "  ${D}%-16s %10s %8s${N}\n" "NODE" "HEIGHT" "DRIFT"
    for name in $ORDERED_NODES; do
      h=$(jq_height "$name")
      if [[ "$h" == "-1" || -z "$h" ]]; then
        printf "  ${R}%-16s %10s %8s${N}\n" "$name" "down" "-"
        ERRORS=$((ERRORS + 1))
      else
        drift=$((MAX_V - h))
        if [[ "$drift" -eq 0 ]]; then
          printf "  ${G}%-16s %10d %8d${N}\n" "$name" "$h" "0"
        elif [[ "$drift" -le 5 ]]; then
          printf "  ${Y}%-16s %10d %7s${N}\n" "$name" "$h" "-${drift}"
        else
          printf "  ${R}%-16s %10d %7s${N}\n" "$name" "$h" "-${drift}"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done
  fi
fi

# ── Containers ───────────────────────────────────────────────────────
printf "\n${B}Containers${N}\n"
printf "%s\n" "$(printf '─%.0s' {1..60})"
if command -v docker &>/dev/null; then
  RUNNING=$(docker ps --filter "name=tempo-" --format "{{.Names}}: {{.Status}}" 2>/dev/null) || true
  if [[ -n "$RUNNING" ]]; then
    COUNT=$(echo "$RUNNING" | wc -l | tr -d ' ')
    pass "Containers" "$COUNT running"
    echo "$RUNNING" | while read -r line; do
      printf "    %s\n" "$line"
    done
  else
    fail "Containers" "no tempo-* containers found"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────
printf "\n%s\n" "$(printf '─%.0s' {1..60})"
if [[ "$ERRORS" -eq 0 ]]; then
  printf "${G}${B}All checks passed.${N}\n\n"
else
  printf "${R}${B}${ERRORS} check(s) failed.${N}\n\n"
  exit 1
fi
