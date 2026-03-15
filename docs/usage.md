# Interact with the Chain

All examples use [Foundry `cast`](https://docs.tempo.xyz/sdk/foundry). Install the Tempo fork for full feature support:

```bash
foundryup -n tempo
```

> Standard Foundry works for basic queries and transfers. The Tempo fork adds `batch-send`, `--tempo.fee-token`, expiring nonces, and fee sponsorship.

## Endpoints

| Service | URL |
|---|---|
| RPC (load-balanced) | `http://localhost` (Traefik, port 80) |
| RPC (direct rpc-0) | `http://localhost:8545` |
| Faucet | `http://localhost:8546` |

```bash
export RPC=http://localhost:8545
export FAUCET=http://localhost:8546
export PATHUSD=0x20c0000000000000000000000000000000000000
```

---

## 1. Create test wallets

```bash
cast wallet new   # → Alice
cast wallet new   # → Bob
```

```bash
export ALICE=0x...
export ALICE_PK=0x...
export BOB=0x...
```

## 2. Fund via faucet

The faucet mints **pathUSD** (6 decimals) to any address:

```bash
cast rpc tempo_fundAddress $ALICE --rpc-url $FAUCET
```

Or with curl:

```bash
curl -s -X POST $FAUCET \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"tempo_fundAddress\",\"params\":[\"$ALICE\"],\"id\":1}"
```

## 3. Check balance

On Tempo there is no native gas token — `eth_getBalance` returns a sentinel value. Read real balances via the TIP-20 contract:

```bash
cast call $PATHUSD "balanceOf(address)(uint256)" $ALICE --rpc-url $RPC
```

## 4. Send a payment

Transfer 1 pathUSD (= 1,000,000 units at 6 decimals):

```bash
cast send $PATHUSD \
  "transfer(address,uint256)" $BOB 1000000 \
  --rpc-url $RPC --private-key $ALICE_PK
```

Fees are paid in pathUSD automatically.

### With memo

Attach a 32-byte memo for reconciliation:

```bash
MEMO=$(cast --format-bytes32-string "INV-001")

cast send $PATHUSD \
  "transferWithMemo(address,uint256,bytes32)" $BOB 500000 "$MEMO" \
  --rpc-url $RPC --private-key $ALICE_PK
```

Emits both `Transfer` and `TransferWithMemo` events.

## 5. Batch transactions

> Requires the [Tempo Foundry fork](https://docs.tempo.xyz/sdk/foundry).

Send multiple calls in a single atomic transaction:

```bash
cast batch-send \
  --call "$PATHUSD::transfer(address,uint256):$BOB,100000" \
  --call "$PATHUSD::transfer(address,uint256):$BOB,200000" \
  --rpc-url $RPC --private-key $ALICE_PK
```

All calls succeed or all revert together. One signature, lower gas.

## 6. Query chain state

```bash
cast block-number --rpc-url $RPC              # current height
cast chain-id --rpc-url $RPC                  # 1337 local, 42431 testnet moderato
cast block latest --rpc-url $RPC              # latest block details

cast call $PATHUSD "name()(string)" --rpc-url $RPC          # "pathUSD"
cast call $PATHUSD "decimals()(uint8)" --rpc-url $RPC       # 6
cast call $PATHUSD "totalSupply()(uint256)" --rpc-url $RPC
```

## 7. Inspect a transaction

```bash
cast receipt <TX_HASH> --rpc-url $RPC
```

Tempo-specific receipt fields:

| Field | Description |
|---|---|
| `feeToken` | TIP-20 token that paid the fee |
| `feePayer` | Address that paid the fee (can differ from `from` with sponsorship) |

---

## Tokens

| Token | Address | Decimals | Availability |
|---|---|---|---|
| pathUSD | `0x20c0...0000` | 6 | local + testnet |

Other tokens are available on the [official testnet](https://docs.tempo.xyz/guide/use-accounts/add-funds)

## Tempo Foundry cheatsheet

These require `foundryup -n tempo`:

## Next steps

- [Dashboards](dashboards.md) — monitor the chain in Grafana
- [Payment lanes spec](https://docs.tempo.xyz/protocol/blockspace/payment-lane-specification)
- [Fee sponsorship guide](https://docs.tempo.xyz/guide/payments/sponsor-user-fees)
- [Stablecoin DEX guide](https://docs.tempo.xyz/guide/stablecoin-dex/executing-swaps)
- [TypeScript / Rust / Go SDKs](https://docs.tempo.xyz/sdk/)
- [Tempo Foundry fork](https://docs.tempo.xyz/sdk/foundry)
