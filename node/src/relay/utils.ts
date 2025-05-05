import { execSync } from "child_process";
import { readFileSync } from "fs";
import {
  Address,
  createWalletClient,
  getAddress,
  http,
  keccak256,
  parseSignature,
  publicActions,
  serializeTransaction,
  TransactionRequest,
  TransactionSerializable,
} from "viem";
import { mainnet, sepolia, telcoinTestnet, Chain } from "viem/chains";
import * as https from "https";

/// Utils suited for single-chain components
export interface TargetConfig {
  chain?: Chain;
  contract?: Address;
  rpcUrl?: string;
}

export const targetConfig: TargetConfig = {};

export function processTargetCLIArgs(args: string[]) {
  args.forEach((arg, index) => {
    const valueIndex = index + 1;

    // Parse chain and set RPC URL
    if (arg === "--target-chain" && args[valueIndex]) {
      switch (args[valueIndex]) {
        case "sepolia":
          targetConfig.chain = sepolia;
          setRpcUrl("SEPOLIA_RPC_URL");
          break;
        case "ethereum":
          targetConfig.chain = mainnet;
          setRpcUrl("MAINNET_RPC_URL");
          break;
        case "telcoin-network":
          targetConfig.chain = telcoinTestnet;
          setRpcUrl("TN_RPC_URL");
          break;
      }
    }

    // Parse target contract
    if (arg === "--target-contract" && args[valueIndex]) {
      targetConfig.contract = getAddress(args[valueIndex]);
    }
  });

  if (!targetConfig.chain || !targetConfig.contract) {
    throw new Error(`Must set --target-chain and --target-contract`);
  }
}

/// GMP utils

export interface GMPMessage {
  txHash?: `0x${string}`;
  logIndex?: number;
  sourceChain?: string;
  sourceAddress?: `0x${string}`;
  destinationChain?: string;
  destinationAddress?: `0x${string}`;
  payloadHash?: `0x${string}`;
  amount?: bigint;
  payload?: `0x${string}`;
  destinationChainMultisigProver?: string;
  multisigSessionId?: string;
}

export interface GMPEnv {
  crtPath?: string;
  keyPath?: string;
  gmpApiUrl?: string;
}
export const gmpEnv: GMPEnv = {};

export function getGMPEnv() {
  const crtPath = process.env.CRT_PATH;
  const keyPath = process.env.KEY_PATH;
  const gmpApiUrl = process.env.GMP_API_URL;

  if (!crtPath || !keyPath || !gmpApiUrl) {
    throw new Error("Set all required ENV vars in .env");
  }

  gmpEnv.crtPath = crtPath;
  gmpEnv.keyPath = keyPath;
  gmpEnv.gmpApiUrl = gmpApiUrl;
}

export function createHttpsAgent(
  crtPath: string,
  keyPath: string
): https.Agent {
  const cert = readFileSync(crtPath);
  const key = readFileSync(keyPath);
  return new https.Agent({ cert, key });
}

/// TX utils
export interface KeystoreAccount {
  account?: Address;
  ksPath?: string;
  ksPw?: string;
}
export const keystoreAccount: KeystoreAccount = {};

export function getKeystoreAccount() {
  const accountStr = process.env.RELAYER;
  const account = accountStr ? getAddress(accountStr) : undefined;
  const ksPath = process.env.KEYSTORE_PATH;
  const ksPw = process.env.KS_PW;

  if (!ksPath || !ksPw || !account) {
    throw new Error("Set all required ENV vars in .env");
  }

  keystoreAccount.account = account;
  keystoreAccount.ksPath = ksPath;
  keystoreAccount.ksPw = ksPw;
}

/// @dev Viem does not support signing via encrypted keystore so
/// a context switch dipping into Foundry is required
export async function signViaEncryptedKeystore(
  txRequest: TransactionRequest,
  ksPath: string,
  ksPw: string
) {
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
  const command = `cast wallet sign ${txHash} --keystore ${ksPath} --password ${ksPw} --no-hash`;
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

export async function transactViaEncryptedKeystore(
  chain: Chain,
  rpcUrl: string,
  from: Address,
  to: Address,
  value: bigint,
  data: `0x${string}`,
  ksPath: string,
  ksPw: string
): Promise<void> {
  console.log("Submitting gateway approval as EVM transaction with proof data");

  // fetch tx params (gas, nonce, etc)
  const walletClient = createWalletClient({
    account: from,
    transport: http(rpcUrl),
    chain: chain,
  }).extend(publicActions);
  try {
    const txRequest = await walletClient.prepareTransactionRequest({
      to: to,
      data: data,
      value: value,
    });
    // sign tx using encrypted keystore
    const txSerializable = await signViaEncryptedKeystore(
      txRequest,
      ksPath!,
      ksPw!
    );

    // send raw signed tx
    const rawTx = serializeTransaction(txSerializable);
    const txHash = await walletClient.sendRawTransaction({
      serializedTransaction: rawTx,
    });

    const receipt = await walletClient.waitForTransactionReceipt({
      hash: txHash,
    });
    console.log("Transaction receipt: ", receipt);
  } catch (err) {
    console.error("Error sending transaction: ", err);
  }
}

export function setRpcUrl(envVarName: string) {
  const rpcUrl = process.env[envVarName];
  if (!rpcUrl) throw new Error("RPC URL not found");
  targetConfig.rpcUrl = rpcUrl;
}

export function validateEnvVar(envVarName: string): string {
  const envVar = process.env[envVarName];
  if (!envVar) throw new Error(`Failed to set env variable: ${envVarName}`);

  return envVar;
}
