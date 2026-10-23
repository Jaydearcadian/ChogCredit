#!/usr/bin/env bash
# Fresh local chain + fresh deployment + a seeded lender, for the end-to-end run. Uses Anvil's well-known first test key.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH=$PATH:~/.foundry/bin
pkill -x anvil; sleep 1
nohup anvil --code-size-limit 131072 --block-time 1 > /tmp/chog-anvil.log 2>&1 &
sleep 3
cd "$ROOT/contracts"
DEPLOY_MODE=local SEED_CHOGS=3 ENABLE_LP=${ENABLE_LP:-false} forge script script/DeployCredit.s.sol --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast --disable-code-size-limit 2>&1 | grep -E "SUCCESSFUL|rror"
cd ../app && ./scripts/use-local-deployment.sh
# a lender supplies 5,000 USDC so there is something to borrow
cd "$ROOT/contracts"
M=$(python3 -c 'import json;d=json.load(open("deployments/credit-local-31337.json"));print(d["mockUsdc"],d["pool"])')
USDC=${M% *}; POOL=${M#* }
K=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; R=http://127.0.0.1:8545
cast send $USDC "faucet()" --private-key $K --rpc-url $R >/dev/null
cast send $USDC "approve(address,uint256)" $POOL 5000000000 --private-key $K --rpc-url $R >/dev/null
cast send $POOL "supply(uint256)" 5000000000 --private-key $K --rpc-url $R >/dev/null && echo "pool seeded with 5,000 USDC"
