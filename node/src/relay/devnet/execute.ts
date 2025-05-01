import { exec } from "child_process";
import { GMPMessage } from "../utils.js";

/**
 * @dev Can be used via CLI or within the TypeScript runtime when imported by another TypeScript file.
 * @dev Usage example for fetching and settlingproofs from a destination chain's multisig prover
 *
 * `npm run get-proof -- \
 *    --multisig-session-id <multisig_session_id>`
 */

// Initialize configuration variables, replacing hardcoded values
let rpc: string = "http://devnet-amplifier.axelar.dev:26657";

export async function getProof({
  destinationChainMultisigProver,
  multisigSessionId,
}: GMPMessage): Promise<void> {
  console.log(
    `Retrieving proof for multisig session ID ${multisigSessionId} from prover ${destinationChainMultisigProver}`
  );

  // Construct the axelard command
  const axelardCommand = `axelard q wasm contract-state smart ${destinationChainMultisigProver} \
    '{
        "get_proof":{
            "multisig_session_id":"${multisigSessionId}"
        }
    }' \
    --node ${rpc}`;

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

// returns values for `getProof()`; only used if invoked via command line
function processExecuteCLIArgs(args: string[]): GMPMessage {
  let multisigSessionId: string | undefined;
  let destinationChainMultisigProver: string | undefined;

  args.forEach((arg, index) => {
    const valueIndex = index + 1;
    switch (arg) {
      case "--multisig-session-id":
        multisigSessionId = args[valueIndex];
        break;
      case "--destination-chain-multisig-prover":
        destinationChainMultisigProver = args[valueIndex];
        break;
    }
  });

  if (!multisigSessionId || !destinationChainMultisigProver) {
    throw new Error(
      "Must set --multisig-session-id and --destination-chain-multisig-prover"
    );
  }

  return { multisigSessionId, destinationChainMultisigProver };
}

function main() {
  const args = process.argv.slice(2);
  getProof(processExecuteCLIArgs(args));
}

// supports CLI invocation by checking if being run directly
if (require.main === module) {
  main();
}
