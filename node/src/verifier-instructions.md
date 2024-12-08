# Instructions for a verifier for Telcoin-Network bridging

Running a verifier on Axelar Network constitutes running an instance of tofnd and of ampd in tandem. These services perform Axelar GMP message verification and sign transactions representing votes which are submitted to Axelar Network as part of Telcoin-Network's bridging flow.

### Note: These instructions center around running a TN Verifier for testing on devnet and testnet by the Telcoin Network team. For mainnet, Axelar Network already has an existing set of verifiers who will run verifiers alongside a TN NVV client.

## Running a TOFND instance

Download the tofnd binary depending on machine architecture from the [latest release tag](https://github.com/axelarnetwork/tofnd/releases)

Create a default mnemonic and configuration in ~/.tofnd/, then back it up and delete it.

```bash
~/Downloads/tofnd*-v1.0.1 -m create
mv ~/.tofnd/export ~/.tofnd/export-new-location
```

Now run tofnd. Be sure to specify the correct file name which may be a different architecture or later version than v1.0.1

TODO: document making an alias for tofnd-binary -> tofnd

```bash
./tofnd-linux-amd64-v1.0.1 -m existing
```

## Running an AMPD instance

### Obtaining the ampd binary

Download the ampd binary depending on machine architecture from the [latest release tag](https://github.com/axelarnetwork/axelar-amplifier/releases)

Add ampd to your PATH by adding an alias to ampd at the end of the .bashrc file on your machine:

`echo "alias ampd=~/Downloads/ampd-darwin-arm64-v1.2.0" >> ~/.bashrc`

Replace ampd-darwin-arm64-v1.2.0 with the correct ampd binary if needed.
TODO: docs missing `alias` keyword, save and close is not necessary with `echo`

Reload the file to apply all changes:

`source ~/.bashrc`

Now you can run ampd, for example with `ampd --version`

### Configure ampd for Telcoin-Network and a source chain (eg Sepolia)

Ampd relies on a config file with handler contract declarations for each chain. This config file is located at `~/.ampd/config.toml`

Below is an example of the `~/.ampd/config.toml` config toml declaring handlers for Sepolia and Telcoin-Network using public RPC endpoints.

```bash
# JSON-RPC URL of Axelar node
tm_jsonrpc="http://devnet-amplifier.axelar.dev:26657"
# gRPC URL of Axelar node
tm_grpc="tcp://devnet-amplifier.axelar.dev:9090"
# max blockchain events to queue. Will error if set too low
event_buffer_cap=10000
# the /status endpoint bind address, often port 3000 i.e "0.0.0.0:3000"
health_check_bind_addr="0.0.0.0:3000"

[service_registry]
# address of service registry
cosmwasm_contract="axelar1c9fkszt5lq34vvvlat3fxj6yv7ejtqapz04e97vtc9m5z9cwnamq8zjlhz"

[broadcast]
# max gas for a transaction. Transactions can contain multiple votes and signatures
batch_gas_limit="20000000"
# how often to broadcast transactions
broadcast_interval="1s"
# chain id of Axelar network to connect to
chain_id="devnet-amplifier"
# gas adjustment to use when broadcasting
gas_adjustment="2"
# gas price with denom, i.e. "0.007uaxl"
gas_price="0.00005uamplifier"
# max messages to queue when broadcasting
queue_cap="1000"
# how often to query for transaction inclusion in a block
tx_fetch_interval="1000ms"
# how many times to query for transaction inclusion in a block before failing
tx_fetch_max_retries="15"

[tofnd_config]
batch_gas_limit="10000000"
# uid of key used for signing transactions
key_uid="axelar"
# metadata, should just be set to ampd
party_uid="ampd"
# url of tofnd
url="http://127.0.0.1:50051"

# multisig handler. This handler is used for all supported chains.
[[handlers]]
# address of multisig contract
cosmwasm_contract="axelar19jxy26z0qnnspa45y5nru0l5rmy9d637z5km2ndjxthfxf5qaswst9290r"
type="MultisigSigner"

# Ethereum-Sepolia EvmMsgVerifier handler declaration.
[[handlers]]
chain_name="ethereum-sepolia"
# URL of JSON-RPC endpoint for external chain
chain_rpc_url="https://rpc.ankr.com/eth_sepolia"
# verifier contract address
cosmwasm_contract="axelar1e6jnuljng6aljk0tjct6f0hl9tye6l0n9p067pwx2374h82dmr0s9qcqy9"
# handler type. Could be EvmMsgVerifier | SuiMsgVerifier
type="EvmMsgVerifier"
# if the chain supports the finalized tag via RPC API, use RPCFinalizedBlock, else use ConfirmationHeight
chain_finalization="RPCFinalizedBlock"

# Ethereum-Sepolia EvmVerifierSetVerifier handler declaration.
[[handlers]]
chain_name="ethereum-sepolia"
chain_rpc_url="https://rpc.ankr.com/eth_sepolia"
cosmwasm_contract="axelar1e6jnuljng6aljk0tjct6f0hl9tye6l0n9p067pwx2374h82dmr0s9qcqy9"
type="EvmVerifierSetVerifier"

# Telcoin-Network EvmMsgVerifier handler declaration
[[handlers]]
chain_name="telcoin-network"
# URL of JSON-RPC endpoint for external chain
chain_rpc_url="https://adiri.tel"
# verifier contract address
cosmwasm_contract="axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx"
# handler type; TN is EVM
type="EvmMsgVerifier"
# TN supports the finalized tag via RPC API; use RPCFinalizedBlock
chain_finalization="RPCFinalizedBlock"

# Telcoin-Network EvmVerifierSetVerifier handler declaration
[[handlers]]
chain_name="telcoin-network"
# URL of JSON-RPC endpoint for external chain
chain_rpc_url="https://adiri.tel"
# verifier contract address
cosmwasm_contract="axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx"
# handler type; TN is EVM
type="EvmVerifierSetVerifier"
```

### Fund and bond the Verifier associated with the ampd instance

To determine the verifier address associated with the ampd instance we've configure thus far, run:

`ampd verifier-address`

TODO: TN <> devnet-amplifier <> Sepolia verifier address is `axelar1t055c4qmplk8dwfaqf55dnm29ddg75rjh4jlle`

After determining the verifier address, fund it for gas purposes:

TODO: funding cmd
