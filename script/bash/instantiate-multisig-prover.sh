#!/bin/bash
export PROVER_CODE_ID=618
export MY_WALLET_ADDRESS="axelar12u9hneuufhrhqpyr9h352dhrdtnz8c0z3w8rsk"
export MY_VERIFIER_ADDRESS="axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx"
export MY_GATEWAY_ADDRESS="axelar16zy7kl6nv8zk0racw6nsm6n0yl7h02lz4s9zz4lt8cfl0vxhfp8sqmtqcr"
export MY_CHAIN_ID=2017

# using cast, derive domain separator from `${chainName}_${myWalletAddress}_${proverCodeId}`
input_string="telcoin-network_${MY_WALLET_ADDRESS}_${PROVER_CODE_ID}"
# will be `0x0035b22d651590efd9f93af65ea459a46e0775da014fe31629513fa0e63a4de0`
domain_separator=$(cast keccak "$input_string")
domain_separator_unprefixed=${domain_separator#0x}

axelard tx wasm instantiate $PROVER_CODE_ID \
    '{
        "admin_address": "'"$MY_WALLET_ADDRESS"'",
        "governance_address": "axelar1zlr7e5qf3sz7yf890rkh9tcnu87234k6k7ytd9",
        "gateway_address": "'"$MY_GATEWAY_ADDRESS"'",
        "multisig_address": "axelar19jxy26z0qnnspa45y5nru0l5rmy9d637z5km2ndjxthfxf5qaswst9290r",
        "coordinator_address":"axelar1m2498n4h2tskcsmssjnzswl5e6eflmqnh487ds47yxyu6y5h4zuqr9zk4g",
        "service_registry_address":"axelar1c9fkszt5lq34vvvlat3fxj6yv7ejtqapz04e97vtc9m5z9cwnamq8zjlhz",
        "voting_verifier_address": "'"$MY_VERIFIER_ADDRESS"'",
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
    --chain-id devnet-amplifier \
    --node http://devnet-amplifier.axelar.dev:26657 \
    --label test-prover-tn  \
    --admin $MY_WALLET_ADDRESS

# Resulting multisig-prover address: axelar162t7mxkcnu7psw7qxlsd4cc5u6ywm399h8xg6qhgseg8nq6qhf6s7q8m0e