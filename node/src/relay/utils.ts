import { Address, getAddress } from "viem";
import { mainnet, sepolia, telcoinTestnet, Chain } from "viem/chains";

export interface TargetConfig {
  chain?: Chain;
  contract?: Address;
  rpcUrl?: string;
}

export const targetConfig: TargetConfig = {};

export function processCLIArgs(args: string[]) {
  let chainSet = false;
  let contractSet = false;

  args.forEach((arg, index) => {
    const valueIndex = index + 1;

    // Parse chain and set RPC URL
    if (arg === "--target-chain" && args[valueIndex]) {
      switch (args[valueIndex]) {
        case "sepolia":
          targetConfig.chain = sepolia;
          setRpcUrl("SEPOLIA_RPC_URL", "RPC URL not found");
          break;
        case "ethereum":
          targetConfig.chain = mainnet;
          setRpcUrl("MAINNET_RPC_URL", "RPC URL not found");
          break;
        case "telcoin-network":
          targetConfig.chain = telcoinTestnet;
          setRpcUrl("TN_RPC_URL", "RPC URL not found");
          break;
      }
      chainSet = true;
    }

    // Parse target contract
    if (arg === "--target-contract" && args[valueIndex]) {
      targetConfig.contract = getAddress(args[valueIndex]);
      contractSet = true;
    }
  });

  if (!chainSet || !contractSet) {
    throw new Error(`Must set --target-chain and --target-contract`);
  }
}

function setRpcUrl(envVarName: string, notFoundMessage: string) {
  const rpcUrl = process.env[envVarName];
  if (!rpcUrl) throw new Error(notFoundMessage);
  targetConfig.rpcUrl = rpcUrl;
}
