# Local DNS (optional)

Set up local hostnames so you can reach the RPC and faucet through Traefik with meaningful names instead of `localhost`.

Traefik routes by `Host` header:

- `rpc.tempo.local` -- load-balanced across rpc-0 and rpc-1
- `faucet.tempo.local` -- faucet node (`tempo_fundAddress`)

Without DNS, `http://localhost` (port 80) still works as a fallback and routes to the RPC nodes.

!!! warning "OrbStack"
    If OrbStack's domain networking is enabled, it binds port 80 on the host. Traefik will fail to start with an "address already in use" error. Either disable OrbStack's domain networking or remap Traefik to a different port (e.g. `8080:80`) in `docker-compose.yaml`.

## Option 1 -- `/etc/hosts` (simplest)

```bash
echo "127.0.0.1  rpc.tempo.local faucet.tempo.local" | sudo tee -a /etc/hosts
```

Verify:

```bash
curl -s -X POST http://rpc.tempo.local \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

curl -s -X POST http://faucet.tempo.local \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```


To undo:

```bash
sudo sed -i '' '/tempo\.local/d' /etc/hosts
```
