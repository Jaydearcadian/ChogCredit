.PHONY: deps test build deploy-testnet

deps:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install foundry-rs/forge-std --no-commit

build:
	forge build

test:
	forge test -vvv

deploy-testnet:
	forge script script/Deploy.s.sol:Deploy --rpc-url monad_testnet --broadcast -vvvv
