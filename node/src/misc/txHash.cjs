const { ethers } = require("ethers");
const RLP = require("ethers/lib/utils").RLP;
const keccak256 = require("ethers/lib/utils").keccak256;

/// @dev Utility for RLP-encoding a transaction and obtaining its EVM transaction hash
/// TODO: generalize into CLI utility rather than hard coded tx fields

const provider = new ethers.providers.JsonRpcProvider("https://adiri.tel");
const txHash =
  "0x6fc22afe63e5d64acd7c3ee2a85716be9673bcdcfc2d734134914be6e2854164";
async function main(txHash) {
  try {
    const tx = await provider.getTransaction(txHash);
    if (!tx) {
      console.log("tx not found");
      return;
    }

    const rawTx = await provider.send("eth_getRawTransactionByHash", [txHash]);
    console.log("raw tx: ", rawTx);
  } catch (error) {
    console.error("error fetching tx", error);
  }
}

// main(txHash);

// Transaction details
const chainId = ethers.utils.hexlify(2017); // telcoin chainId 2017
const nonce = ethers.utils.hexlify(36); // 0x24
const maxPriorityFeePerGas = ethers.utils.hexlify(7); // 0x07
const maxFeePerGas = ethers.utils.hexlify(7); //0x07
const gasLimit = ethers.utils.hexlify(1000000); // 0x0f4240
const to = "0x0e26AdE1F5A99Bd6B5D40f870a87bFE143Db68B6";
const value = "0x"; // 0x0
const data =
  "0xeb3839a7000000000000000000000000989251ff79b744736a91c617dde3d3b5da2c09ef00000000000000000000000026ba8e629bf6094f3b9a4199a92da55493cd78e9";
const accessList = [];
const yParity = "0x"; // yParity of 0 is encoded as an empty byte to result in "0x80" when RLP encoded
const r = "0x8ea2f39340ddd7258087c137315cd5d062a2da8d97b457224c603ec3f4f5cba3";
const s = "0x773fc73bd0f6e70920c844ee52369987c378b8c7798bed1b8c87eecedc9faf81";

// Create the transaction array for EIP 1559 transaction type (== 2)
const txData = [
  chainId,
  nonce,
  maxPriorityFeePerGas,
  maxFeePerGas,
  gasLimit,
  to,
  value,
  data,
  accessList,
  yParity,
  r,
  s,
];

// RLP encode the transaction
const rlpEncoded = RLP.encode(txData);
console.log(`RLP Encoded: ${rlpEncoded}`);

const rlpEncodedWithType = "0x02" + rlpEncoded.slice(2); // remove "0x" prefix and replace with "0x02"
console.log(`RLP Encoded With Type: ${rlpEncodedWithType}`);

// Hash the RLP encoded data
const transactionHash = keccak256(rlpEncodedWithType);
console.log(`Transaction Hash: ${transactionHash}`);
