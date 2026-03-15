# Tempo Monitor

A local [Tempo](https://tempo.xyz) consensus development network with full observability -- 4 validators, 2 RPC followers, a faucet node, Traefik load balancer, and an optional monitoring stack (Grafana, Prometheus, Loki, Tempo, Pyroscope).

## Prerequisites

- Docker >= 24.0 with Compose >= 2.20
- [just](https://github.com/casey/just) task runner
- 8 GB RAM minimum (16 GB recommended with monitoring)

## Quick Start

```bash
git clone https://github.com/alessandrolomanto/tempo-monitor.git
cd tempo-monitor
cp .env.example .env
just up          # consensus + monitoring
just up-consensus      # consensus only
```

See the full docs running `just docs` for local DNS setup, chain interaction guide, and dashboard reference.
## Endpoints

| Service | URL |
|---|---|
| JSON-RPC (load-balanced) | `http://localhost` or `http://rpc.tempo.local` |
| Faucet RPC | `http://localhost:8546` or `http://faucet.tempo.local` |
| Traefik dashboard | `http://localhost:8081` |
| Grafana | `http://localhost:3000` (admin/admin) |
| Prometheus | `http://localhost:9090` |

## Documentation

See the [full docs](docs/index.md) for local DNS setup, chain interaction guide, and dashboard reference.
