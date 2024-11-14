import { readFileSync } from "fs";
import { createPublicClient, http, Log } from "viem";
import { mainnet } from "viem/chains";
import axelarAmplifierGatewayArtifact from "../../artifacts/AxelarAmplifierGateway.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

// env config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
if (!CRT_PATH) throw new Error("Set cert path in .env");
const CERT = readFileSync(CRT_PATH);
const KEY_PATH: string | undefined = process.env.KEY_PATH;
if (!KEY_PATH) throw new Error("Set key path in .env");
const KEY = readFileSync(KEY_PATH);
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;
if (!GMP_API_URL) throw new Error("Set Axelar GMP api url in .env");

// const httpsAgent = new https.Agent({CERT, KEY});

// mainnet
// const MAINNET_RPC_URL: string | undefined = process.env.MAINNET_RPC_URL;
// if (!MAINNET_RPC_URL) throw new Error("Set mainnet rpc url in .env");
// const AXL_ETH_EXTERNAL_GATEWAY = "0x4F4495243837681061C4743b74B3eEdf548D56A5";

// testnet
const SEPOLIA_RPC_URL: string | undefined = process.env.SEPOLIA_RPC_URL;
if (!SEPOLIA_RPC_URL) throw new Error("Set mainnet rpc url in .env");
const AXL_SEPOLIA_EXTERNAL_GATEWAY =
  "0xBf02955Dc36E54Fe0274159DbAC8A7B79B4e4dc3";

const client = createPublicClient({
  chain: mainnet,
  transport: http(SEPOLIA_RPC_URL), // MAINNET_RPC_URL
});

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
  try {
    const currentBlock = await client.getBlockNumber();
    console.log("Current block: ", currentBlock);

    const terminateSubscriber = client.watchContractEvent({
      address: AXL_SEPOLIA_EXTERNAL_GATEWAY, //AXL_ETH_EXTERNAL_GATEWAY,
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

      // make post request // todo: onboard to receive api key first
      //   const response = await fetch(`${GMP_API_URL}/ethereum/events`, {
      //     method: "POST",
      //     headers: {
      //       "Content-Type": "application/json",
      //     },
      //     body: JSON.stringify(request),
      //   });

      //   if (!response.ok)
      //     throw new Error(`HTTP error! Status: ${response.status}`);

      //   const responseData = await response.json();
      //   console.log("Success: ", responseData);
    } catch (err) {
      console.error("GMP API error: ", err);
    }
  }
}

main();
