import { readFileSync } from "fs";
import {
  createWalletClient,
  http,
  publicActions,
  TransactionReceipt,
} from "viem";
import { forma, mainnet, sepolia, telcoinTestnet } from "viem/chains";
import * as dotenv from "dotenv";
import { privateKeyToAccount } from "viem/accounts";
dotenv.config();

// todo:
// Amplifier GMP API config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
if (!CRT_PATH) throw new Error("Set cert path in .env");
const CERT = readFileSync(CRT_PATH);
const KEY_PATH: string | undefined = process.env.KEY_PATH;
if (!KEY_PATH) throw new Error("Set key path in .env");
const KEY = readFileSync(KEY_PATH);
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;
if (!GMP_API_URL) throw new Error("Set Axelar GMP api url in .env");

// const httpsAgent = new https.Agent({CERT, KEY});

const TN_RPC_URL: string | undefined = process.env.TN_RPC_URL;
if (!TN_RPC_URL) throw new Error("Set TN rpc url in .env");
const AXL_TN_EXTERNAL_GATEWAY = "0xbf02955dc36e54fe0274159dbac8a7b79b4e4dc3";
// todo: use encrypted keystore
const RELAYER_PK: string | undefined = process.env.RELAYER_PK;
if (!RELAYER_PK) throw new Error("Set relayer private key in .env");

const relayerAccount = privateKeyToAccount(`0x${RELAYER_PK}`);
const walletClient = createWalletClient({
  account: relayerAccount,
  transport: http(TN_RPC_URL),
  chain: telcoinTestnet,
}).extend(publicActions);

let latestTask: string;
let pollInterval = 12000;
// let sourceChain: string = CLI arg
// let destinationChain: string = CLI arg

interface TaskItem {
  id: string;
  timestamp: string;
  type: string;
  task: {
    executeData: `0x${string}`;
    message: {
      messageID: string;
      sourceAddress: `0x${string}`;
      destinationAddress: `0x${string}`; // RWTEL module
    };
    payload: `0x${string}`;
  };
}

async function main() {
  console.log("Starting up includer...");

  // poll amplifier Task API for new tasks
  setInterval(async () => {
    const tasks = await fetchTasks();
    if (tasks.length === 0) return;

    for (const task of tasks) {
      await processTask(task);
    }
  }, pollInterval);
}

async function fetchTasks() {
  let urlSuffix: string = "";
  if (latestTask) {
    urlSuffix = `?after=${latestTask}`;
  }
  const url = `${GMP_API_URL}/chains/telcoin-network/tasks${urlSuffix}`;

  // call API endpoint
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) throw new Error(`HTTP error! Status: ${response.status}`);

    const responseData = await response.json();
    console.log("Response from Amplifier GMP API: ", responseData);

    const tasks = responseData.data.tasks;
    return tasks;
  } catch (err) {
    console.error("GMP API error: ", err);
  }
}

// process both approvals and executes
async function processTask(taskItem: TaskItem) {
  // todo: check whether new tasks are already executed (ie by another includer)
  let txHash: `0x${string}` = "0x";

  if (taskItem.type == "GATEWAY_TX") {
    const executeData = taskItem.task.executeData;
    txHash = await walletClient.sendTransaction({
      to: AXL_TN_EXTERNAL_GATEWAY,
      data: executeData,
      chain: telcoinTestnet,
    });
  } else if (taskItem.type == "EXECUTE") {
    // must == RWTEL
    const destinationAddress = taskItem.task.message.destinationAddress;
    const payload = taskItem.task.payload;
    txHash = await walletClient.sendTransaction({
      to: destinationAddress,
      data: payload,
      chain: telcoinTestnet,
    });
  } else {
    console.warn("Unknown task type: ", taskItem.type);
  }

  const receipt = await walletClient.waitForTransactionReceipt({
    hash: txHash,
  });

  // inform taskAPI of `GATEWAY_TX` or `EXECUTE` completion
  await recordTaskExecuted(taskItem, receipt);

  console.log("Transaction hash: ", txHash);
  console.log("Transaction receipt: ", receipt);
}

// todo: abstract GMP API functionality to reusable unopinionated file
async function recordTaskExecuted(
  taskItem: TaskItem,
  txReceipt: TransactionReceipt
) {
  // make post request // todo: onboard to receive api key first
  try {
    const request = {
      events: [
        {
          type: taskItem.type,
          eventID: taskItem.id,
          messageID: taskItem.task.message.messageID,
          meta: {
            fromAddress: txReceipt.from,
            txID: txReceipt.transactionHash,
            finalized: true,
          },
          sourceChain: "ethereum", // todo: enable two-way inclusion via CLI
          status: "SUCCESSFUL",
        },
      ],
    };

    //todo: change 'telcoin-network' to `${destinationChain}` from CLI arg
    const response = await fetch(`${GMP_API_URL}/telcoin-network/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(request),
    });

    if (!response.ok) throw new Error(`HTTP error! Status: ${response.status}`);

    const responseData = await response.json();
    console.log("Success: ", responseData);
  } catch (err) {
    console.error("GMP API Error: ", err);
  }
}

main();

/* todo:
    - check whether new tasks are already executed (ie by another includer)
    - use aggregation via Multicall3
    - monitor transaction & adjust gas params if necessary
    - must push latest task ID to some persistent storage as a fallback in the case where the `Includer` goes offline and `taskID` has been consumed at TaskAPI
*/
