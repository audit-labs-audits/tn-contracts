import {
  logger,
  networks,
  NetworkSetup,
} from "@axelar-network/axelar-local-dev";
import { ethers, Wallet, Signer, providers, ContractFactory } from "ethers";
import { NonceManager } from "@ethersproject/experimental";
import { NetworkExtended } from "./NetworkExtended.js";

/// @dev
export const deployContract = async (
  signer: Wallet | NonceManager | Signer,
  contractJson: { abi: any; bytecode: string },
  args: any[] = [],
  options = {}
) => {
  const factory = new ContractFactory(
    contractJson.abi,
    contractJson.bytecode,
    signer
  );

  const contract = await factory.deploy(...args, { ...options });
  await contract.deployed();
  return contract;
};

export async function setupNetworkExtended(
  urlOrProvider: string | providers.Provider,
  options: NetworkSetup
) {
  const chain = new NetworkExtended();

  chain.name = options.name ?? "NO NAME SPECIFIED";
  chain.provider =
    typeof urlOrProvider === "string"
      ? ethers.getDefaultProvider(urlOrProvider)
      : urlOrProvider;
  chain.chainId = (await chain.provider.getNetwork()).chainId;

  const defaultWallets = getDefaultLocalWallets();

  logger.log(
    `Setting up ${chain.name} on a network with a chainId of ${chain.chainId}...`
  );
  if (options.userKeys == null)
    options.userKeys = options.userKeys || defaultWallets.slice(5, 10);
  if (options.relayerKey == null)
    options.relayerKey = options.ownerKey || defaultWallets[2];
  if (options.operatorKey == null)
    options.operatorKey = options.ownerKey || defaultWallets[3];
  if (options.adminKeys == null)
    options.adminKeys = options.ownerKey
      ? [options.ownerKey]
      : [defaultWallets[4]];

  options.ownerKey = options.ownerKey || defaultWallets[0];

  chain.userWallets = options.userKeys.map(
    (x) => new Wallet(x, chain.provider)
  );
  chain.ownerWallet = new Wallet(options.ownerKey, chain.provider);
  chain.ownerNonceManager = new NonceManager(chain.ownerWallet);
  chain.operatorWallet = new Wallet(options.operatorKey, chain.provider);
  chain.relayerWallet = new Wallet(options.relayerKey, chain.provider);

  chain.adminWallets = options.adminKeys.map(
    (x) => new Wallet(x, chain.provider)
  );
  chain.threshold = options.threshold != null ? options.threshold : 1;
  chain.lastRelayedBlock = await chain.provider.getBlockNumber();
  chain.lastExpressedBlock = chain.lastRelayedBlock;
  await chain.deployConstAddressDeployer();
  await chain.deployCreate3Deployer();
  await chain.deployGateway();
  await chain.deployGasReceiver();
  await chain.deployInterchainTokenService();
  chain.tokens = {};

  networks.push(chain);
  return chain;
}

// testing only **NOT SECURE**
function getDefaultLocalWallets() {
  // This is a default seed for anvil that generates 10 wallets
  const defaultSeed =
    "test test test test test test test test test test test junk";

  const wallets = [];

  for (let i = 0; i < 10; i++) {
    wallets.push(Wallet.fromMnemonic(defaultSeed, `m/44'/60'/0'/0/${i}`));
  }

  return wallets;
}
