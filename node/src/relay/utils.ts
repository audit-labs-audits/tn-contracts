import { Address, getAddress } from "viem";
import { mainnet, sepolia, telcoinTestnet, Chain } from "viem/chains";

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

/// utils suited for general GMP
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
