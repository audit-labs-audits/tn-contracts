import { keccak256 } from "viem";
import {
  axelardTxExecute,
  GMPMessage,
  processGmpCLIArgs,
  processTargetCLIArgs,
} from "../utils.js";
import * as dotenv from "dotenv";
dotenv.config();

/**
 * @dev Can be used via CLI or within the TypeScript runtime when imported by another TypeScript file.
 * @dev CLI Usage example for routing GMP messages on an Axelar internal gateway to its multisig prover
 *
 * `npm run route -- \
 *    --source-chain <source_chain> --source-address <source_address> \
 *    --destination-chain <destination_chain> --destination-address <destination_address> \
 *    --payload-hash <payload_hash> --tx-hash <tx_hash> --log-index <log_index>`
 */

export async function route({
  txHash,
  logIndex,
  sourceChain,
  sourceAddress,
  destinationChain,
  destinationAddress,
  payload,
}: GMPMessage): Promise<void> {
  console.log(
    `Instructing ${sourceChain}'s internal gateway to route verified GMP message to ${destinationChain}'s multisig prover`
  );

  processTargetCLIArgs([
    "--target-chain",
    "axelar-devnet",
    "--target-contract",
    sourceChainGateway,
  ]);

  // axelard payloadHash must not be 0x prefixed
  const payloadHash = keccak256(payload!);
  const trimmedPayloadHash = payloadHash!.startsWith("0x")
    ? payloadHash!.slice(2)
    : payloadHash;

  const jsonPayload = JSON.stringify({
    route_messages: [
      {
        cc_id: {
          source_chain: `${sourceChain}`,
          message_id: `${txHash}-${logIndex}`,
        },
        destination_chain: `${destinationChain}`,
        destination_address: `${destinationAddress}`,
        source_address: `${sourceAddress}`,
        payload_hash: `${trimmedPayloadHash}`,
      },
    ],
  });

  await axelardTxExecute(
    sourceChainGateway,
    jsonPayload,
    rpc,
    axelarWallet,
    axelarChainId
  );
}

function main() {
  const args = process.argv.slice(2);
  route(processGmpCLIArgs(args));
}

// supports CLI invocation by checking if being run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
