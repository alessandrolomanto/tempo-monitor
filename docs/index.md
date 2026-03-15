# Quick Start

Spin up a local Tempo consensus network with full observability in under a minute.

## Prerequisites

- Docker >= 24.0 with Compose >= 2.20
- [just](https://github.com/casey/just) task runner
- 8 GB RAM minimum (16 GB recommended with monitoring)

## Start the network

```bash
git clone https://github.com/alessandrolomanto/tempo-monitor.git
cd tempo-monitor
cp .env.example .env

# Consensus only (validators + RPCs + faucet + Traefik)
just up

# Everything including observability (Grafana, Prometheus, Loki, Tempo, Pyroscope)
just up-all
```

## Verify it works

```bash
curl -s -X POST http://localhost \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

You should see an increasing block number.

## Endpoints

| Service | URL |
|---|---|
| JSON-RPC (load-balanced) | `http://localhost` (Traefik, port 80) |
| JSON-RPC (direct rpc-0) | `http://localhost:8545` |
| Faucet RPC | `http://localhost:8546` |
| Traefik dashboard | `http://localhost:8081` |
| Grafana | `http://localhost:3000` (admin/admin) |
| Prometheus | `http://localhost:9090` |

With [local DNS](local-dns.md) configured you can also use `http://rpc.tempo.local` and `http://faucet.tempo.local`.

## Commands

| Command | Description |
|---|---|
| `just up` | Start consensus network |
| `just up-all` | Start consensus + monitoring |
| `just down` | Stop all services |
| `just down-v` | Stop all services and volumes |
| `just logs [service]` | Tail logs (default: `validator-0`) |
| `just status` | Show service status |
| `just health` | Run health check |

## Next steps

1. [Interact with the chain](usage.md) — wallets, faucet, payments, memos
2. [View dashboards](dashboards.md) — Grafana panels and logs
3. [Set up local DNS](local-dns.md) (optional)
