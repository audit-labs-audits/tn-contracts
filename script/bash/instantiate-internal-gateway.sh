export GATEWAY_CODE_ID=616
export MY_VERIFIER_ADDRESS=""

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
