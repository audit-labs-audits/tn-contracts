import {
  Network,
  EvmRelayer,
  createAndExport,
  networks,
  createNetwork,
  getNetwork,
  NetworkSetup,
  NetworkInfo,
  relay,
  setupNetwork,
} from "@axelar-network/axelar-local-dev";
// import { JsonRpcProvider } from "@ethersproject/providers";
import { ethers, Wallet, providers } from "ethers";
import {
  NetworkExtended,
  setupNetworkExtended,
} from "./utils/NetworkExtended.js";
import * as dotenv from "dotenv";
dotenv.config();

const pk: string | undefined = process.env.PK;
if (!pk) throw new Error("Set private key string in .env");

/// @dev Basic script to tinker with local bridging via Axelar
/// @notice initializes an Ethereum network on port 8500, deploys Axelar infra, funds specified address, deploys aUSDC
async function main(): Promise<void> {
  const eth = await setupETH();

  // connect to TelcoinNetwork running on port 8545
  const telcoinRpcUrl = "http://localhost:8545";
  const telcoinProvider: providers.JsonRpcProvider =
    new providers.JsonRpcProvider(telcoinRpcUrl);
  const testerWalletTN: Wallet = new ethers.Wallet(
    pk as string,
    telcoinProvider
  );
  const tn: NetworkExtended = await setupTN(telcoinProvider, testerWalletTN);

  const bridge = async (eth: Network, tn: NetworkExtended) => {
    console.log("Bridging USDC from Ethereum to Telcoin");

    const ethUSDC = await eth.getTokenContract("aUSDC");
    console.log(
      "eth before transfer" + (await ethUSDC.balanceOf(testerWalletTN.address))
    );

    // approve ethereum gateway to manage tokens
    console.log(eth.ownerWallet.address);
    const ethApproveTx = await ethUSDC
      .connect(eth.ownerWallet)
      .approve(eth.gateway.address, 10e6);
    await ethApproveTx.wait(1);

    console.log(tn.name + " " + testerWalletTN.address);
    console.log("usdc:" + (await eth.getTokenContract("aUSDC")));

    // perform bridge transaction, starting with gateway request
    const ethGatewayTx = await eth.gateway
      .connect(eth.ownerWallet)
      .sendToken(tn.name, testerWalletTN.address, "aUSDC", 10e6);
    await ethGatewayTx.wait(1);
    console.log(
      "eth after transfer" + (await ethUSDC.balanceOf(testerWalletTN.address))
    );

    const tnUSDC = await tn.getTokenContract("aUSDC");
    const oldBalance = await tnUSDC.balanceOf(testerWalletTN.address);
    console.log("tn before relay" + oldBalance);

    // load network info and push to this instance then relay transactions
    const ethInfo = eth.getInfo();
    const ethAsExternalNetwork = await getNetwork(
      "http://localhost:8500",
      ethInfo
    );
    const tnInfo = tn.getInfo();
    const tnAsExternalNetwork = await getNetwork(telcoinProvider, tnInfo);
    networks.push(ethAsExternalNetwork);
    networks.push(tnAsExternalNetwork);

    await relay(/*{}, [eth, tnAsExternalNetwork]*/);

    const sleep = (ms: number | undefined) =>
      new Promise((resolve) => setTimeout(resolve, ms));
    // wait until relayer succeeds
    while (true) {
      const newBalance = await tnUSDC.balanceOf(testerWalletTN.address);
      console.log("old: " + oldBalance);
      console.log("new: " + newBalance);

      if (!oldBalance.eq(newBalance)) break;
      await sleep(2000);
    }

    // check token balances in console
    console.log(
      "aUSDC in Ethereum wallet: ",
      await ethUSDC.balanceOf(testerWalletTN.address)
    );
    console.log(
      "aUSDC in Telcoin wallet: ",
      await tnUSDC.balanceOf(testerWalletTN.address)
    );
  };

  try {
    // const eth = await setupETH();
    // const tn = await setupTN();
    await bridge(eth, tn);
    console.log("Completed!");
  } catch (err) {
    console.log(err);
  }
}

const setupETH = async (): Promise<Network> => {
  await createAndExport({
    chainOutputPath: "out",
    accountsToFund: ["0x3DCc9a6f3A71F0A6C8C659c65558321c374E917a"],
    chains: ["Ethereum"],
    relayInterval: 5000,
    port: 8500,
  });

  const ethRpcUrl = "http://localhost:8500/0";
  const ethProvider: providers.JsonRpcProvider = new providers.JsonRpcProvider(
    ethRpcUrl
  );
  const testerWalletETH: Wallet = new ethers.Wallet(pk, ethProvider);

  const eth = await getNetwork(ethRpcUrl);

  // deploy and mint tokens to testerWalletTN on ethereum
  await deployUsdc(eth);
  await eth.giveToken(testerWalletETH.address, "aUSDC", BigInt(10e6));

  return eth;
};

const setupTN = async (
  telcoinProvider: providers.JsonRpcProvider,
  testerWalletTN: Wallet
): Promise<NetworkExtended> => {
  const networkSetup: NetworkSetup = {
    name: "Telcoin Network",
    chainId: 2017,
    ownerKey: testerWalletTN,
  };

  try {
    const tn: NetworkExtended = await setupNetworkExtended(
      telcoinProvider,
      networkSetup
    );
    console.log("Deploying USDC to TN");
    await deployUsdc(tn);
    return tn;
  } catch (e) {
    console.error("Error setting up TN", e);
    throw new Error("Setup Error");
  }
};

const deployUsdc = async (chain: Network): Promise<void> => {
  await chain.deployToken("Axelar Wrapped aUSDC", "aUSDC", 6, BigInt(1e22));
};

function networkExtendedToNetwork(extended: NetworkExtended): Network {
  return new Network(extended);
}

main();
