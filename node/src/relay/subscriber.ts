import { readFileSync } from "fs";
import * as https from "https";
import axios from "axios";
import {
  Chain,
  createPublicClient,
  getAddress,
  http,
  Log,
  PublicClient,
} from "viem";
import { sepolia } from "viem/chains";
import axelarAmplifierGatewayArtifact from "../../../artifacts/AxelarAmplifierGateway.json" with { type: "json" };
import * as dotenv from "dotenv";
import { processCLIArgs, targetConfig } from "./utils.js";
dotenv.config();

/// @dev Usage example for subscribing to a target AxelarAmplifierGateway:
/// `npm run subscriber -- --target-chain telcoin-network --target-contract 0xF128c84c3326727c3e155168daAa4C0156B87AD1`

// env config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
const KEY_PATH: string | undefined = process.env.KEY_PATH;
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;

if (!CRT_PATH || !KEY_PATH || !GMP_API_URL) {
  throw new Error("Set all required ENV vars in .env");
}

const CERT = readFileSync(CRT_PATH);
const KEY = readFileSync(KEY_PATH);
const httpsAgent = new https.Agent({ cert: CERT, key: KEY });

let client: PublicClient;
let lastCheckedBlock: bigint;

interface ExtendedLog extends Log {
  eventName: string;
  args: {
    sender: string;
    payloadHash: string;
    destinationChain: string;
    destinationContractAddress: string;
    payload: string;
  };
}

async function main() {
  console.log("Starting up subscriber...");

  const args = process.argv.slice(2);
  processCLIArgs(args);

  console.log(`Subscriber running for ${targetConfig.chain!.name}`);
  console.log(`Subscribed to ${targetConfig.contract}`);

  client = createPublicClient({
    chain: targetConfig.chain,
    transport: http(targetConfig.rpcUrl),
  });

  try {
    const currentBlock = await client.getBlockNumber();
    console.log("Current block (saved as `lastCheckedBlock`): ", currentBlock);

    const terminateSubscriber = client.watchContractEvent({
      address: getAddress(targetConfig.contract!),
      abi: axelarAmplifierGatewayArtifact.abi,
      eventName: "ContractCall",
      fromBlock: currentBlock,
      args: {},
      /*
        args: {
                destinationChain: "telcoin-network",
                destinationContractAddress: "0x07e17e17e17e17e17e17e17e17e17e17e17e17e1",
        }
        */
      onLogs: (logs) => processLogs(logs),
    });

    lastCheckedBlock = currentBlock;
  } catch (err) {
    console.error("Error monitoring events: ", err);
  }
}

async function processLogs(logs: Log[]) {
  // handle axelar's custom nomenclature for sepolia
  let sourceChain = targetConfig.chain!.name.toLowerCase();
  if (targetConfig.chain === sepolia) sourceChain = `eth-${sourceChain}`;

  const events = [];
  for (const log of logs) {
    console.log("New event: ", log);
    const txHash = log.transactionHash;
    const logIndex = log.logIndex;
    const id = `${txHash}-${logIndex}`;

    const extendedLog = log as ExtendedLog;
    const sender = extendedLog.args.sender;
    const payloadHash = extendedLog.args.payloadHash;
    const destinationChain = extendedLog.args.destinationChain;
    const destinationContractAddress =
      extendedLog.args.destinationContractAddress;
    const payload = extendedLog.args.payload;

    // construct array info for API call
    events.push({
      type: "CALL",
      eventID: id,
      message: {
        messageID: id,
        sourceChain: sourceChain,
        sourceAddress: sender,
        destinationAddress: destinationContractAddress,
        payloadHash: payloadHash,
      },
      destinationChain: destinationChain,
      payload: payload,
    });
  }

  try {
    const request = {
      events: events,
    };

    // make post request
    const response = await axios.post(
      `${GMP_API_URL}/chains/${sourceChain}/events`,
      request,
      {
        headers: {
          "Content-Type": "application/json",
        },
        httpsAgent,
      }
    );

    console.log("Success: ", response.data);
  } catch (err) {
    console.error("GMP API error: ", err);
  }
}

main();
