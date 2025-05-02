# Telcoin Network Bridging

Because the Telcoin token $TEL was deployed as an ERC20 token on Ethereum as part of its ICO in 2017, a native bridging mechanism needed to be devised in order to use $TEL as the native currency for Telcoin Network.

At the very highest level, Telcoin Network utilizes four component categories to enable native cross-chain bridging. These are:

- Axelar [Interchain Token Service](../../src/interchain-token-service/README.md) and [GMP protocol](https://www.axelar.network/blog/general-message-passing-and-how-can-it-change-web3)
- [offchain relayers](./relay/README.md)
- [Telcoin Network's customized interchain TEL implementation, the InterchainTEL contract](../../README.md#itel-module)
- [verifiers](./verifier-instructions.md) voting on event finality using the Telcoin Network Non-Voting Validator "NVV" node client

## In a (very abstract) nutshell

### Gateway and Interchain Token Service Contracts

Each chain that enables cross-chain GMP communication via Axelar Network integrates to the Axelar hub by deploying at minimum an external gateway smart contract. The Interchain Token Service is built on top of cross-chain GMP messages, protocolizing an interoperability standard for interchain ERC20 tokens with the use of `MINT_BURN` or `LOCK_RELEASE` delivery mechanisms.

For Telcoin Network the AxelarAmplifierGateway, Interchain Token Service contracts, and the interchain TEL contract (InterchainTEL) as well as its `MINT_BURN` token manager are precompiled and instantiated at genesis.

ITS handles calls to the external gateway, causing it to emit outgoing ITS messages and execute incoming ITS messages validated by the gateway. ITS instructs the InterchainTEL token manager to perform $TEL mints and burns by calling the respective InterchainTEL function.

### GMP API

The Axelar GMP API abstracts away Axelar Network's internals [which are discussed here](https://forum.telcoin.org/t/light-clients-independent-verification/296/6?u=robriks). Under the hood, the GMP API handles a series of CosmWasm transactions required to push cross-chain messages through various verification steps codified by smart contracts deployed on the Axelar blockchain.

### Relayers

Relayers are offchain components that handle the transfer of cross-chain messages by monitoring the external gateways for new outbound messages and relaying them to the Axelar GMP API or vice versa. In the reverse case, relayers poll the GMP API for new incoming messages which have been verified by Axelar Network and deliver them to the chain's external gateway as well as execute them through the executable contract via transactions.

### Verifiers

To validate cross-chain messages within the Axelar chain, whitelisted services called "verifiers" check new messages against their source chain's finality by performing RPC calls to ensure the messages were emitted by the source chain's gateway in a block which has reached finality. The verifiers themselves run a copy of a Telcoin Network Non-Voting Validator client to track TN's execution and consensus, and in turn quorum-vote on whether or not the message in question is finalized.

## User Flow

### Bridging to TN

From a user's perspective, two transactions are required to initiate the bridging sequence to TN from a source chain:

1. Approve the token balance to be bridged for the local ITS contract to spend. This is necessary because the gateway transfers tokens from the user to itself in the subsequent bridge transaction, locking those tokens so they can be delivered and used on the destination chain.

2. Perform a call to the local ITS `interchainTransfer()` function. This transaction locks the tokens to be bridged in their token manager, where they remain until the tokens are bridged back from the destination chain.

### Bridging from TN

From a user's perspective, two transactions are required to initiate the bridging sequence from TN to a remote chain:

1. Double wrap the native TEL balance on the InterchainTEL contract. This is necessary because ITS is designed for ERC20 tokens and so InterchainTEL's ERC20 ledger serves as the interchain representation of bridgeable outbound TEL on Telcoin-Network. It can be done using any one of the following InterchainTEL functions:

- `doubleWrap()`: requires providing native TEL to the function call,
- `permitWrap()`: requires user to hold wTEL and sign an ERC2612 permit to the InterchainTEL contract
- `wrap()`: requires user to hold and approve their wTEL balance to the InterchainTEL contract

### Example

Telcoin-Network provides a canonical bridge interface for a convenient UI to perform the transactions above, but bridging remains permissionless because it can be performed by any user with TEL tokens on their own.

Below is an example for bridging using ethers and the AxelarQueryAPI, which helps with gas estimation for prepayment:

```javascript
const { ethers } = require("ethers");
const {
  AxelarQueryAPI,
  CHAINS,
  Environment,
} = require("@axelar-network/axelarjs-sdk");

const provider = new ethers.providers.JsonRpcProvider(
  "https://source_chain_endpoint"
);

// ITS address is the same on both sepolia and TN
const devnetITS = "0x2269B93c8D8D4AfcE9786d2940F5Fcd4386Db7ff";
const itsInterchainTransferABI = [
  {
    type: "function",
    name: "interchainTransfer",
    inputs: [
      { name: "tokenId", type: "bytes32", internalType: "bytes32" },
      { name: "destinationChain", type: "string", internalType: "string" },
      { name: "destinationAddress", type: "bytes", internalType: "bytes" },
      { name: "amount", type: "uint256", internalType: "uint256" },
      { name: "metadata", type: "bytes", internalType: "bytes" },
      { name: "gasValue", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
];
const interchainTokenService = new ethers.Contract(
  devnetITS,
  itsInterchainTransferABI,
  provider
);

// it looks like axelarjs-sdk doesn't yet have DEVNET::eth-sepolia so try using TESTNET::ethereum-sepolia
const sdk = new AxelarQueryAPI({ environment: Environment.TESTNET });
// this should be the execution cost on the destination chain, will require some testing to identify so for now just hard code a generous one
const gasLimit = 700000;
// TN devnet should behave similarly to sepolia so we can mock it here until we've added support for it to the gas query api via a PR
const sourceChain = CHAINS.TESTNET.SEPOLIA;
const mockDest = CHAINS.TESTNET.SEPOLIA;
const gasValue = sdk.estimateGasFee(sourceChain, mockDest, gasLimit, "auto");

// this must be TEL's interchain token ID, currently using the devnet sepolia ID
const interchainTokenId =
  "0x7da21a183d41d57607078acf0ae8c42a61f1613ab223509359da7d27b95bc1f5";
const metadata = ""; // not used
// open to user input; generally should default to the user wallet
const recipientAddress = "0xuserWallet";
const amount = 42; // denominated in TEL, must undergo decimals conversion

/// @dev Bridges ERC20 TEL on Sepolia to native TEL on TN
async function bridgeSepoliaToTN(recipient, amount) {
  // must use Axelar contracts's exact matching name. devnet is as follows:
  const destinationChain = "telcoin-devnet";

  // erc20 TEL uses 2 decimals
  const bridgeAmount = amount * 1e2;
  // user must first approve ITS
  sepoliaTEL.approve(devnetITS, bridgeAmount);

  // note that the recipient `destinationAddress` must be of `bytes` type, not `address`
  const tx = await interchainTokenService.interchainTransfer(
    interchainTokenId,
    destinationChain,
    ethers.utils.arrayify(recipient),
    bridgeAmount,
    metadata,
    gasValue,
    { value: gasValue }
  );
  await tx.wait();
}

/// @dev Bridges native TEL on TN to ERC20 TEL on Sepolia
async function bridgeTNToSepolia(recipient, amount) {
  // must use Axelar contracts's exact matching name. devnet is as follows:
  const destinationChain = "eth-sepolia";
  // native TEL uses 18 decimals
  const bridgeAmount = amount * 1e18;
  // user must first double-wrap native TEL -> wTEL -> iTEL
  const iTELDoubleWrapABI = [
    {
      type: "function",
      name: "doubleWrap",
      inputs: [],
      outputs: [],
      stateMutability: "payable",
    },
  ];
  const iTEL = new ethers.Contract(
    0x28a51e729c8e420123332dcc7c76f865805214de,
    iTELDoubleWrapABI,
    tnProvider
  );
  iTEL.doubleWrap({ value: bridgeAmount });
  // then elapse recoverableWindow before bridging, 1 minute on devnet (will be 1 week on mainnet)
  await sleep(60000);
  // note that the recipient `destinationAddress` must be of `bytes` type, not `address`
  const tx = await interchainTokenService.interchainTransfer(
    interchainTokenId,
    destinationChain,
    ethers.utils.arrayify(recipient),
    bridgeAmount,
    metadata,
    gasValue,
    { value: gasValue }
  );
  await tx.wait();
}

await bridgeSepoliaToTN(recipientAddress, amount);
// or
await bridgeTNToSepolia(recipientAddress, amount);
```

## Relevant Bridging Contract Deployments

All of Axelar's canonical deployments are listed [here](https://github.com/axelarnetwork/axelar-contract-deployments/tree/main/axelar-chains-config/info)

### Amplifier-Devnet Deployments

The Amplifier-Devnet AVM contract deployment addresses for Telcoin-Network use the pre-existing implementations and are as follows:

| Name             | Network          | Address                                                           | CodeId |
| ---------------- | ---------------- | ----------------------------------------------------------------- | ------ |
| Voting Verifier  | Amplifier-Devnet | axelar1kdzmvkjtvu8cct0gzzqdj8jyd6yvlcswauu73ccmvcl0w429xcxqdqst4p | 626    |
| Internal Gateway | Amplifier-Devnet | axelar1ecyaz6vr4hj6qwnza8vh0xuer04jmwxnd4vpewtuju3404hvwv7sdj30zz | 616    |
| Multisig Prover  | Amplifier-Devnet | axelar1e3fr74wrnjfazhqzhq6aehcf8y3gjut9kgac2ufndaqpz32lq5sskln40l | 618    |
