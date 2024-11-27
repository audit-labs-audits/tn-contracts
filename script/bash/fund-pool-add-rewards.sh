#!/bin/bash

# Will fund a rewards pool; specify which pool with either $VOTING_VERIFIER or $MULTISIG_PROVER
export REWARDS_CONTRACT_ADDRESS="axelar1vaj9sfzc3z0gpel90wu4ljutncutv0wuhvvwfsh30rqxq422z89qnd989l"
export CHAIN_NAME="telcoin-network" 
# convert to CLI arg. These can be hard coded and set using a string flag
export VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDRESS="axelar1elaymnd2epmfr498h2x9p2nezc4eklv95uv92u9csfs8wl75w7yqdc0h67"
|| "0x7eeE33A59Db27d762AA1Fa31b26efeE0dABa1132" 
export RPC="http://devnet-amplifier.axelar.dev:26657" 
export AMOUNT="1000uamplifier"
# convert amount to fund to CLI arg (1000000 = 1 AXL) 
export CHAIN_ID="devnet-amplifier"

axelard tx wasm execute $REWARDS_CONTRACT_ADDRESS \
    '{
        "add_rewards":
            {
                "pool_id":
                    {
                        "chain_name":"'"$CHAIN_NAME"'",
                        "contract":"'"$VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDRESS"'"
                    }
            }
    }' \
    --amount "'"$AMOUNT"'" \
    --keyring-backend test \
    --chain-id "'"$CHAIN_ID"'" \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.007uamplifier \
    --node $RPC