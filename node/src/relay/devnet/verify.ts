import { exec } from "child_process";
import { GMPMessage } from "../utils.js";

/**
 * @dev Can be used via CLI or within typescript runtime when imported by another typescript file
 * @dev CLI Usage example for verifying GMP messages on an Axelar internal gateway:
 *
 * `npm run verify -- \
 *    --source-chain <source_chain> --source-address <source_address> \
 *    --destination-chain <destination_chain> --destination-address <destination_address> \
 *    --payload-hash <payload_hash> --tx-hash <tx_hash> --log-index <log_index>`
 */

// when migrating beyond devnet these can be initialized via CLI flag
let rpc: string = "http://devnet-amplifier.axelar.dev:26657";
let axelarWallet: string = "axelard-test-wallet";
let axelarChainId: string = "devnet-amplifier";
let axelarInternalGateway: string =
  "axelar1ecyaz6vr4hj6qwnza8vh0xuer04jmwxnd4vpewtuju3404hvwv7sdj30zz";

export async function verify({
  txHash,
  logIndex,
  sourceChain,
  sourceAddress,
  destinationChain,
  destinationAddress,
  payloadHash,
}: GMPMessage): Promise<void> {
  console.log(
    `Instructing ${sourceChain}'s internal gateway to commence verification on its paired voting verifier`
  );

  // axelard payloadHash must not be 0x prefixed
  const trimmedPayloadHash = payloadHash!.startsWith("0x")
    ? payloadHash!.slice(2)
    : payloadHash;

  // construct and exec axelard binary cmd
  const axelardCommand = `axelard tx wasm execute ${axelarInternalGateway} \
    '{
        "verify_messages":
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

// returns values for `verify()`; only used if invoked via command line
export function processInternalGatewayCLIArgs(args: string[]) {
  let sourceChain: string | undefined;
  let sourceAddress: `0x${string}` | undefined;
  let destinationChain: string | undefined;
  let destinationAddress: `0x${string}` | undefined;
  let payloadHash: `0x${string}` | undefined;
  let txHash: `0x${string}` | undefined;
  let logIndex: number | undefined;

  args.forEach((arg, index) => {
    const valueIndex = index + 1;
    switch (arg) {
      case "--source-chain":
        sourceChain = args[valueIndex];
        break;
      case "--source-address":
        sourceAddress = args[valueIndex] as `0x${string}`;
        break;
      case "--destination-chain":
        destinationChain = args[valueIndex];
        break;
      case "--destination-address":
        destinationAddress = args[valueIndex] as `0x${string}`;
        break;
      case "--payload-hash":
        payloadHash = args[valueIndex] as `0x${string}`;
        break;
      case "--tx-hash":
        txHash = args[valueIndex] as `0x${string}`;
        break;
      case "--log-index":
        logIndex = parseInt(args[valueIndex], 10);
        break;
    }
  });

  if (
    !sourceChain ||
    !sourceAddress ||
    !destinationChain ||
    !destinationAddress ||
    !payloadHash ||
    !txHash ||
    logIndex === undefined
  ) {
    throw new Error(
      "Must set --source-chain, --source-address, --destination-chain, --destination-address, --payload-hash, --tx-hash, and --log-index"
    );
  }

  return {
    txHash,
    logIndex,
    sourceChain,
    sourceAddress,
    destinationChain,
    destinationAddress,
    payloadHash,
  };
}

function main() {
  const args = process.argv.slice(2);
  verify(processInternalGatewayCLIArgs(args));
}
// supports CLI invocation by checking if being run directly
if (require.main === module) {
  main();
}
