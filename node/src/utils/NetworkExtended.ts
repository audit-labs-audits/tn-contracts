"use strict";

import {
  logger,
  Network,
  networks,
  NetworkSetup,
} from "@axelar-network/axelar-local-dev";
import {
  Contract,
  ContractFactory,
  Wallet,
  Signer,
  ethers,
  providers,
} from "ethers";
import { NonceManager } from "@ethersproject/experimental";
import {
  AxelarGasReceiverProxy,
  Auth,
  TokenDeployer,
  AxelarGatewayProxy,
  ConstAddressDeployer,
  Create3Deployer,
  TokenManagerDeployer,
  InterchainTokenDeployer,
  InterchainToken,
  TokenManager,
  TokenHandler,
  InterchainTokenService as InterchainTokenServiceContract,
  InterchainTokenFactory as InterchainTokenFactoryContract,
  InterchainProxy,
} from "@axelar-network/axelar-local-dev/dist/contracts/index.js";
import { AxelarGateway__factory as AxelarGatewayFactory } from "@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/axelar-cgp-solidity/contracts/AxelarGateway__factory.js";
import { AxelarGasService__factory as AxelarGasServiceFactory } from "@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService__factory.js";
import {
  InterchainTokenService__factory as InterchainTokenServiceFactory,
  InterchainTokenFactory__factory as InterchainTokenFactoryFactory,
} from "@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/interchain-token-service/contracts/index.js";
import { setupITS } from "@axelar-network/axelar-local-dev/dist/its.js";
import { InterchainTokenService } from "@axelar-network/axelar-local-dev/dist/types/@axelar-network/interchain-token-service/contracts/InterchainTokenService.js";

const { defaultAbiCoder, arrayify, keccak256, toUtf8Bytes } = ethers.utils;
const defaultGasLimit = 10_000_000;

/// @dev This class inherits Network and extends it for use with Telcoin Network by adding a nonce manager and manually setting gas limits
/// This is because TN consensus results in differing pending block & transaction behavior
export class NetworkExtended extends Network {
  ownerNonceManager!: NonceManager;

  async deployConstAddressDeployer(): Promise<Contract> {
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

    const tx = await this.ownerNonceManager.sendTransaction({
      to: deployerWallet.address,
      value: BigInt(1e18),
      gasLimit: defaultGasLimit,
    });
    await tx.wait();

    const constAddressDeployer = await deployContract(
      deployerWallet,
      ConstAddressDeployer,
      [], // constructor args
      {
        gasLimit: defaultGasLimit,
      }
    );

    this.constAddressDeployer = new Contract(
      constAddressDeployer.address,
      ConstAddressDeployer.abi,
      this.provider
    );
    logger.log(`Deployed at ${this.constAddressDeployer.address}`);

    return this.constAddressDeployer;
  }
  async deployCreate3Deployer(): Promise<Contract> {
    logger.log(`Deploying the Create3Deployer for ${this.name}... `);
    const create3DeployerPrivateKey = keccak256(
      toUtf8Bytes("const-address-deployer-deployer")
    );
    const deployerWallet = new Wallet(create3DeployerPrivateKey, this.provider);
    const tx = await this.ownerNonceManager.sendTransaction({
      to: deployerWallet.address,
      value: BigInt(1e18),
    });
    await tx.wait();

    const create3Deployer = await deployContract(
      deployerWallet,
      Create3Deployer,
      [],
      {
        gasLimit: defaultGasLimit,
      }
    );

    this.create3Deployer = new Contract(
      create3Deployer.address,
      Create3Deployer.abi,
      this.provider
    );
    logger.log(`Deployed at ${this.create3Deployer.address}`);
    return this.create3Deployer;
  }

  async deployGateway(): Promise<Contract> {
    logger.log(`Deploying the Axelar Gateway for ${this.name}... `);

    const params = arrayify(
      defaultAbiCoder.encode(
        ["address[]", "uint8", "bytes"],
        [
          this.adminWallets.map((wallet) => wallet.address),
          this.threshold,
          "0x",
        ]
      )
    );
    const auth = await deployContract(this.ownerNonceManager, Auth, [
      [
        defaultAbiCoder.encode(
          ["address[]", "uint256[]", "uint256"],
          [[this.operatorWallet.address], [1], 1]
        ),
      ],
    ]);
    const tokenDeployer = await deployContract(
      this.ownerNonceManager,
      TokenDeployer
    );
    const gateway = await deployContract(
      this.ownerNonceManager,
      AxelarGatewayFactory,
      [auth.address, tokenDeployer.address]
    );
    const proxy = await deployContract(
      this.ownerNonceManager,
      AxelarGatewayProxy,
      [gateway.address, params]
    );
    await (await auth.transferOwnership(proxy.address)).wait();
    this.gateway = AxelarGatewayFactory.connect(proxy.address, this.provider);
    logger.log(`Deployed at ${this.gateway.address}`);
    return this.gateway;
  }

