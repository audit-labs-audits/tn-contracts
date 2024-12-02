#!/bin/bash
# This script instantiates a voting verifier using provided params
set -e
set -u

VERIFIER_CODE_ID=626
CHAIN_ID="devnet-amplifier"

# fallback addresses are for devnet-amplifier
FALLBACK_WALLET_ADDR="axelar1sky56slxkswwd8e68ln8da3j44vlhjdvqkxnqg"
FALLBACK_SOURCE_GATEWAY="0xBf02955Dc36E54Fe0274159DbAC8A7B79B4e4dc3"
FALLBACK_RPC_URL="http://devnet-amplifier.axelar.dev:26657" 

# initialize to default values before parsing CLI args
WALLET_ADDR="$FALLBACK_WALLET_ADDR"
SOURCE_GATEWAY_ADDR="$FALLBACK_SOURCE_GATEWAY"
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
        --src-gateway) 
            if [[ -n "$2:-}" && ! "$2" =~ ^-- ]]; then
                SOURCE_GATEWAY_ADDR="$2" 
                shift
            else
                echo "Error: provide a value to --src-gateway"
                exit 1
            fi
            ;;
        --rpc-url)
            if [[ -n "$2:-}" && ! "$2" =~ ^-- ]]; then
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
echo "Using source gateway: $SOURCE_GATEWAY_ADDR"
echo "Using RPC url: $RPC"

axelard tx wasm instantiate $VERIFIER_CODE_ID \
    '{
        "governance_address": "axelar1zlr7e5qf3sz7yf890rkh9tcnu87234k6k7ytd9",
        "service_registry_address":"axelar1c9fkszt5lq34vvvlat3fxj6yv7ejtqapz04e97vtc9m5z9cwnamq8zjlhz",
        "service_name":"validators-tn",
        "source_gateway_address":"'"$SOURCE_GATEWAY_ADDR"'",
        "voting_threshold":["1","1"],
        "block_expiry":"10",
        "confirmation_height":1,
        "source_chain":"telcoin-network",
        "rewards_address":"axelar12u9hneuufhrhqpyr9h352dhrdtnz8c0z3w8rsk",
        "msg_id_format":"hex_tx_hash_and_event_index",
        "address_format": "eip55"
    }' \
    --keyring-backend test \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.00005uamplifier\
    --chain-id $CHAIN_ID \
    --node $RPC \
    --label test-voting-verifier-tn \
    --admin $WALLET_ADDR
    
# Resulting voting-verifier address: axelar16rlsy2vs89yv6wvexur0sgq3kvcq6glu4cy6xz2et36hsmehhhuswxuw05