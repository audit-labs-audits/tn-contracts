"use strict";

import {
  deployContract,
  logger,
  Network,
  networks,
  NetworkSetup,
} from "@axelar-network/axelar-local-dev";
import { Contract, Wallet, ethers, providers } from "ethers";
import {
  ConstAddressDeployer,
  Create3Deployer,
  InterchainTokenDeployer,
  InterchainToken,
  InterchainTokenService as InterchainTokenServiceContract,
  InterchainTokenFactory as InterchainTokenFactoryContract,
  InterchainProxy,
} from "@axelar-network/axelar-local-dev/dist/contracts/index.js";
import { setupITS } from "@axelar-network/axelar-local-dev/dist/its.js";

const { defaultAbiCoder, arrayify, keccak256, toUtf8Bytes } = ethers.utils;
const defaultGasLimit = 1_000_000;

/// @dev This class inherits Network and extends it for use with Telcoin Network by manually setting gas limits
/// This is because standard gas estimation is not possible on TN due to its consensus
export class NetworkExtended extends Network {
  async deployConstAddressDeployer(): Promise<Contract> {
    console.log("YO");
    logger.log(
      `Deploying the ConstAddressDeployer with manual gasLimit for ${this.name}... `
    );
    // local tinkering only- **NOT SECURE**
    const constAddressDeployerDeployerPrivateKey = keccak256(
      toUtf8Bytes("const-address-deployer-deployer")
    );
    const deployerWallet = new Wallet(
      constAddressDeployerDeployerPrivateKey,
      this.provider
    );

    await this.ownerWallet
      .sendTransaction({
        to: deployerWallet.address,
        value: BigInt(1e18),
        // funding transaction does not require manual gasLimit
      })
      .then((tx) => tx.wait());

    console.log("HELLO");
    const constAddressDeployer = await deployContract(
      deployerWallet,
      ConstAddressDeployer,
      [
        {
          gasLimit: defaultGasLimit,
        },
      ]
    );
    console.log("BYE");

    this.constAddressDeployer = new Contract(
      constAddressDeployer.address,
      ConstAddressDeployer.abi,
      this.provider
    );
    logger.log(`Deployed at ${this.constAddressDeployer.address}`);

    return this.constAddressDeployer;
  }
  // async deployCreate3Deployer(): Promise<Contract> {}
  // async deployGateway(): Promise<Contract> {}
  // async deployGasReceiver(): Promise<Contract> {}
  // async deployInterchainTokenService(): Promise<Contract> {}
}

export async function setupNetworkExtended(
  urlOrProvider: string | providers.Provider,
  options: NetworkSetup
) {
  const chain = new NetworkExtended();

  chain.name =
    options.name ??
    "NO NAME SPECIFIED" /*!= null ? options.name : `Chain ${networks.length + 1}`*/;
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
