From the telcoin-network root directory, start a local testnet, eg:

`./etc/local-testnet.sh --dev-funds 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23`

Once the local testnet is running, from the tn-contracts root directory initiate a GMP message on the gateway, eg:

`npm run initiate -- --target-chain telcoin --target-contract 0xF128c84c3326727c3e155168daAa4C0156B87AD1 --amount 0 --destination-chain sepolia --destination-contract 0xF128c84c3326727c3e155168daAa4C0156B87AD1 --payload 0x68656c6c6f20776f726c64`

After the transaction is confirmed, grab the tx hash, log index, and payload hash which will be used to verify execution on the source chain.

`npm run verify -- --source-chain telcoin-network --source-address 0xF128c84c3326727c3e155168daAa4C0156B87AD1 --destination-chain sepolia --destination-address 0xF128c84c3326727c3e155168daAa4C0156B87AD1 --tx-hash 0x962b4f88aebae63000e59256fa85bde67d085db45bf491dd6a1b1c9c8884fc63 --log-index 0 --payload-hash 0x47173285a8d7341e5e972fc677286384f802f8ef42a5ec5f03bbfa254cb01fad`
