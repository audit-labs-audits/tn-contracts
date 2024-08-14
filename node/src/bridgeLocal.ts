import {
  Network,
  createAndExport,
  NetworkSetup,
  relay,
} from "@axelar-network/axelar-local-dev";
import { ethers, Contract, Wallet, providers } from "ethers";
import { NetworkExtended } from "./wrappers/NetworkExtended.js";
import { setupNetworkExtended } from "./wrappers/utils.js";
import * as dotenv from "dotenv";
dotenv.config();

const pk: string | undefined = process.env.PK;
if (!pk) throw new Error("Set private key string in .env");

/// @dev Basic script to tinker with local bridging via Axelar
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
      "Sender eth:USDC balance before bridging: " +
        (await ethUSDC.balanceOf(eth.ownerWallet.address))
    );

    // approve ethereum gateway to manage tokens
    const ethApproveTx = await ethUSDC
      .connect(eth.ownerWallet)
      .approve(eth.gateway.address, 10e6);
    await ethApproveTx.wait(1);

    // perform bridge transaction, starting with gateway request
    const ethGatewayTx = await eth.gateway
      .connect(eth.ownerWallet)
      .sendToken(tn.name, testerWalletTN.address, "aUSDC", 10e6);
    await ethGatewayTx.wait(1);
    console.log(
      "Sender eth:USDC balance after bridging: " +
        (await ethUSDC.balanceOf(eth.ownerWallet.address))
    );

    const tnUSDC = await tn.getTokenContract("aUSDC");
    const oldBalance = await tnUSDC.balanceOf(testerWalletTN.address);
    console.log("Recipient tn:USDC before relaying: " + oldBalance);

    await relay();
    console.log("Relayed");

    const sleep = (ms: number | undefined) =>
      new Promise((resolve) => setTimeout(resolve, ms));
    // wait until relayer succeeds
    while (true) {
      const newBalance = await tnUSDC.balanceOf(testerWalletTN.address);

      if (!oldBalance.eq(newBalance)) break;
      await sleep(2000);
    }

    // check token balances in console
    console.log(
      "aUSDC in Recipient's Telcoin wallet: ",
      await tnUSDC.balanceOf(testerWalletTN.address)
    );
  };

  try {
    await bridge(eth, tn);
    console.log("Completed!");
  } catch (err) {
    console.log(err);
  }
}

/// @notice initializes an Ethereum network on port 8500, deploys Axelar infra, funds specified address, deploys aUSDC
const setupETH = async (): Promise<Network> => {
  let ethResolve: (value: Network) => void;
  const ethPromise: Promise<Network> = new Promise(
    (resolve) => (ethResolve = resolve)
  );
  const callback = async (chain: Network, info: any): Promise<void> => {
    ethResolve(chain);
    await deployUsdc(chain);
    await chain.giveToken(chain.ownerWallet.address, "aUSDC", BigInt(10e6));
    console.log("Funded ETH owner wallet with aUSDC");
  };
  const chains = ["Ethereum"];
  await createAndExport({
    chainOutputPath: "out/output.json",
    accountsToFund: ["0x3DCc9a6f3A71F0A6C8C659c65558321c374E917a"],
    callback: callback,
    chains: chains,
    relayInterval: 5000,
    port: 8500,
  });

  const eth = await ethPromise;
  return eth;
};

/// @notice instantiates NetworkExtended object around local TN running on port 8545, deploys Axelar infra, funds specified address, deploys aUSDC
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
    await deployUsdc(tn);

    return tn;
  } catch (e) {
    console.error("Error setting up TN", e);
    throw new Error("Setup Error");
  }
};

const deployUsdc = async (
  chain: Network | NetworkExtended
): Promise<Contract> => {
  return await chain.deployToken(
    "Axelar Wrapped aUSDC",
    "aUSDC",
    6,
    BigInt(1e22)
  );
};

main();
