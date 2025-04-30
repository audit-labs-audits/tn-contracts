import { execSync } from "child_process";
import { readFileSync, writeFile } from "fs";
import * as https from "https";
import axios from "axios";
import {
  createWalletClient,
  http,
  keccak256,
  parseSignature,
  publicActions,
  serializeTransaction,
  getAddress,
  TransactionReceipt,
  TransactionRequest,
  TransactionSerializable,
  Chain,
  Address,
} from "viem";
import { sepolia } from "viem/chains";
import * as dotenv from "dotenv";
import { processCLIArgs, targetConfig } from "./utils.js";
dotenv.config();

/// @dev Usage example for including GMP API tasks as transactions to the Axelar sepolia gateway:
/// `npm run includer -- --source-chain telcoin-network --destination-chain sepolia --target-contract 0xe432150cce91c13a887f7D836923d5597adD8E31`

// Amplifier GMP API config
const CRT_PATH: string | undefined = process.env.CRT_PATH;
const KEY_PATH: string | undefined = process.env.KEY_PATH;
const GMP_API_URL: string | undefined = process.env.GMP_API_URL;
const KEYSTORE_PATH: string | undefined = process.env.KEYSTORE_PATH;
const KS_PW: string | undefined = process.env.KS_PW;
const RELAYER: string | undefined = process.env.RELAYER;
if (
  !CRT_PATH ||
  !KEY_PATH ||
  !GMP_API_URL ||
  !KEYSTORE_PATH ||
  !KS_PW ||
  !RELAYER
) {
  throw new Error("Set all required ENV vars in .env");
}

const CERT = readFileSync(CRT_PATH);
const KEY = readFileSync(KEY_PATH);
const httpsAgent = new https.Agent({ cert: CERT, key: KEY });

let walletClient;
let relayerAccount: Address = RELAYER as `0x${string}`;
let latestTask: string = ""; // optional CLI arg
let pollInterval = 12000; // optional CLI arg, default to mainnet block time

interface TaskItem {
  id: string;
  timestamp: string;
  type: string;
  task: {
    executeData: string;
    message: {
      messageID: string;
      sourceChain: string;
      sourceAddress: `0x${string}`;
      destinationAddress: `0x${string}`; // RWTEL module
    };
    payload: string;
  };
}

