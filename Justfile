set dotenv-load

tempo_repo := env("TEMPO_REPO", "../tempo")

# Start everything: consensus network + full observability stack
up:
    docker compose --profile consensus --profile monitoring up -d

# Start everything: consensus network + full observability stack
up-consensus:
    docker compose --profile consensus up -d

up-restart:
    docker compose --profile consensus --profile monitoring up -d --force-recreate

# Stop all services
down:
    docker compose --profile consensus --profile monitoring down

# Stop all services with volumes
down-v:
    docker compose --profile consensus --profile monitoring down -v

# Tail logs for a service (default: validator-0)
# Usage: just logs [validator-0|validator-1|rpc-0|rpc-1|traefik|alloy|...]
logs service="validator-0":
    docker logs -f tempo-{{service}}

# Tail health-check sidecar logs for rpc-0 or rpc-1
# Usage: just logs-health [rpc-0|rpc-1]
logs-health service="rpc-0":
    docker logs -f tempo-{{service}}-health

# Regenerate genesis and validator keys from the tempo repo
generate-genesis:
    cd {{tempo_repo}} && CARGO_HOME=/tmp/cargo-home cargo xtask generate-genesis \
        --validators 10.0.0.1:8000,10.0.0.2:8000,10.0.0.3:8000,10.0.0.4:8000 \
        --seed 0 \
        --accounts 100 \
        --no-extra-tokens \
        --no-pairwise-liquidity \
        --output {{justfile_directory()}}/consensus/generated-tmp
    rm -rf {{justfile_directory()}}/consensus/validator-{0,1,2,3} {{justfile_directory()}}/consensus/genesis.json
    mv {{justfile_directory()}}/consensus/generated-tmp/genesis.json {{justfile_directory()}}/consensus/genesis.json
    cd {{justfile_directory()}}/consensus/generated-tmp && \
        for i in 0 1 2 3; do mv "10.0.0.$((i+1)):8000" {{justfile_directory()}}/consensus/validator-$i; done
    rm -rf {{justfile_directory()}}/consensus/generated-tmp
    # Fund faucet account (Hardhat #0) with 10M native ETH for gas
    python3 -c "import json; \
        f=open('{{justfile_directory()}}/consensus/genesis.json'); g=json.load(f); f.close(); \
        g['alloc']['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266']={'balance':hex(10_000_000*10**18)}; \
        f=open('{{justfile_directory()}}/consensus/genesis.json','w'); json.dump(g,f,indent=2); f.write('\n'); f.close()"

# Run health check against the RPC endpoint
health rpc_url="http://localhost:8545":
    ./scripts/health-check.sh {{rpc_url}}

# Show service status
status:
    docker compose --profile consensus --profile monitoring ps

# Serve docs locally with MkDocs (http://localhost:8000)
docs:
    docker run --rm -p 8000:8000 -v {{justfile_directory()}}:/docs squidfunk/mkdocs-material
