#!/bin/bash
# This script instantiates an internal gateway using provided params
set -e
set -u

GATEWAY_CODE_ID=616
CHAIN_ID="devnet-amplifier"

# fallback addresses are for devnet-amplifier
FALLBACK_WALLET_ADDR="axelar12u9hneuufhrhqpyr9h352dhrdtnz8c0z3w8rsk"
FALLBACK_VERIFIER_ADDR="axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx"
FALLBACK_RPC_URL="http://devnet-amplifier.axelar.dev:26657" 

# initialize to default values before parsing CLI args
WALLET_ADDR="$FALLBACK_WALLET_ADDR"
VOTING_VERIFIER_ADDR="$FALLBACK_VERIFIER_ADDR"
RPC="$FALLBACK_RPC_URL"

# parse CLI args if given
while [[ "$#" -gt 0 ]]; do
    case $1 in 
        --wallet-addr) 
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                WALLET_ADDR="$2" 
                shift
            else
                echo "Error: provide a value to --wallet-addr"
                exit 1
            fi
            ;;
        --verifier-addr) 
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                VOTING_VERIFIER_ADDR="$2" 
                shift
            else
                echo "Error: provide a value to --verifier-addr"
                exit 1
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

echo "Using wallet address: $WALLET_ADDR"
echo "Using voting verifier: $VOTING_VERIFIER_ADDR"
echo "Using RPC url: $RPC"

axelard tx wasm instantiate $GATEWAY_CODE_ID \
    '{
        "verifier_address": "'"$VOTING_VERIFIER_ADDR"'",
        "router_address": "axelar14jjdxqhuxk803e9pq64w4fgf385y86xxhkpzswe9crmu6vxycezst0zq8y"
    }' \
    --keyring-backend test \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.00005uamplifier\
    --chain-id $CHAIN_ID \
    --node $RPC \
    --label test-gateway-tn \
    --admin $WALLET_ADDR

# Resulting internal-gateway address: axelar16zy7kl6nv8zk0racw6nsm6n0yl7h02lz4s9zz4lt8cfl0vxhfp8sqmtqcr