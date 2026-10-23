#!/usr/bin/env bash
# Point the app at the local Anvil deployment (see contracts/script/DeployCredit.s.sol).
set -euo pipefail
cd "$(dirname "$0")/.."
cp ../contracts/deployments/credit-local-31337.json public/deployment.json
echo "app now uses $(python3 -c 'import json;print(json.load(open("public/deployment.json"))["registry"])') on chain 31337"
