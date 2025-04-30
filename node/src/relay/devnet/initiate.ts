import {
  createWalletClient,
  getAddress,
  http,
  Chain,
  PublicClient,
  WalletClient,
  Address,
  publicActions,
  getAbiItem,
  encodeFunctionData,
  parseAbi,
} from "viem";
import * as dotenv from "dotenv";
import { processCLIArgs, targetConfig } from "../utils.js";
import { privateKeyToAccount } from "viem/accounts";

dotenv.config();

/// @dev Usage example for initiating GMP msgs on a target AxelarAmplifierGateway:
/// `npm run initiate -- --target-chain sepolia --target-contract 0xF128c84c3326727c3e155168daAa4C0156B87AD1`

const privateKey: Address = process.env.PK as `0x${string}`;
if (!privateKey) {
  throw new Error("Private key not set in .env");
}
let walletClient: WalletClient;

let amount: bigint = 0n;
let destinationChain: `0x${string}`;
let destinationContract: `0x${string}`;
let payload: `0x${string}`;

async function main() {
  console.log("Initiating interchain GMP message");

  const args = process.argv.slice(2);
  processInitiateCLIArgs(args);

  console.log(`Initiating transaction on ${targetConfig.chain!.name}`);
  console.log(`Target contract: ${targetConfig.contract}`);

  const account = privateKeyToAccount(privateKey!);
  walletClient = createWalletClient({
    account,
    chain: targetConfig.chain,
    transport: http(targetConfig.rpcUrl),
  });

  try {
    const callContract = parseAbi([
      "function callContract(string calldata destinationChain, string calldata destinationContractAddress,bytes calldata payload) external",
    ]);
    const calldata = encodeFunctionData({
      abi: callContract,
      functionName: "callContract",
      args: [destinationChain, destinationContract, payload],
    });
    const txHash = await walletClient.sendTransaction({
      account: account,
      chain: targetConfig.chain,
      to: targetConfig.contract!,
      value: amount,
      data: calldata,
    });

    console.log("Transaction sent: ", txHash);

    const receipt = await walletClient
      .extend(publicActions)
      .waitForTransactionReceipt({ hash: txHash });
    console.log("Transaction confirmed: ", receipt.transactionHash);
  } catch (err) {
    console.error("Error sending transaction: ", err);
  }
}

function processInitiateCLIArgs(args: string[]) {
  processCLIArgs(args);

  let destChainSet = false;
  let destContractSet = false;
  let payloadSet = false;
  args.forEach((arg, index) => {
    const valueIndex = index + 1;

    if (arg == "--amount" && args[valueIndex]) {
      amount = BigInt(args[valueIndex]);
    }
    if (arg == "--destination-chain" && args[valueIndex]) {
      destinationChain = args[valueIndex] as `0x${string}`;
      destChainSet = true;
    }
    if (arg == "--destination-contract" && args[valueIndex]) {
      destinationContract = args[valueIndex] as `0x${string}`;
      destContractSet = true;
    }
    if (arg == "--payload" && args[valueIndex]) {
      payload = args[valueIndex] as `0x${string}`;
      payloadSet = true;
    }

    if (!destChainSet || !destContractSet || !payloadSet) {
      throw new Error(
        "Must set --destination-chain, --destination-contract, and --payload"
      );
    }
  });
}

main();
