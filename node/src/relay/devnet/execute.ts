import { exec } from "child_process";
import {
  getKeystoreAccount,
  GMPMessage,
  keystoreAccount,
  processGatewayCLIArgs,
  processTargetCLIArgs,
  Proof,
  targetConfig,
  transactViaEncryptedKeystore,
} from "../utils.js";
import { promisify } from "util";
import yaml from "js-yaml";
import * as dotenv from "dotenv";
import {
  createPublicClient,
  createWalletClient,
  encodeFunctionData,
  http,
  parseAbi,
  publicActions,
  PublicClient,
  toHex,
} from "viem";
dotenv.config();

/**
 * @dev Can be used via CLI or within the TypeScript runtime when imported by another TypeScript file.
 * @dev Usage example for executing an approved cross chain message to the target destination chain
 * @notice InterchainTokenService should be the target contract and the gateway should be `destinationAddress`
 *
 * `npm run execute -- \
 * --target-chain $DEST --target-contract $DEST_ADDR --message-id $MESSAGEID \
 * --source-chain $SRC --source-address $SRC_ADDR --payload $PAYLOAD
 */

export async function execute({
  sourceChain,
  sourceAddress,
  destinationAddress,
  txHash,
  logIndex,
  payload,
}: GMPMessage) {
  console.log("Executing ITS message on target chain");

  getKeystoreAccount();
  const client = createPublicClient({
    chain: targetConfig.chain,
    transport: http(targetConfig.rpcUrl),
  });
  const commandId = await getCommandId(client, {
    destinationAddress,
    txHash,
    logIndex,
  });

  const calldata = encodeFunctionData({
    abi: ["function execute(bytes32 commandId) external"],
    args: [commandId, sourceChain, sourceAddress, payload],
  });
  await transactViaEncryptedKeystore(
    targetConfig.chain!,
    targetConfig.rpcUrl!,
    keystoreAccount.account!,
    targetConfig.contract!,
    0n,
    calldata,
    keystoreAccount.ksPath!,
    keystoreAccount.ksPw!
  );
}

export async function getCommandId(
  client: PublicClient,
  { sourceChain, destinationAddress, txHash, logIndex }: GMPMessage
): Promise<`0x${string}`> {
  const messageId = `${txHash}-${logIndex}`;
  console.log(
    `Retrieving command ID for message ID ${messageId} from ${destinationAddress}`
  );

  const messageToCommandId = parseAbi([
    "function messageToCommandId(string calldata sourceChain, string calldata messageId) external returns (bytes32)",
  ]);
  const commandId = await client.readContract({
    address: destinationAddress,
    abi: messageToCommandId,
    functionName: "messageToCommandId",
    args: [sourceChain, messageId],
    code: "0x",
  });

  return commandId as `0x${string}`;
}

async function main() {
  const args = process.argv.slice(2);
  await execute(processGatewayCLIArgs(args));
}

// supports CLI invocation by checking if being run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