  async deployGasReceiver(): Promise<Contract> {
    logger.log(`Deploying the Axelar Gas Receiver for ${this.name}...`);
    const wallet = await this.ownerNonceManager;
    const ownerAddress = await wallet.getAddress();
    const gasService = await deployContract(
      this.ownerNonceManager,
      AxelarGasServiceFactory,
      [ownerAddress]
    );
    const gasReceiverInterchainProxy = await deployContract(
      this.ownerNonceManager,
      AxelarGasReceiverProxy
    );
    await gasReceiverInterchainProxy.init(
      gasService.address,
      ownerAddress,
      "0x"
    );

    this.gasService = AxelarGasServiceFactory.connect(
      gasReceiverInterchainProxy.address,
      this.provider
    );
    logger.log(`Deployed at ${this.gasService.address}`);
    return this.gasService;
  }

  async deployInterchainTokenService(): Promise<InterchainTokenService> {
    logger.log(`Deploying the InterchainTokenService for ${this.name}...`);
    const deploymentSalt = keccak256(
      defaultAbiCoder.encode(["string"], ["interchain-token-service-salt"])
    );
    const factorySalt = keccak256(
      defaultAbiCoder.encode(["string"], ["interchain-token-factory-salt"])
    );
    const wallet = this.ownerNonceManager;
    const ownerAddress = await wallet.getAddress();

    const interchainTokenServiceAddress =
      await this.create3Deployer.deployedAddress(
        "0x", // deployed address not reliant on bytecode via Create3 so pass empty bytes
        ownerAddress,
        deploymentSalt
      );

    const tokenManagerDeployer = await deployContract(
      wallet,
      TokenManagerDeployer,
      [],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log("tokenManagerDeployer deployed");

    const interchainToken = await deployContract(
      wallet,
      InterchainToken,
      [interchainTokenServiceAddress],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log("interchainToken deployed");

    const interchainTokenDeployer = await deployContract(
      wallet,
      InterchainTokenDeployer,
      [interchainToken.address],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log("interchainTokenDeployer deployed");

    const tokenManager = await deployContract(
      wallet,
      TokenManager,
      [interchainTokenServiceAddress],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log("tokenManager deployed");

    const tokenHandler = await deployContract(wallet, TokenHandler, [], {
      gasLimit: defaultGasLimit,
    });
    console.log("tokenHandler deployed");

    const interchainTokenFactoryAddress =
      await this.create3Deployer.deployedAddress(
        "0x",
        ownerAddress,
        factorySalt
      );

    const serviceImplementation = await deployContract(
      wallet,
      InterchainTokenServiceContract,
      [
        tokenManagerDeployer.address,
        interchainTokenDeployer.address,
        this.gateway.address,
        this.gasService.address,
        interchainTokenFactoryAddress,
        this.name,
        tokenManager.address,
        tokenHandler.address,
      ],
      {
        gasLimit: defaultGasLimit,
      }
    );

    console.log("serviceImplementation deployed");
    const factory = new ContractFactory(
      InterchainProxy.abi,
      InterchainProxy.bytecode
    );
    let bytecode = factory.getDeployTransaction(
      serviceImplementation.address,
      ownerAddress,
      defaultAbiCoder.encode(
        ["address", "string", "string[]", "string[]"],
        [ownerAddress, this.name, [], []]
      )
    ).data;
    try {
      await this.create3Deployer
        .connect(wallet)
        .deploy(bytecode, deploymentSalt);
      this.interchainTokenService = InterchainTokenServiceFactory.connect(
        interchainTokenServiceAddress,
        wallet
      );
    } catch {
      throw new Error("Create3 Failure: InterchainTokenService");
    }

    const tokenFactoryimplementation = await deployContract(
      wallet,
      InterchainTokenFactoryContract,
      [interchainTokenServiceAddress],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log("tokenFactoryImplementation deployed");

    bytecode = factory.getDeployTransaction(
      tokenFactoryimplementation.address,
      ownerAddress,
      "0x"
    ).data;

    try {
      await this.create3Deployer.connect(wallet).deploy(bytecode, factorySalt);
      this.interchainTokenFactory = InterchainTokenFactoryFactory.connect(
        interchainTokenFactoryAddress,
        wallet
      );
    } catch {
      throw new Error("Create3 Error: InterchainTokenFactory");
    }

    await setupITS(this);
    logger.log(`Deployed at ${this.interchainTokenService.address}`);
    return this.interchainTokenService;
  }
}

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
