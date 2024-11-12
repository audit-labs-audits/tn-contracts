export PROVER_CODE_ID=618
export MY_GATEWAY_ADDRESS=""
export MY_CHAIN_ID=2017

axelard tx wasm instantiate $PROVER_CODE_ID \
    '{
        "admin_address": "'"$MY_WALLET_ADDRESS"'",
        "governance_address": "axelar1zlr7e5qf3sz7yf890rkh9tcnu87234k6k7ytd9",
        "gateway_address": "'"$MY_GATEWAY_ADDRESS"'",
        "multisig_address": "",
        "coordinator_address":"axelar1m2498n4h2tskcsmssjnzswl5e6eflmqnh487ds47yxyu6y5h4zuqr9zk4g",
        "service_registry_address":"axelar1c9fkszt5lq34vvvlat3fxj6yv7ejtqapz04e97vtc9m5z9cwnamq8zjlhz",
        "voting_verifier_address": "'"$MY_VERIFIER_ADDRESS"'",
        "signing_threshold": ["1","1"],
        "service_name": "validators-tn",
        "chain_name":"telcoin-network",
        "verifier_set_diff_threshold": 1,
        "encoder": "abi",
        "key_type": "ecdsa",
        "domain_separator": "6973c72935604464b28827141b0a463af8e3487616de69c5aa0c785392c9fb9f"
    }' \
    --keyring-backend test \
    --from wallet \
    --gas auto --gas-adjustment 1.5 --gas-prices 0.00005uamplifier\
    --chain-id devnet-amplifier \
    --node http://devnet-amplifier.axelar.dev:26657 \
    --label test-prover-tn  \
    --admin $MY_WALLET_ADDRESS