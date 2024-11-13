import { readFileSync } from "fs";
import { createPublicClient, http, Log } from "viem";
import axelarAmplifierGatewayArtifact from "../../artifacts/AxelarAmplifierGateway.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

// Amplifier GMP API config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
if (!CRT_PATH) throw new Error("Set cert path in .env");
const CERT = readFileSync(CRT_PATH);
const KEY_PATH: string | undefined = process.env.KEY_PATH;
if (!KEY_PATH) throw new Error("Set key path in .env");
const KEY = readFileSync(KEY_PATH);
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;
if (!GMP_API_URL) throw new Error("Set Axelar GMP api url in .env");

// const httpsAgent = new https.Agent({CERT, KEY}); //todo: onboard to receive mTLS cert first

const TN_RPC_URL: string | undefined = process.env.TN_RPC_URL;
if (!TN_RPC_URL) throw new Error("Set TN rpc url in .env");
const AXL_TN_EXTERNAL_GATEWAY = "0xbf02955dc36e54fe0274159dbac8a7b79b4e4dc3";

const client = createPublicClient({
  transport: http(TN_RPC_URL),
});

let latestTask: string;

async function main() {
  console.log("Starting up includer...");

  // poll amplifier Task API for new tasks
  let urlSuffix: string = "";
  if (latestTask) {
    urlSuffix = `?after=${latestTask}`;
  }
  const url = `${GMP_API_URL}/chains/telcoin-network/tasks${urlSuffix}`;

  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) throw new Error(`HTTP error! Status: ${response.status}`);

    const responseData = await response.json();
    console.log("Success: ", responseData);
  } catch (err) {
    console.error("GMP API error: ", err);
  }

  /*
    - check whether new tasks are already executed (ie by another includer)
    - translate task payload into transaction
    - sign transaction and publish to TN (via RPC or direct-to-node?)
        - use aggregation via Multicall3
    - monitor transaction & adjust gas params if necessary
    - must push latest task ID to some persistent storage as a fallback in the case where the `Includer` goes offline and `taskID` has been consumed at TaskAPI

    */
}

main();
