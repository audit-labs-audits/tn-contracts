import { exec } from "child_process";
import { GMPMessage } from "../utils.js";

/**
 * @dev Can be used via CLI or within the TypeScript runtime when imported by another TypeScript file.
 * @dev Usage example for constructing proofs on a destination chain's multisig prover:
 *
 * `npm run construct-proof -- \
 *    --source-chain <source_chain> --tx-hash <tx_hash> --log-index <log_index>`
 */

// when migrating beyond devnet these can be initialized via CLI flag
let rpc: string = "http://devnet-amplifier.axelar.dev:26657";
let axelarWallet: string = "axelard-test-wallet"; //todo
let axelarChainId: string = "devnet-amplifier";

export async function constructProof({
  txHash,
  logIndex,
  sourceChain,
  destinationChainMultisigProver,
}: GMPMessage): Promise<void> {
  console.log(
    `Instructing destination chain's multisig prover ${destinationChainMultisigProver} to construct GMP message proof`
  );

  // Construct the axelard command
  const axelardCommand = `axelard tx wasm execute ${destinationChainMultisigProver} \
    '{
        "construct_proof":
          [
            {
              "source_chain":"${sourceChain}",
              "message_id":"${txHash}-${logIndex}"
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

// returns values for `constructProof()`; only used if invoked via command line
function processConstructProofCLIArgs(args: string[]) {
  let sourceChain: string | undefined;
  let txHash: `0x${string}` | undefined;
  let logIndex: number | undefined;
  let destinationChainMultisigProver: string | undefined;

  args.forEach((arg, index) => {
    const valueIndex = index + 1;
    switch (arg) {
      case "--source-chain":
        sourceChain = args[valueIndex];
        break;
      case "--tx-hash":
        txHash = args[valueIndex] as `0x${string}`;
        break;
      case "--log-index":
        logIndex = parseInt(args[valueIndex], 10);
        break;
      case "--destination-chain-multisig-prover":
        destinationChainMultisigProver = args[valueIndex];
        break;
    }
  });

  if (
    !sourceChain ||
    !txHash ||
    logIndex === undefined ||
    !destinationChainMultisigProver
  ) {
    throw new Error(
      "Must set --source-chain, --tx-hash, --log-indexm --destination-chain-multisig-prover"
    );
  }

  return {
    txHash,
    logIndex,
    sourceChain,
    destinationChainMultisigProver,
  };
}

function main() {
  const args = process.argv.slice(2);
  constructProof(processConstructProofCLIArgs(args));
}

// supports CLI invocation by checking if being run directly
if (require.main === module) {
  main();
}
