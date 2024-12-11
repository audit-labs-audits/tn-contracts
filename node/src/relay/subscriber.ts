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
import { mainnet, sepolia, telcoinTestnet } from "viem/chains";
import axelarAmplifierGatewayArtifact from "../../../artifacts/AxelarAmplifierGateway.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

/// @dev Usage example for subscribing to the RWTEL contract on TN:
/// `npm run subscriber -- --target-chain telcoin-network --target-contract 0xca568d148d23a4ca9b77bef783dca0d2f5962c12`

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

let rpcUrl: string;
let client: PublicClient;
let targetChain: Chain;
let targetContract: string;

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
  processSubscriberCLIArgs(args);

  console.log(`Subscriber running for ${targetChain.name}`);
  console.log(`Subscribed to ${targetContract}`);

  client = createPublicClient({
    chain: targetChain,
    transport: http(rpcUrl),
  });

  try {
    const currentBlock = await client.getBlockNumber();
    console.log("Current block (saved as `lastCheckedBlock`): ", currentBlock);

    const terminateSubscriber = client.watchContractEvent({
      address: getAddress(targetContract),
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
  let sourceChain = targetChain.name.toLowerCase();
  if (targetChain === sepolia) sourceChain = `ethereum-${sourceChain}`;

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

function processSubscriberCLIArgs(args: string[]) {
  args.forEach((arg, index) => {
    const valueIndex = index + 1;

    // parse target chain for subscription
    if (arg === "--target-chain" && args[valueIndex]) {
      if (args[valueIndex] === "sepolia") {
        targetChain = sepolia;
        const sepoliaRpcUrl = process.env.SEPOLIA_RPC_URL;
        if (!sepoliaRpcUrl) throw new Error("Sepolia RPC URL not in .env");
        rpcUrl = sepoliaRpcUrl;
      } else if (args[valueIndex] === "ethereum") {
        targetChain = mainnet;
        const mainnetRpcUrl = process.env.MAINNET_RPC_URL;
        if (!mainnetRpcUrl) throw new Error("Mainnet RPC URL not in .env");
        rpcUrl = mainnetRpcUrl;
      } else if (args[valueIndex] === "telcoin-network") {
        targetChain = telcoinTestnet;
        const tnRpcUrl = process.env.TN_RPC_URL;
        if (!tnRpcUrl) throw new Error("Sepolia RPC URL not in .env");
        rpcUrl = tnRpcUrl;
      }
    }

    // parse target contract to watch
    if (arg === "--target-contract" && args[valueIndex]) {
      targetContract = args[valueIndex];
    }
  });

  if (!targetChain || !targetContract) {
    throw new Error("Must set --target-chain and --target-contract");
  }
}

main();
