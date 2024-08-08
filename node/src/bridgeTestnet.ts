// "use strict";

// import {
//   Network,
//   getNetwork,
//   networks,
// } from "@axelar-network/axelar-local-dev";
// import { ethers, Wallet, providers } from "ethers";
// import * as dotenv from "dotenv";
// dotenv.config();

// async function main(): Promise<void> {
//   const pk = process.env.PK
//   if (!pk) throw new Error("Set private key string in .env")
//   const testerWallet: Wallet = new Wallet(pk, )
//   const sepoliaRpcUrl = process.env.SEPOLIA_RPC_URL
//   const sepoliaProvider: providers.JsonRpcProvider = new providers.JsonRpcProvider(
//     sepoliaRpcUrl
//   )
//   const sepolia: Network = await getNetwork(sepoliaProvider);

//   const telcoinRpcUrl = process.env.TN_RPC_URL;
//   const telcoinProvider: providers.JsonRpcProvider = new providers.JsonRpcProvider(
//     telcoinRpcUrl
//   );
//   const tn:Network = await getNetwork(telcoinProvider)

//   const amount = 10e6;
//   const destinationAddress =

// }
