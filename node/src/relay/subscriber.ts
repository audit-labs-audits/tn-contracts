import { readFileSync } from "fs";
import {
  Chain,
  createPublicClient,
  http,
  Log,
  PublicClient,
  toHex,
} from "viem";
import { mainnet, sepolia, telcoinTestnet } from "viem/chains";
import axelarAmplifierGatewayArtifact from "../../artifacts/AxelarAmplifierGateway.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

// env config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
const KEY_PATH: string | undefined = process.env.KEY_PATH;
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;

if (!CRT_PATH || !KEY_PATH || !GMP_API_URL) {
  throw new Error("Set all required ENV vars in .env");
}

const CERT = readFileSync(CRT_PATH);
const KEY = readFileSync(KEY_PATH);
// const httpsAgent = new https.Agent({CERT, KEY});

let rpcUrl: string;
let client: PublicClient;
let targetChain: Chain;
let targetContract: string;

let externalGatewayContract: `0x${string}` =
  "0xBf02955Dc36E54Fe0274159DbAC8A7B79B4e4dc3"; // `== targetContract` (default to Sepolia)
// const AXL_ETH_EXTERNAL_GATEWAY = "0x4F4495243837681061C4743b74B3eEdf548D56A5";

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
  externalGatewayContract = toHex(targetContract);

  console.log(`Subscriber running for ${targetChain}`);
  console.log(`Subscribed to ${targetContract}`);

  client = createPublicClient({
    chain: targetChain,
    transport: http(rpcUrl),
  });

  try {
    const currentBlock = await client.getBlockNumber();
    console.log("Current block: ", currentBlock);

    const terminateSubscriber = client.watchContractEvent({
      address: externalGatewayContract,
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
  for (const log of logs) {
    try {
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

      // construct info for API call
      const request = {
        // todo: make a single API request for all logs
        events: [
          {
            type: "CALL",
            eventID: id,
            message: {
              messageID: id,
              sourceChain: "ethereum",
              sourceAddress: sender,
              destinationAddress: destinationContractAddress,
              payloadHash: payloadHash,
            },
            destinationChain: destinationChain,
            payload: payload,
          },
        ],
      };

      // make post request
      const response = await fetch(`${GMP_API_URL}/ethereum/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(request),
      });

      if (!response.ok)
        throw new Error(`HTTP error! Status: ${response.status}`);

      const responseData = await response.json();
      console.log("Success: ", responseData);
    } catch (err) {
      console.error("GMP API error: ", err);
    }
  }
}

function processSubscriberCLIArgs(args: string[]) {
  args.forEach((arg, index) => {
    const valueIndex = index + 1;
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

    if (arg === "--target-contract" && args[valueIndex]) {
      targetContract = args[valueIndex];
    }
  });

  if (!targetChain || !targetContract) {
    throw new Error("Must set --target-chain and --target-contract");
  }
}

main();
