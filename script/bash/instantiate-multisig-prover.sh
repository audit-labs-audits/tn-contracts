#!/bin/bash
# This script instantiates a multisig prover using provided params
set -e
set -u

PROVER_CODE_ID=618
CHAIN_ID="devnet-amplifier"

# fallback addresses are for devnet-amplifier
FALLBACK_WALLET_ADDR="axelar12u9hneuufhrhqpyr9h352dhrdtnz8c0z3w8rsk"
FALLBACK_VERIFIER_ADDR="axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx"
FALLBACK_INTERNAL_GATEWAY_ADDR="axelar16zy7kl6nv8zk0racw6nsm6n0yl7h02lz4s9zz4lt8cfl0vxhfp8sqmtqcr"
FALLBACK_RPC_URL="http://devnet-amplifier.axelar.dev:26657" 

# initialize to default values before parsing CLI args
WALLET_ADDR="$FALLBACK_WALLET_ADDR"
VOTING_VERIFIER_ADDR="$FALLBACK_VERIFIER_ADDR"
INTERNAL_GATEWAY_ADDR="$FALLBACK_INTERNAL_GATEWAY_ADDR"
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
        --gateway-addr) 
            if [[ -n "${2:-}" && ! "$2" =~ ^-- ]]; then
                INTERNAL_GATEWAY_ADDR="$2" 
                shift 
            else
                echo "Error: provide a value to --gateway-addr"
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

# using cast, derive domain separator from `${chainName}_${myWalletAddress}_${proverCodeId}`
input_string="telcoin-network_${WALLET_ADDR}_${PROVER_CODE_ID}"
# will be `0x0035b22d651590efd9f93af65ea459a46e0775da014fe31629513fa0e63a4de0`
domain_separator=$(cast keccak "$input_string")
domain_separator_unprefixed=${domain_separator#0x}

echo "Using wallet address: $WALLET_ADDR"
echo "Using voting verifier: $VOTING_VERIFIER_ADDR"
echo "Using domain separator: $domain_separator"
echo "Using RPC url: $RPC"

axelard tx wasm instantiate $PROVER_CODE_ID \
    '{
        "admin_address": "'"$WALLET_ADDR"'",
        "governance_address": "axelar1zlr7e5qf3sz7yf890rkh9tcnu87234k6k7ytd9",
        "gateway_address": "'"$INTERNAL_GATEWAY_ADDR"'",
        "multisig_address": "axelar19jxy26z0qnnspa45y5nru0l5rmy9d637z5km2ndjxthfxf5qaswst9290r",
        "coordinator_address":"axelar1m2498n4h2tskcsmssjnzswl5e6eflmqnh487ds47yxyu6y5h4zuqr9zk4g",
        "service_registry_address":"axelar1c9fkszt5lq34vvvlat3fxj6yv7ejtqapz04e97vtc9m5z9cwnamq8zjlhz",
        "voting_verifier_address": "'"$VOTING_VERIFIER_ADDR"'",
        "signing_threshold": ["1","1"],
        "service_name": "validators-tn",
        "chain_name":"telcoin-network",
        "verifier_set_diff_threshold": 1,
        "encoder": "abi",
        "key_type": "ecdsa",
        "domain_separator": "'"$domain_separator_unprefixed"'"
    }' \
    --keyring-backend test \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.00005uamplifier\
    --chain-id $CHAIN_ID \
    --node $RPC \
    --label test-prover-tn  \
    --admin $WALLET_ADDR

# Resulting multisig-prover address: axelar162t7mxkcnu7psw7qxlsd4cc5u6ywm399h8xg6qhgseg8nq6qhf6s7q8m0e