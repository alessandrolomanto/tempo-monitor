#!/usr/bin/env bash
# Tempo node health check
# Usage: ./health-check.sh [RPC_URL]
set -euo pipefail

RPC_URL="${1:-http://localhost:8545}"
METRICS_URL="${METRICS_URL:-http://localhost:9090/-/healthy}"

# ── Colors ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  G='\033[0;32m' R='\033[0;31m' Y='\033[0;33m' B='\033[1m' N='\033[0m'
else
  G='' R='' Y='' B='' N=''
fi

pass() { printf "  ${G}✔${N} %-30s %s\n" "$1" "$2"; }
fail() { printf "  ${R}✘${N} %-30s %s\n" "$1" "$2"; ERRORS=$((ERRORS + 1)); }
warn() { printf "  ${Y}⚠${N} %-30s %s\n" "$1" "$2"; }

ERRORS=0

printf "\n${B}Tempo Node Health Check${N}\n"
printf "RPC: %s\n" "$RPC_URL"
printf "%s\n\n" "$(printf '─%.0s' {1..50})"

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

# jq with grep fallback
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

# ── Containers ───────────────────────────────────────────────────────
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
printf "\n%s\n" "$(printf '─%.0s' {1..50})"
if [[ "$ERRORS" -eq 0 ]]; then
  printf "${G}${B}All checks passed.${N}\n\n"
else
  printf "${R}${B}${ERRORS} check(s) failed.${N}\n\n"
  exit 1
fi
