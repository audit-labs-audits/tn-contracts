#!/bin/bash
export VERIFIER_CODE_ID=626
export MY_SECOND_WALLET_ADDRESS="axelar1sky56slxkswwd8e68ln8da3j44vlhjdvqkxnqg"
export MY_SOURCE_CHAIN_GATEWAY_ADDRESS="0xBf02955Dc36E54Fe0274159DbAC8A7B79B4e4dc3"

axelard tx wasm instantiate $VERIFIER_CODE_ID \
    '{
        "governance_address": "axelar1zlr7e5qf3sz7yf890rkh9tcnu87234k6k7ytd9",
        "service_registry_address":"axelar1c9fkszt5lq34vvvlat3fxj6yv7ejtqapz04e97vtc9m5z9cwnamq8zjlhz",
        "service_name":"validators-tn",
        "source_gateway_address":"'"$MY_SOURCE_CHAIN_GATEWAY_ADDRESS"'",
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
    --chain-id devnet-amplifier \
    --node http://devnet-amplifier.axelar.dev:26657 \
    --label test-voting-verifier-tn \
    --admin $MY_SECOND_WALLET_ADDRESS
    
# Resulting voting-verifier address: axelar16rlsy2vs89yv6wvexur0sgq3kvcq6glu4cy6xz2et36hsmehhhuswxuw05