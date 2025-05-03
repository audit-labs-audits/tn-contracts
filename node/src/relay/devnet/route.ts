import { exec } from "child_process";
import { GMPMessage } from "../utils.js";
import { processInternalGatewayCLIArgs } from "./verify.js";

/**
 * @dev Can be used via CLI or within the TypeScript runtime when imported by another TypeScript file.
 * @dev CLI Usage example for routing GMP messages on an Axelar internal gateway to its multisig prover
 *
 * `npm run route -- \
 *    --source-chain <source_chain> --source-address <source_address> \
 *    --destination-chain <destination_chain> --destination-address <destination_address> \
 *    --payload-hash <payload_hash> --tx-hash <tx_hash> --log-index <log_index>`
 */

// when migrating beyond devnet these can be initialized via CLI flag
let rpc: string = "http://devnet-amplifier.axelar.dev:26657";
let axelarWallet: string = "axelard-test-wallet"; //todo change to devnet
let axelarChainId: string = "devnet-amplifier";
let sourceChainGateway: string =
  "axelar1r2s8ye304vtyhfgajljdjj6pcpeya7jwdn9tgw8wful83uy2stnqk4x7ya";

export async function route({
  txHash,
  logIndex,
  sourceChain,
  sourceAddress,
  destinationChain,
  destinationAddress,
  payloadHash,
}: GMPMessage): Promise<void> {
  console.log(
    `Instructing ${sourceChain}'s internal gateway to route verified GMP message to ${destinationChain}'s multisig prover`
  );

  // axelard payloadHash must not be 0x prefixed
  const trimmedPayloadHash = payloadHash!.startsWith("0x")
    ? payloadHash!.slice(2)
    : payloadHash;

  // construct and exec axelard binary cmd
  const axelardCommand = `axelard tx wasm execute ${sourceChainGateway} \
    '{
        "route_messages":
          [
            {
              "cc_id":
                {
                  "source_chain":"${sourceChain}",
                  "message_id":"${txHash}-${logIndex}"
                },
              "destination_chain":"${destinationChain}",
              "destination_address":"${destinationAddress}",
              "source_address":"${sourceAddress}",
              "payload_hash":"${trimmedPayloadHash}"
            }
          ]
    }' \
    --from ${axelarWallet} \
    --keyring-backend file \
    --node ${rpc} \
    --chain-id ${axelarChainId} \
    --gas-prices 0.00005uamplifier \
    --gas auto --gas-adjustment 1.5`;

  exec(axelardCommand, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error executing command: ${error.message}`);
      return;
    }
    if (stderr) {
      console.error(`Error in command output: ${stderr}`);
      return;
    }
    console.log(`Command output: ${stdout}`);
  });
}

function main() {
  const args = process.argv.slice(2);
  route(processInternalGatewayCLIArgs(args));
}

// supports CLI invocation by checking if being run directly
if (require.main === module) {
  main();
}
