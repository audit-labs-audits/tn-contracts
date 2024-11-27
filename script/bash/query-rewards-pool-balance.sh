#!/bin/bash
export REWARDS_CONTRACT_ADDRESS="axelar1vaj9sfzc3z0gpel90wu4ljutncutv0wuhvvwfsh30rqxq422z89qnd989l"
export CHAIN_NAME="telcoin-network"
# convert to CLI arg - can be matched using string representation
export VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDRESS="axelar1elaymnd2epmfr498h2x9p2nezc4eklv95uv92u9csfs8wl75w7yqdc0h67" || "0x7eeE33A59Db27d762AA1Fa31b26efeE0dABa1132"
export RPC="http://devnet-amplifier.axelar.dev:26657"

axelard q wasm contract-state smart $REWARDS_CONTRACT_ADDRESS \
    '{
        "rewards_pool":
            {
                "pool_id":
                    {
                        "chain_name":"'"$CHAIN_NAME"'",
                        "contract":"'"$VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDRESS"'"
                    }
            }
    }' \
    --node $RPC