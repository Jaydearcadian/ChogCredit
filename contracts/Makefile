.PHONY: deps fmt build test deploy-testnet

# Dependencies are pinned git submodules (see ../.gitmodules). Requires Foundry >= 1.8.0 (Monad execution support).
deps:
	git submodule update --init --recursive

fmt:
	forge fmt --check

build:
	forge build

test:
	forge test -vvv

deploy-testnet:
	DEPLOY_MODE=testnet-mock forge script script/DeployCore.s.sol:DeployCore --rpc-url monad_testnet --broadcast -vvvv