async function main() {
  console.log("Starting up includer...");
  const args = process.argv.slice(2);
  processIncluderCLIArgs(args);

  console.log(
    `Includer submitting transactions of tasks bound for ${
      targetConfig.chain!.name
    }`
  );
  console.log(`Using relayer address: ${relayerAccount}`);
  console.log(
    `Including approval transactions bound for ${targetConfig.contract}`
  );

  // poll amplifier Task API for new tasks
  setInterval(async () => {
    const tasks: TaskItem[] = await fetchTasks();
    if (tasks.length === 0) return;

    for (const task of tasks) {
      const sourceChain = task.task.message.sourceChain;
      await processTask(sourceChain, targetConfig.chain!, task);
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
    const response = await axios.get(url, {
      headers: {
        "Content-Type": "application/json",
      },
      httpsAgent,
    });

    console.log("Response from Amplifier GMP API: ", response.data);

    return response?.data?.data?.tasks || [];
  } catch (err) {
    console.error("Error fetching tasks: ", err);
  }
}

// process both approvals and executes
async function processTask(
  sourceChain: string,
  destinationChain: Chain,
  taskItem: TaskItem
) {
  // todo: check whether new tasks are already executed (ie by another includer)

  walletClient = createWalletClient({
    account: relayerAccount,
    transport: http(targetConfig.rpcUrl),
    chain: destinationChain,
  }).extend(publicActions);

  let txHash: `0x${string}` = "0x";
  if (taskItem.type == "GATEWAY_TX") {
    const executeData: `0x${string}` = `0x${Buffer.from(
      taskItem.task.executeData,
      "base64"
    )}`;

    // fetch tx params (gas, nonce, etc)
    const txRequest = await walletClient.prepareTransactionRequest({
      to: getAddress(targetConfig.contract!),
      data: executeData,
    });
    // sign tx using encrypted keystore
    const txSerializable = await signViaEncryptedKeystore(txRequest);

    // send raw signed tx
    const rawTx = serializeTransaction(txSerializable);
    txHash = await walletClient.sendRawTransaction({
      serializedTransaction: rawTx,
    });
  } else if (taskItem.type == "EXECUTE") {
    // must == RWTEL
    const destinationAddress = taskItem.task.message.destinationAddress;
    const payload: `0x${string}` = `0x${
      (Buffer.from(taskItem.task.payload), "base64")
    }`;
    const txRequest = await walletClient.prepareTransactionRequest({
      to: destinationAddress,
      data: payload,
    });

    // sign tx using encrypted keystore
    const txSerializable = await signViaEncryptedKeystore(txRequest);

    // send raw signed tx
    const rawTx = serializeTransaction(txSerializable);
    txHash = await walletClient.sendRawTransaction({
      serializedTransaction: rawTx,
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
  // save latest task to disk
  writeFile("./latest-task.txt", taskItem.id, (err) => {
    if (err) throw new Error(`${err}`);
    console.log("Latest task saved to disk");
  });
}

async function recordTaskExecuted(
  sourceChain: string,
  destinationChain: Chain,
  taskItem: TaskItem,
  txReceipt: TransactionReceipt
) {
  // handle axelar's custom nomenclature for sepolia
  let destinationChainName = destinationChain.name.toLowerCase();
  if (destinationChain === sepolia)
    destinationChainName = `eth-${destinationChainName}`;

  // make post request
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

    const response = await axios.post(
      `${GMP_API_URL}/chains/${destinationChainName}/events`,
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
    console.error("Error recording task executed: ", err);
  }
}

/// @dev Viem does not support signing via encrypted keystore so
/// a context switch dipping into Foundry is required
async function signViaEncryptedKeystore(txRequest: TransactionRequest) {
  // convert tx to serializable format
  const txSerializable: TransactionSerializable = {
    chainId: 2017,
    gas: txRequest.gas,
    maxFeePerGas: txRequest.maxFeePerGas,
    maxPriorityFeePerGas: txRequest.maxPriorityFeePerGas,
    nonce: txRequest.nonce,
    to: txRequest.to,
    data: txRequest.data,
  };
  const serializedTx = serializeTransaction(txSerializable);

  // pre-derive tx hash to be securely signed before submission
  const txHash = keccak256(serializedTx);
  const command = `cast wallet sign ${txHash} --keystore ${KEYSTORE_PATH} --password ${KS_PW} --no-hash`;
  try {
    const stdout = execSync(command, { encoding: "utf8" });
    console.log(`stdout: ${stdout}`);

    const signature = stdout.trim() as `0x${string}`;
    // attach signature and re-serialize tx
    const parsedSignature = parseSignature(signature);
    txSerializable.r = parsedSignature.r;
    txSerializable.s = parsedSignature.s;
    txSerializable.v = parsedSignature.v;

    return txSerializable;
  } catch (err) {
    console.error(`Error signing tx: ${err}`);
    throw err;
  }
}

function processIncluderCLIArgs(args: string[]) {
  processCLIArgs(args);

  args.forEach((arg, index) => {
    const valueIndex = index + 1;

    if (arg === "--latest-task" && args[valueIndex]) {
      latestTask = args[valueIndex];
    }
    if (arg === "--poll-interval" && args[valueIndex]) {
      pollInterval = parseInt(args[valueIndex], 10);
    }
  });
}

main();

/* todo:
    - check whether new tasks are already executed (ie by another includer)
    - use aggregation via Multicall3
    - monitor transaction & adjust gas params if necessary
*/
