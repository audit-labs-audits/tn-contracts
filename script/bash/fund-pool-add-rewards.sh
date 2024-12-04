#!/bin/bash
# This script funds a rewards pool; which can be for either a verifier or multisig
set -e
set -u

CHAIN_NAME="telcoin-network"
CHAIN_ID="devnet-amplifier"

# fallback addresses are for devnet-amplifier
FALLBACK_REWARDS_CONTRACT_ADDR="axelar1vaj9sfzc3z0gpel90wu4ljutncutv0wuhvvwfsh30rqxq422z89qnd989l"
FALLBACK_VOTING_VERIFIER="axelar1elaymnd2epmfr498h2x9p2nezc4eklv95uv92u9csfs8wl75w7yqdc0h67"
FALLBACK_MULTISIG_ADDR="0x7eeE33A59Db27d762AA1Fa31b26efeE0dABa1132"
FALLBACK_RPC_URL="http://devnet-amplifier.axelar.dev:26657" 
FALLBACK_AMOUNT="1000uamplifier" # (1000000 = 1 AXL) 

# initialize variables to fallback
REWARDS_CONTRACT_ADDR="$FALLBACK_REWARDS_CONTRACT_ADDR"
VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR=""
RPC="$FALLBACK_RPC_URL"
AMOUNT="$FALLBACK_AMOUNT"

VERIFIER_FLAG=false
MULTISIG_FLAG=false

# parse CLI args if given
while [[ "$#" -gt 0 ]]; do
    case $1 in
        # specify --verifier to fund a verifier pool
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
        # specify --multisig to fund a multisig pool
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
        --amount)
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                AMOUNT="$2"
                shift
            else
                echo "Must provide a value if specifying --amount"
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
echo "Using native token amount: $AMOUNT"
echo "Using RPC url: $RPC"

axelard tx wasm execute $REWARDS_CONTRACT_ADDR \
    '{
        "add_rewards":
            {
                "pool_id":
                    {
                        "chain_name":"'"$CHAIN_NAME"'",
                        "contract":"'"$VOTING_VERIFIER_OR_MULTISIG_CONTRACT_ADDR"'"
                    }
            }
    }' \
    --amount $AMOUNT \
    --keyring-backend test \
    --chain-id $CHAIN_ID \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.007uamplifier \
    --node $RPC