# Telcoin Network Bridging

Because the Telcoin token $TEL was deployed as an ERC20 token on Ethereum as part of its ICO in 2017, a native bridging mechanism needed to be devised in order to use $TEL as the native currency for Telcoin Network.

At the very highest level, Telcoin Network utilizes four component categories to enable native cross-chain bridging. These are:

- Axelar Gateway and Executable contracts
- [offchain relayers](./relay/README.md)
- [Axelar's "General Message Passing" GMP API](https://www.axelar.network/blog/general-message-passing-and-how-can-it-change-web3)
- [verifiers](./verifier-instructions.md) implemented as the Telcoin Network Non-Voting Validator "NVV" Client

## In a (very abstract) nutshell

### Gateway and Executable Contracts

Each chain that enables cross-chain communication via Axelar Network integrates to the Axelar hub by deploying at minimum two smart contracts: an external gateway contract and an executable contract. For Telcoin Network these are the AxelarAmplifierGateway and the RWTEL module, respectively. The external gateway's role is to both emit outgoing cross-chain messages and to accept incoming cross-chain messages, whereas the RWTEL executable performs the actual $TEL minting (for $TEL incoming from another chain) and locking (for $TEL being sent to another chain).

### Relayers

Relayers are offchain components that handle the transfer of cross-chain messages by monitoring the external gateways for new outbound messages and relaying them to the Axelar GMP API or vice versa. In the reverse case, relayers poll the GMP API for new incoming messages which have been verified by Axelar Network and deliver them to the chain's external gateway as well as execute them through the executable contract via transactions.

### GMP API

The Axelar GMP API abstracts away Axelar Network's internals [which are discussed here](https://forum.telcoin.org/t/light-clients-independent-verification/296/6?u=robriks). Under the hood, the GMP API handles a series of CosmWasm transactions required to push cross-chain messages through various verification steps codified by smart contracts deployed on the Axelar blockchain.

### Verifiers

To validate cross-chain messages within the Axelar chain, whitelisted services called "verifiers" check new messages against their source chain's finality by performing RPC calls to ensure the messages were emitted by the source chain's gateway in a block which has reached finality. The verifiers themselves run a copy of a Telcoin Network Non-Voting Validator client to track TN's execution and consensus, and in turn quorum-vote on whether or not the message in question is finalized.

## User Flow

From a user's perspective, only two transactions are required to initiate the bridging sequence:

1. Approve the token balance to be bridged for the external gateway to spend. This is necessary because the gateway transfers tokens from the user to itself in the subsequent bridge transaction, locking those tokens so they can be delivered and used on the destination chain.

2. Perform a call to the external gateway's `callContractWithToken()` function. This transaction locks the tokens to be bridged in the external gateway, where they remain until the tokens are bridged back from the destination chain.

Telcoin-Network provides a canonical bridge interface for a convenient UI to perform the transactions above, but bridging remains permissionless because it can be performed by any user with TEL tokens on their own. Below is an example for how to do so using ethers:

```javascript
const { ethers } = require("ethers");
const provider = new ethers.providers.JsonRpcProvider(
  "https://source_chain_endpoint"
);

/// @dev This example demonstrates bridging from sepolia -> TN

// Sepolia external gateway
const axlExtGatewayContract = "0xe432150cce91c13a887f7D836923d5597adD8E31";
// must use Axelar’s exact naming convention for each chain. Sepolia is as follows:
const sourceChain = "ethereum-sepolia";
const destinationChain = "telcoin-network";
// this must be the destination chain’s Axelar Executable contract. On TN this is RWTEL
const destinationContractAddress = "0xca568d148d23a4ca9b77bef783dca0d2f5962c12";
// open to user input; generally defaults to the user wallet
const recipientAddress = "0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180";
const erc20Symbol = "TEL";
// must be <= the amount previously approved to the external gateway
const bridgeAmount = 42;

const gatewayCallContractWithTokenABI = [
  {
    inputs: [
      {
        internalType: "string",
        name: "destinationChain",
        type: "string",
      },
      {
        internalType: "string",
        name: "destinationContractAddress",
        type: "string",
      },
      { internalType: "bytes", name: "payload", type: "bytes" },
      { internalType: "string", name: "symbol", type: "string" },
      { internalType: "uint256", name: "amount", type: "uint256" },
    ],
    name: "callContractWithToken",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const axlExtGateway = new ethers.Contract(
  axlExtGatewayContract,
  gatewayCallContractWithTokenABI,
  provider
);

async function bridgeERC20() {
  // bridge txs to TN as destination chain are restricted to 'RWTEL::execute()'
  const executeFuncSignature = "execute(bytes32,string,string,bytes)";
  // parameters for the 'execute' function
  const commandId = ethers.constants.HashZero; // deprecated by axelar- use bytes32(0)
  const sourceAddress = axlExtGatewayContract;

  // payload param must be abi-encoded representation of ExtCall solidity struct below
  /// struct ExtCall {
  ///      address target; // ie recipient
  ///      uint256 value; // ie bridge amount
  ///      bytes data; // empty, but can be used for more granularity in future
  ///  }

  // Define the ExtCall object and abi-encode as solidity struct
  const extCall = {
    target: recipientAddress,
    value: bridgeAmount, // must conform to ERC20 decimals and be <= approved amount
    data: "", // for plain ERC20 bridging, enforce data field to be empty
  };

  const payload = ethers.utils.defaultAbiCoder.encode(
    ["address", "uint256", "bytes"],
    [extCall.target, extCall.value, extCall.data]
  );

  // ABI encode the outer function call using previously defined parameters
  const abiEncodedExecuteParams = ethers.utils.defaultAbiCoder.encode(
    ["bytes32", "string", "string", "bytes"],
    [commandId, sourceChain, sourceAddress, payload]
  );

  // hash signature & slice first 10 chars (‘0x’ + 4-byte func selector)
  const execFuncSelector = ethers.utils.id(execFuncSignature).slice(0, 10);
  // concatenate the function selector with the encoded data (less the ‘0x’)
  const transactionData = functionSelector + abiEncodedFuncParams.slice(2);

  const tx = await axlExtGateway.callContractWithToken(
    destinationChain,
    destinationContractAddress,
    payload,
    erc20Symbol,
    bridgeAmount
  );
  await tx.wait();
}

await bridgeERC20();
```

## Relevant Bridging Contract Deployments

All of Axelar's canonical deployments are listed [here](https://github.com/axelarnetwork/axelar-contract-deployments/tree/main/axelar-chains-config/info)

### EVM Network Deployments

Please note that the Telcoin-Network deployments are being iterated on and liable to change, leaving their entries in the following table outdated. For canonical deployments on TN which are guaranteed to be up to date, refer to `deployments/deployments.json`

| Name          | Network         | Address                                    |
| ------------- | --------------- | ------------------------------------------ |
| Gateway Proxy | Sepolia         | 0xe432150cce91c13a887f7D836923d5597adD8E31 |
| Gateway Impl  | Sepolia         | 0xc1712652326E87D193Ac11910934085FF45C2F48 |
| Gateway Proxy | Ethereum        | 0x4F4495243837681061C4743b74B3eEdf548D56A5 |
| Gateway Impl  | Ethereum        | 0x99B5FA03a5ea4315725c43346e55a6A6fbd94098 |
| Gateway Proxy | Polygon         | 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8 |
| Gateway Impl  | Polygon         | 0x99B5FA03a5ea4315725c43346e55a6A6fbd94098 |
| Gateway Proxy | Telcoin-Network | 0xbf02955dc36e54fe0274159dbac8a7b79b4e4dc3 |
| Gateway Impl  | Telcoin-Network | 0xd118b3966488e29008e7355fc9090c5bca9fdef8 |
| RWTEL (exec)  | Telcoin-Network | 0xca568d148d23a4ca9b77bef783dca0d2f5962c12 |

### Amplifier-Devnet Deployments

The Amplifier-Devnet AVM contract deployment addresses for Telcoin-Network use the pre-existing implementations and are as follows:

| Name             | Network          | Address                                                           | CodeId |
| ---------------- | ---------------- | ----------------------------------------------------------------- | ------ |
| Voting Verifier  | Amplifier-Devnet | axelar1n2g7xr4wuy4frc0936vtqhgr0fyklc0rxhx7qty5em2m2df47clsxuvtxx | 626    |
| Internal Gateway | Amplifier-Devnet | axelar16zy7kl6nv8zk0racw6nsm6n0yl7h02lz4s9zz4lt8cfl0vxhfp8sqmtqcr | 616    |
| Multisig Prover  | Amplifier-Devnet | axelar162t7mxkcnu7psw7qxlsd4cc5u6ywm399h8xg6qhgseg8nq6qhf6s7q8m0e | 618    |
