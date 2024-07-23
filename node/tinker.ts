import {
  Network,
  EvmRelayer,
  createAndExport,
  getNetwork,
  NetworkSetup,
  setupNetwork,
  relay,
} from "@axelar-network/axelar-local-dev";
import { JsonRpcProvider } from "@ethersproject/providers";
import { ethers, Wallet } from "ethers";
import * as dotenv from "dotenv";
dotenv.config();

/// @dev Basic script to tinker with local bridging via Axelar
async function main(): Promise<void> {
  // initializes an Ethereum network on port 8500, deploys Axelar infra, funds specified address, deploys aUSDC
  const setup = async (): Promise<void> => {
    // Define the path where chain configuration files with deployed contract addresses will be stored
    const outputPath = "./node/out/output.json";
    // A list of addresses to be funded with 100ether worth of the native token
    const fundAddresses = ["0x3DCc9a6f3A71F0A6C8C659c65558321c374E917a"];
    // A list of EVM chain names to be initialized
    const chains = ["Ethereum"];
    // Define the chain stacks that the networks will relay transactions between
    const relayers = { evm: new EvmRelayer() };
    // Number of milliseconds to periodically trigger the relay function and send all pending crosschain transactions to the destination chain
    const relayInterval = 5000;

    // A port number for the RPC endpoint. The endpoint for each chain can be accessed by the 0-based index of the chains array.
    // For example, if your chains array is ["Avalanche", "Fantom", "Moonbeam"], then http://localhost:8500/0 is the endpoint for the local Avalanche chain.
    const port = 8500;

    const deployUsdc = async (chain: Network): Promise<void> => {
      await chain.deployToken("Axelar Wrapped aUSDC", "aUSDC", 6, BigInt(1e22));
    };

    await createAndExport({
      chainOutputPath: outputPath,
      accountsToFund: fundAddresses,
      callback: (chain, _info) => deployUsdc(chain),
      chains: chains.length !== 0 ? chains : undefined,
      relayInterval: relayInterval,
      relayers,
      port,
    });
  };

  const bridge = async () => {
    // connect to TelcoinNetwork running on port 8545
    const telcoinRpcUrl = "http://localhost:8545/0";
    const telcoinProvider: JsonRpcProvider =
      new ethers.providers.JsonRpcProvider(telcoinRpcUrl);

    // set up Axelar infra and USDC token on TelcoinNetwork, instantiate Axelar <Network> wrapper around TN
    const pk = process.env.PK;
    if (!pk) throw new Error("Set private key string in .env");
    const testerWallet: Wallet = new ethers.Wallet(pk, telcoinProvider); // does wallet need to be connected with provider?
    const networkSetup: NetworkSetup = {
      name: "Telcoin Network",
      chainId: 2017,
      ownerKey: testerWallet,
    };
    const tn: Network = await setupNetwork(telcoinProvider, networkSetup);
    console.log(tn);
    const tnUSDC = await tn.getTokenContract("aUSDC");
    console.log(tnUSDC);

    // mint tokens to testerWallet on ethereum
    const ethRpcUrl = "http://localhost:8500/0";
    const eth = await getNetwork(ethRpcUrl);
    await eth.giveToken(testerWallet.address, "aUSDC", BigInt(10e6));
    const ethUSDC = await eth.getTokenContract("aUSDC");
    console.log(ethUSDC.balanceOf(testerWallet.address));

    // approve ethereum gateway to manage tokens
    const ethApproveTx = await ethUSDC
      .connect(testerWallet)
      .approve(eth.gateway.address, 10e6);
    await ethApproveTx.wait();

    // perform bridge transaction, starting with gateway request
    const ethGatewayTx = await eth.gateway
      .connect(testerWallet)
      .sendToken(tn.name, testerWallet.address, "aUSDC", 10e6);
    await ethGatewayTx.wait();

    // relay transactions
    await relay();

    // check token balances in console
    console.log(
      "aUSDC in Ethereum wallet: ",
      (await ethUSDC.balanceOf(testerWallet.address)) / 1e6
    );
    console.log(
      "aUSDC in Telcoin wallet: ",
      (await tnUSDC.balanceOf(testerWallet.address)) / 1e6
    );
  };

  try {
    await setup();
    await bridge();
  } catch (err) {
    console.log(err);
  }
}

main();
