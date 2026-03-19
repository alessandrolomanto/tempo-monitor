# Machine Payments Protocol (MPP)

The `mpp-demo` service demonstrates [MPP](https://mpp.dev) on the local devnet: a Hono API server gates endpoints behind pathUSD payments, and any MPP-compatible client (CLI, SDK, or agent) can pay and access them automatically.

## Architecture

```
Client (host)                     mpp-demo (:3030)             validator-0 (10.0.0.1)
     │                                  │                              │
     │── GET /api/joke ────────────────>│                              │
     │<── 402 + Challenge (0.01 pUSD) ──│                              │
     │                                  │                              │
     │── GET /api/joke + Credential ──>│                              │
     │                                  │── broadcast tx ────────────>│
     │                                  │<── confirmed (~500ms) ──────│
     │<── 200 + Receipt + data ────────│                              │
```

The server runs as a Docker container on the same network as the Tempo nodes (`10.0.0.40`), broadcasting transactions to validator-0 via internal IP. Clients on the host reach the server through the exposed port `3030`.

## Quick start

```bash
# Start the devnet + MPP demo
just up-mpp

# Wait for blocks (~10s), then fund the test account
curl -s -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tempo_fundAddress","params":["0x6C1CF016cB69fFf3e3b29a23326274660038045e"],"id":1}'

# Verify the server is running
curl http://localhost:3030/api/ping
```

## Endpoints

| Endpoint | Method | Cost | Description |
|---|---|---|---|
| `/api/ping` | GET | Free | Health check |
| `/api/joke` | GET | 0.01 pathUSD | Payment-gated joke |

## Making paid requests

### With the mppx CLI

Install `mppx` and make a paid request using BOB's private key:

```bash
cd mpp-demo

MPPX_PRIVATE_KEY=$BOB_PK \
npx mppx http://localhost:3030/api/joke --rpc-url http://localhost:8545 -v
```

Expected output:

```
Payment Required
  amount     10000 (0.01 PathUSD)
  chainId    1337
  feePayer   true

Payment Receipt
  reference  0x562a6d19ade1...
  status     success

{"joke":"Why do programmers prefer dark mode? Because light attracts bugs."}
```

### With the programmatic client

```bash
cd mpp-demo
BOB_PK=$BOB_PK bun run client.ts
```

```
Status: 200
Receipt: yes
Body: { joke: "Why do programmers prefer dark mode? Because light attracts bugs." }
```

### With curl (inspect the 402)

```bash
curl -i http://localhost:3030/api/joke
```

Returns `402 Payment Required` with a `WWW-Authenticate` header containing the payment challenge (amount, currency, chain ID, recipient).

## Environment variables

The `.envrc` provides `BOB_PK` and `MPPX_PRIVATE_KEY` for convenience. If you use `direnv`, they load automatically.

| Variable | Used by | Description |
|---|---|---|
| `MPPX_PRIVATE_KEY` | mppx CLI | Private key for signing payment transactions |
| `MPPX_RPC_URL` | mppx CLI | RPC endpoint for the client (`http://localhost:8545`) |
| `BOB_PK` | `client.ts` | Same key, alternative name |
| `RPC_URL` | server container | Internal RPC endpoint (`http://10.0.0.1:8545`) |
| `FEE_PAYER_KEY` | server container | Hardhat #0 key, sponsors gas fees |

## How it works

### Server (`mpp-demo/server.ts`)

The server uses the [mppx](https://mpp.dev/sdk/typescript/) TypeScript SDK with a [Hono](https://hono.dev/) middleware:

- `tempo.charge()` configures the Tempo payment method with a custom `getClient` pointing to the local validator
- `mppx.charge()` middleware on `/api/joke` requires 0.01 pathUSD per request
- `tempoLocalnet` from `viem/chains` provides the correct chain definition (ID 1337)
- Fee sponsorship is enabled via `FEE_PAYER_KEY` (Hardhat #0), so clients don't need gas

### Client (`mpp-demo/client.ts`)

The programmatic client patches `fetch` with `Mppx.create()` to handle 402 responses automatically: parse the challenge, sign a TIP-20 transfer, and retry with a credential.

### Payment flow

1. Client sends `GET /api/joke`
2. Server returns `402` with a `WWW-Authenticate: Payment` header containing amount, currency, chain ID, and recipient
3. Client signs a TIP-20 transfer transaction (pathUSD to ALICE)
4. Client retries with the signed tx in the `Authorization` header
5. Server broadcasts the tx to validator-0 and waits for confirmation
6. Server returns `200` with the data and a `Payment-Receipt` header

## Justfile commands

| Command | Description |
|---|---|
| `just up-mpp` | Start consensus + MPP demo |
| `just restart-mpp` | Rebuild and restart only the mpp-demo container |
| `just logs-mpp` | Tail mpp-demo container logs |

## Troubleshooting

**Server keeps restarting** -- Check `just logs-mpp`. Common causes: missing `secretKey` in `Mppx.create()`, or `FEE_PAYER_KEY` not set.

**`InsufficientBalance` on client** -- Fund the paying account via the faucet first (see Quick start above).

## Next steps

- [Interact with the chain](usage.md) for manual transfers and balance checks
- [MPP documentation](https://mpp.dev) for the full protocol spec
- [mppx SDK reference](https://mpp.dev/sdk/typescript/) for client and server APIs
- [Tempo payment method](https://mpp.dev/payment-methods/tempo/) for charge vs session intents
