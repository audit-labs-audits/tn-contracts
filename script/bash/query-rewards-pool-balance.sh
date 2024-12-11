#!/bin/bash
# This script queries a Telcoin-Network rewards pool's balance
set -e
set -u

CHAIN_NAME="telcoin-network"

# fallback addresses are for devnet-amplifier
FALLBACK_REWARDS_CONTRACT_ADDR="axelar1vaj9sfzc3z0gpel90wu4ljutncutv0wuhvvwfsh30rqxq422z89qnd989l"
FALLBACK_VOTING_VERIFIER="axelar1elaymnd2epmfr498h2x9p2nezc4eklv95uv92u9csfs8wl75w7yqdc0h67"
FALLBACK_MULTISIG_ADDR="0x7eeE33A59Db27d762AA1Fa31b26efeE0dABa1132"
FALLBACK_RPC_URL="http://devnet-amplifier.axelar.dev:26657"


# initialize variables to fallback
REWARDS_CONTRACT_ADDR="$FALLBACK_REWARDS_CONTRACT_ADDR"
VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR=""
RPC="$FALLBACK_RPC_URL"

VERIFIER_FLAG=false
MULTISIG_FLAG=false

# parse CLI args if given
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rewards-contract)
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                REWARDS_CONTRACT_ADDR="$2"
                shift
            else
                echo "No rewards contract specified, using devnet default"
                REWARDS_CONTRACT_ADDR="$FALLBACK_REWARDS_CONTRACT_ADDR"
            fi
            ;;
        # specify --verifier to query a verifier pool
        --verifier)
            VERIFIER_FLAG=true
            # if a value is passed to --verifier, use it; else use default devnet value
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR="$2"
                shift
            else
                echo "No value specified for verifier address, using devnet default"
                VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR="$FALLBACK_VOTING_VERIFIER"
            fi
            ;;
        # specify --multisig to query a multisig pool
        --multisig) 
            MULTISIG_FLAG=true
            # if a value is passed to --multisig, use it; else use default devnet value
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR="$2"
                shift
            else
                echo "No value specified for multisig address, using devnet default"
                VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR="$FALLBACK_MULTISIG_ADDR"
            fi
            ;;
        --rpc-url)
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                RPC="$2"
                shift
            else
                echo "Must provide a value if specifying --rpc-url"
                exit 1
            fi
            ;;
    *)
        echo "Unknown parameter passed: $1"
        exit 1
        ;;
    esac
    shift
done

# ensure either --verifier or --multisig is provided and not both
if [[ "$VERIFIER_FLAG" == true && "$MULTISIG_FLAG" == true ]]; then
    echo "Error: script can only fund one pool type at a time."
    exit 1
fi
if [[ "$VERIFIER_FLAG" == false && "$MULTISIG_FLAG" == false ]]; then
    echo "Error: must specify verifier or multisig pool type."
    exit 1
fi

echo "Using target reward pool address: $VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR"
echo "Using RPC url: $RPC"

axelard q wasm contract-state smart $REWARDS_CONTRACT_ADDR \
    '{
        "rewards_pool":
            {
                "pool_id":
                    {
                        "chain_name":"'"$CHAIN_NAME"'",
                        "contract":"'"$VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR"'"
                    }
            }
    }' \
    --node $RPC