import { createPublicClient, http, Log } from "viem";
import { mainnet } from "viem/chains";
import axelarAmplifierGatewayArtifact from "../../artifacts/AxelarAmplifierGateway.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

// const CERT = fs.readFileSync(process.env.CRT_PATH);
// const KEY = fs.readFileSync(process.env.KEY_PATH);
const GMP_API_URL = process.env.GMP_API_URL;
const MAINNET_RPC_URL: string | undefined = process.env.MAINNET_RPC_URL;
if (!MAINNET_RPC_URL) throw new Error("Set mainnet rpc url in .env");
const AXL_ETH_EXTERNAL_GATEWAY = "0x4F4495243837681061C4743b74B3eEdf548D56A5";

const client = createPublicClient({
  chain: mainnet,
  transport: http(MAINNET_RPC_URL),
});
// const httpsAgent = new https.Agent({CERT, KEY});

let lastCheckedBlock: bigint;

async function main() {
  try {
    const currentBlock = await client.getBlockNumber();

    const watch = client.watchContractEvent({
      address: AXL_ETH_EXTERNAL_GATEWAY,
      abi: axelarAmplifierGatewayArtifact.abi,
      eventName: "ContractCall",
      fromBlock: currentBlock,
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
      // todo: processing
      console.log("sender:", log.topics[0]);
      const sender = log.topics[0];
      console.log("payloadHash?:", log.topics[1]);
      const payloadHash = log.topics[1];
      console.log("destinationChain?:", log.data);
      const destinationAddress = log.data; // todo
      // const payload= log.data; //todo

      const txHash = "";
      const logIndex = "";
      const id = `${txHash}-${logIndex}`;

      // construct info for API call
      const request = {
        events: [
          {
            type: "CALL",
            eventID: id,
            message: {
              messageID: id,
              sourceChain: "ethereum",
              sourceAddress: sender,
              destinationAddress: destinationAddress,
              payloadHash: payloadHash,
            },
            destinationChain: "Telcoin-Network",
            payload: "",
          },
        ],
      };

      // make post request to gmpApiUrl/chains/telcoin-network/events
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

main();
