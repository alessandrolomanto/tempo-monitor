# Dashboards

All dashboards are provisioned automatically. Open Grafana at `http://localhost:3000` (admin / admin).

## Key dashboards

| Dashboard | What it shows |
|---|---|
| **Tempo Chain** | Block height, block time, peers, txpool, RPC latency, resources. Use the Job/Instance dropdowns to filter. |
| **Validator Health** | Consensus layer: epoch state, DKG peers, voting rates, consensus latency histograms. |
| **RPC & Traefik** | RPC call rates and latency alongside Traefik request rate, response codes, and active connections. |
| **Faucet** | `tempo_fundAddress` call rate/latency/errors and faucet pathUSD balance. |

## Logs

Navigate to **Explore > Loki** and query by container:

```logql
{container="tempo-validator-0"}
{container="tempo-faucet"} |= "error"
```

## Traces

Navigate to **Explore > Tempo**. Traefik propagates the W3C `traceparent` header to RPC backends, so each request produces an end-to-end trace from the HTTP edge through the execution engine.

## Profiling

Profiling requires a Tempo image built with the `profiling` profile and extra features. From the `tempo` repo, first build the chef (dependency) stage, then the final image:

```bash
# 1. Build the chef stage
docker build \
  --build-arg RUST_PROFILE=profiling \
  --build-arg RUST_FEATURES="asm-keccak,jemalloc-prof,jemalloc-symbols,otlp,tracy" \
  --build-arg EXTRA_RUSTFLAGS="-C force-frame-pointers=yes" \
  --target builder \
  -t tempo-chef:profiling \
  -f Dockerfile.chef .

# 2. Build the tempo image
docker build \
  --build-arg CHEF_IMAGE=tempo-chef:profiling \
  --build-arg RUST_PROFILE=profiling \
  --build-arg RUST_FEATURES="asm-keccak,jemalloc-prof,jemalloc-symbols,otlp,tracy" \
  --build-arg EXTRA_RUSTFLAGS="-C force-frame-pointers=yes" \
  --target tempo \
  -t tempo:profiling \
  -f Dockerfile .
```

Navigate to **Explore > Pyroscope** and select a service to view eBPF CPU profiles and pprof heap profiles.

## Datasources

| Name | Type | Internal URL |
|---|---|---|
| Prometheus | prometheus | `http://prometheus:9090` |
| Loki | loki | `http://loki:3100` |
| Tempo | tempo | `http://grafana-tempo:3200` |
| Pyroscope | grafana-pyroscope | `http://pyroscope:4040` |
