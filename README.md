# Tempo Monitor + MPP

A local [Tempo](https://tempo.xyz) consensus development network with full observability and a built-in [Machine Payments Protocol](https://mpp.dev) demo -- 4 validators, 2 RPC followers, a faucet node, Traefik load balancer, an MPP-gated API server, and an optional monitoring stack (Grafana, Prometheus, Loki, Tempo, Pyroscope).

## Prerequisites

- Docker >= 24.0 with Compose >= 2.20
- [just](https://github.com/casey/just) task runner
- 8 GB RAM minimum (16 GB recommended with monitoring)

## Quick Start

```bash
git clone https://github.com/alessandrolomanto/tempo-monitor.git
cd tempo-monitor
cp .env.example .env
just up              # consensus + monitoring
just up-consensus    # consensus only
just up-mpp          # consensus + MPP demo
```

## MPP Demo

The `mpp-demo` service runs a payment-gated API on the local devnet using the [Machine Payments Protocol](https://mpp.dev). Clients pay 0.01 pathUSD per request using TIP-20 stablecoin transfers settled on-chain in ~500ms.

```bash
# Start the devnet + MPP server
just up-mpp

# Fund a test account
curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tempo_fundAddress","params":["0x6C1CF016cB69fFf3e3b29a23326274660038045e"],"id":1}'

# Make a paid request
cd mpp-demo
MPPX_PRIVATE_KEY=$BOB_PK npx mppx http://localhost:3030/api/joke --rpc-url http://localhost:8545
```

See the [MPP documentation](docs/mpp.md) for the full setup, architecture, and troubleshooting guide.

## Endpoints

| Service | URL |
|---|---|
| JSON-RPC (load-balanced) | `http://localhost` or `http://rpc.tempo.local` |
| Faucet RPC | `http://localhost:8546` or `http://faucet.tempo.local` |
| MPP demo API | `http://localhost:3030` |
| Traefik dashboard | `http://localhost:8081` |
| Grafana | `http://localhost:3000` (admin/admin) |
| Prometheus | `http://localhost:9090` |

## Docker Compose profiles

| Profile | Services | Command |
|---|---|---|
| `consensus` | Validators, RPCs, faucet, health sidecars, Traefik | `just up-consensus` |
| `monitoring` | Grafana, Prometheus, Loki, Tempo, Pyroscope, Alloy | `just up` |
| `mpp` | MPP demo API server | `just up-mpp` |

## Documentation

Run `just docs` for the full docs site, or browse directly:

- [Quick Start](docs/index.md)
- [Local DNS](docs/local-dns.md)
- [Interact with the Chain](docs/usage.md)
- [MPP Demo](docs/mpp.md)
- [Dashboards](docs/dashboards.md)
