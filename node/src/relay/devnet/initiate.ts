import {
  createWalletClient,
  http,
  WalletClient,
  Address,
  publicActions,
  encodeFunctionData,
  parseAbi,
} from "viem";
import * as dotenv from "dotenv";
import { processCLIArgs, targetConfig } from "../utils.js";
import { privateKeyToAccount } from "viem/accounts";
dotenv.config();

/**
 * @dev This function can be used via CLI or within the TypeScript runtime when imported by another TypeScript file.
 * Usage example for initiating GMP message flow on a target AxelarAmplifierGateway:
 *
 * `npm run initiate -- \
 *    --target-chain <target_chain> --target-contract <target_contract>`
 */

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

  console.log(
    `Sending GMP message from ${
      targetConfig.chain!.name
    } to ${destinationChain}`
  );

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

  args.forEach((arg, index) => {
    const valueIndex = index + 1;
    switch (arg) {
      case "--amount":
        amount = BigInt(args[valueIndex]);
        break;
      case "--destination-chain":
        destinationChain = args[valueIndex] as `0x${string}`;
        break;
      case "--destination-contract":
        destinationContract = args[valueIndex] as `0x${string}`;
        break;
      case "--payload":
        payload = args[valueIndex] as `0x${string}`;
        break;
    }
  });

  if (!destinationChain || !destinationContract || !payload) {
    throw new Error(
      "Must set --destination-chain, --destination-contract, and --payload"
    );
  }
}

main();
