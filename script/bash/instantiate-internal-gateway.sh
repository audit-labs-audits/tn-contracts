#!/bin/bash
# This script instantiates an internal gateway using provided params
set -e
set -u

# devnet-amplifier config
GATEWAY_CODE_ID=848
CHAIN_ID="devnet-amplifier"
ROUTER_ADDR="axelar14jjdxqhuxk803e9pq64w4fgf385y86xxhkpzswe9crmu6vxycezst0zq8y"
RPC="http://devnet-amplifier.axelar.dev:26657" 

# initialize to default values before parsing CLI args
WALLET_ADDR="axelar12u9hneuufhrhqpyr9h352dhrdtnz8c0z3w8rsk"
VOTING_VERIFIER_ADDR="axelar1kdzmvkjtvu8cct0gzzqdj8jyd6yvlcswauu73ccmvcl0w429xcxqdqst4p"

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
        "router_address": "'"$ROUTER_ADDR"'"
    }' \
    --keyring-backend file \
    --from devnet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.00005uamplifier\
    --chain-id $CHAIN_ID \
    --node $RPC \
    --label test-gateway-tn \
    --admin $WALLET_ADDR

# Resulting internal-gateway address: axelar1ecyaz6vr4hj6qwnza8vh0xuer04jmwxnd4vpewtuju3404hvwv7sdj30zz