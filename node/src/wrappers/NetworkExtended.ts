"use strict";

import {
  getRandomID,
  getSignedExecuteInput,
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
  BurnableMintableCappedERC20,
} from "@axelar-network/axelar-local-dev/dist/contracts/index.js";
import { AxelarGateway__factory as AxelarGatewayFactory } from "@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/axelar-cgp-solidity/contracts/AxelarGateway__factory.js";
import { AxelarGasService__factory as AxelarGasServiceFactory } from "@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService__factory.js";
import {
  InterchainTokenService__factory as InterchainTokenServiceFactory,
  InterchainTokenFactory__factory as InterchainTokenFactoryFactory,
} from "@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/interchain-token-service/contracts/index.js";
import { setupITS } from "@axelar-network/axelar-local-dev/dist/its.js";
import { InterchainTokenService } from "@axelar-network/axelar-local-dev/dist/types/@axelar-network/interchain-token-service/contracts/InterchainTokenService.js";
import { deployContract } from "./utils.js";

const { defaultAbiCoder, arrayify, keccak256, toUtf8Bytes } = ethers.utils;
const defaultGasLimit = 10_000_000;

/// @dev This class inherits Network and extends it for use with Telcoin Network by adding a nonce manager
/// and manually setting gas limits. This is because TN consensus results in differing pending block & transaction behavior
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
      value: BigInt(10e18),
      gasLimit: defaultGasLimit,
    });
    await tx.wait();
    console.log("Funded deployer wallet with 100 TEL");

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
      value: BigInt(10e18),
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
    const wallet = this.ownerNonceManager;
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

    console.log(`Deploying the TokenManagerDeployer for ${this.name}...`);
    const tokenManagerDeployer = await deployContract(
      wallet,
      TokenManagerDeployer,
      [],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log(`Deployed at ${tokenManagerDeployer.address}`);

    console.log(`Deploying the InterchainToken for ${this.name}...`);
    const interchainToken = await deployContract(
      wallet,
      InterchainToken,
      [interchainTokenServiceAddress],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log(`Deployed at ${interchainToken.address}`);

    console.log(`Deploying the InterchainTokenDeployer for ${this.name}...`);
    const interchainTokenDeployer = await deployContract(
      wallet,
      InterchainTokenDeployer,
      [interchainToken.address],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log(`Deployed at ${interchainTokenDeployer.address}`);

    console.log(`Deploying the TokenManager for ${this.name}...`);
    const tokenManager = await deployContract(
      wallet,
      TokenManager,
      [interchainTokenServiceAddress],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log(`Deployed at ${tokenManager.address}`);

    console.log(`Deploying the TokenHandler for ${this.name}...`);
    const tokenHandler = await deployContract(wallet, TokenHandler, [], {
      gasLimit: defaultGasLimit,
    });
    console.log(`Deployed at ${tokenHandler.address}`);

    const interchainTokenFactoryAddress =
      await this.create3Deployer.deployedAddress(
        "0x",
        ownerAddress,
        factorySalt
      );

    console.log(`Deploying the ServiceImplementation for ${this.name}...`);
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

    console.log(`Deployed at ${serviceImplementation.address}`);
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

    console.log(`Deploying the TokenFactoryImplementation for ${this.name}...`);
    const tokenFactoryimplementation = await deployContract(
      wallet,
      InterchainTokenFactoryContract,
      [interchainTokenServiceAddress],
      {
        gasLimit: defaultGasLimit,
      }
    );
    console.log(`Deployed at ${tokenFactoryimplementation.address}`);

    bytecode = factory.getDeployTransaction(
      tokenFactoryimplementation.address,
      ownerAddress,
      "0x"
    ).data;

    try {
      console.log(`Deploying the InterchainTokenFactory for ${this.name}...`);
      await this.create3Deployer.connect(wallet).deploy(bytecode, factorySalt);
      this.interchainTokenFactory = InterchainTokenFactoryFactory.connect(
        interchainTokenFactoryAddress,
        wallet
      );
      console.log(`Deployed at ${this.interchainTokenFactory.address}`);
    } catch {
      throw new Error("Create3 Error: InterchainTokenFactory");
    }

    await setupITS(this);
    logger.log(
      `Deployed the InterchainTokenService at ${this.interchainTokenService.address}`
    );
    return this.interchainTokenService;
  }

  /// @dev Altered to use the NetworkExtended's NonceManager rather than ethers Wallet
  deployToken = async (
    name: string,
    symbol: string,
    decimals: number,
    cap: bigint
    // address: string = ADDRESS_ZERO,
    // alias: string = symbol
  ) => {
    logger.log(`Deploying ${name} for ${this.name}...`);
    const data = arrayify(
      defaultAbiCoder.encode(
        ["uint256", "bytes32[]", "string[]", "bytes[]"],
        [
          this.chainId,
          [getRandomID()],
          ["deployToken"],
          [
            defaultAbiCoder.encode(
              ["string", "string", "uint8", "uint256", "address", "uint256"],
              [name, symbol, decimals, cap, ethers.constants.AddressZero, 0]
            ),
          ],
        ]
      )
    );
    const signedData = await getSignedExecuteInput(data, this.operatorWallet);

    // use nonce manager rather than ethers wallet
    const wallet = this.ownerNonceManager;
    await (
      await this.gateway
        .connect(wallet)
        .execute(signedData, { gasLimit: defaultGasLimit })
    ).wait();
    const tokenAddress = await this.gateway.tokenAddresses(symbol);
    const tokenContract = new Contract(
      tokenAddress,
      BurnableMintableCappedERC20.abi,
      wallet
    );
    logger.log(`Deployed at ${tokenContract.address}`);
    this.tokens[symbol] = symbol;
    return tokenContract;
  };
}
