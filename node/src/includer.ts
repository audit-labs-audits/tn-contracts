import { readFileSync } from "fs";
import {
  createWalletClient,
  http,
  publicActions,
  PublicClient,
  toHex,
  TransactionReceipt,
  WalletClient,
} from "viem";
import { mainnet, sepolia, telcoinTestnet } from "viem/chains";
import * as dotenv from "dotenv";
import { privateKeyToAccount } from "viem/accounts";
dotenv.config();

// todo:
// Amplifier GMP API config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
const KEY_PATH: string | undefined = process.env.KEY_PATH;
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;
// const TN_RPC_URL: string | undefined = process.env.TN_RPC_URL;
// todo: use encrypted keystore
const RELAYER_PK: string | undefined = process.env.RELAYER_PK;
if (!CRT_PATH || !KEY_PATH || !GMP_API_URL || !RELAYER_PK) {
  throw new Error("Set all required ENV vars in .env");
}

const CERT = readFileSync(CRT_PATH);
const KEY = readFileSync(KEY_PATH);
// const httpsAgent = new https.Agent({CERT, KEY});
const relayerAccount = privateKeyToAccount(toHex(RELAYER_PK));

let rpcUrl: string;
let walletClient;
let sourceChain: string = "";
let destinationChain: string = "";
let targetContract: string = "";
let latestTask: string = ""; // optional CLI arg
let pollInterval = 12000; // optional CLI arg, default to mainnet block time

let externalGatewayContract: `0x${string}` =
  "0xbf02955dc36e54fe0274159dbac8a7b79b4e4dc3"; // `== targetContract` (default to Sepolia)

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
  const args = process.argv.slice(2);
  processIncluderCLIArgs(args);
  externalGatewayContract = toHex(targetContract);

  console.log(`Includer running for ${sourceChain} => ${destinationChain}`);
  console.log(`Using relayer address: ${relayerAccount}`);
  console.log(`Including approval transactions bound for ${targetContract}`);

  // poll amplifier Task API for new tasks
  setInterval(async () => {
    const tasks = await fetchTasks();
    if (tasks.length === 0) return;

    for (const task of tasks) {
      await processTask(sourceChain, destinationChain, task);
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
async function processTask(
  sourceChain: string,
  destinationChain: string,
  taskItem: TaskItem
) {
  // todo: check whether new tasks are already executed (ie by another includer)
  walletClient = createWalletClient({
    account: relayerAccount,
    transport: http(rpcUrl),
    chain: telcoinTestnet,
  }).extend(publicActions);

  let txHash: `0x${string}` = "0x";
  if (taskItem.type == "GATEWAY_TX") {
    const executeData = taskItem.task.executeData;
    txHash = await walletClient.sendTransaction({
      to: externalGatewayContract,
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
    return;
  }

  const receipt = await walletClient.waitForTransactionReceipt({
    hash: txHash,
  });

  console.log("Transaction hash: ", txHash);
  console.log("Transaction receipt: ", receipt);

  // inform taskAPI of `GATEWAY_TX` or `EXECUTE` completion
  await recordTaskExecuted(sourceChain, destinationChain, taskItem, receipt);
}

// todo: abstract GMP API functionality to reusable unopinionated file
async function recordTaskExecuted(
  sourceChain: string,
  destinationChain: string,
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
          sourceChain: sourceChain,
          status: "SUCCESSFUL",
        },
      ],
    };

    const response = await fetch(`${GMP_API_URL}/${destinationChain}/events`, {
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

function processIncluderCLIArgs(args: string[]) {
  args.forEach((arg, index) => {
    const valueIndex = index + 1;
    if (arg === "--source-chain" && args[valueIndex]) {
      sourceChain = args[valueIndex];
    }
    if (arg === "--destination-chain" && args[valueIndex]) {
      destinationChain = args[valueIndex];
    }
    if (arg === "--target-contract" && args[valueIndex]) {
      targetContract = args[valueIndex];
    }
    if (arg === "--latest-task" && args[valueIndex]) {
      latestTask = args[valueIndex];
    }
    if (arg === "--poll-interval" && args[valueIndex]) {
      pollInterval = parseInt(args[valueIndex], 10);
    }
  });

  if (!sourceChain || !destinationChain) {
    throw new Error("Must set --source-chain and --destination-chain");
  }
}

main();

/* todo:
    - check whether new tasks are already executed (ie by another includer)
    - use aggregation via Multicall3
    - monitor transaction & adjust gas params if necessary
    - must push latest task ID to some persistent storage as a fallback in the case where the `Includer` goes offline and `taskID` has been consumed at TaskAPI
*/
