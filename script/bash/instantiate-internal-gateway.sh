#!/bin/bash
export GATEWAY_CODE_ID=616
export MY_WALLET_ADDRESS="axelar12u9hneuufhrhqpyr9h352dhrdtnz8c0z3w8rsk"
export MY_VERIFIER_ADDRESS="axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx"

axelard tx wasm instantiate $GATEWAY_CODE_ID \
    '{
        "verifier_address": "'"$MY_VERIFIER_ADDRESS"'",
        "router_address": "axelar14jjdxqhuxk803e9pq64w4fgf385y86xxhkpzswe9crmu6vxycezst0zq8y"
    }' \
    --keyring-backend test \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.00005uamplifier\
    --chain-id devnet-amplifier \
    --node http://devnet-amplifier.axelar.dev:26657 \
    --label test-gateway-tn \
    --admin $MY_WALLET_ADDRESS

# Resulting internal-gateway address: axelar16zy7kl6nv8zk0racw6nsm6n0yl7h02lz4s9zz4lt8cfl0vxhfp8sqmtqcr