import { JsonRpcProvider } from "@ethersproject/providers";
import { ethers, Wallet } from "ethers";
import {
  NetworkExtended,
  setupNetworkExtended,
} from "./utils/NetworkExtended.js";
import * as dotenv from "dotenv";
dotenv.config();

const LOCAL_BLOCKCHAIN_URL = "https://adiri.tel"; //"http://localhost:8545";

const PRIVATE_KEY = process.env.PK; // Replace with the private key of 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23
if (!PRIVATE_KEY) throw new Error("PK not defined in env");
const privateKey = PRIVATE_KEY as string;

// Define the recipient address and amount to send
const RECIPIENT_ADDRESS = "0x3DCc9a6f3A71F0A6C8C659c65558321c374E917a";
const AMOUNT = ".001";
const DEFAULT_PRIORITY_FEE = "2";
const DEFAULT_MAX_FEE = "30";

async function main(): Promise<void> {
  try {
    // Create an ethers provider connected to the local blockchain
    const telcoinNetwork = new ethers.providers.JsonRpcProvider(
      LOCAL_BLOCKCHAIN_URL
    );

    // Create a wallet instance from the private key and connect it to the provider
    const wallet = new ethers.Wallet(privateKey, telcoinNetwork);

    // Create a transaction object
    const tx = {
      to: RECIPIENT_ADDRESS,
      value: ethers.utils.parseEther(AMOUNT),
      gasLimit: 21000, // Standard gas limit for a simple transfer
      // gasPrice: ethers.utils.parseUnits(DEFAULT_GAS_PRICE, "gwei"),
      maxPriorityFeePerGas: ethers.utils.parseUnits(
        DEFAULT_PRIORITY_FEE,
        "gwei"
      ),
      maxFeePerGas: ethers.utils.parseUnits(DEFAULT_MAX_FEE, "gwei"),
    };

    // Sign and send the transaction
    console.log(tx);
    const transactionResponse = await wallet.sendTransaction(tx);

    console.log("Transaction submitted:", transactionResponse);

    // Wait for the transaction to be mined
    const receipt = await transactionResponse.wait();
    console.log(receipt);
    console.log("Transaction mined:", receipt.transactionHash);
  } catch (error) {
    console.error("Error submitting transaction:", error);
  }
}

main();
