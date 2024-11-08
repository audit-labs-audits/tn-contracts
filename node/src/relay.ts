import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import axelarAmplifierGatewayArtifact from "../../artifacts/AxelarAmplifierGateway.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

const MAINNET_RPC_URL: string | undefined = process.env.MAINNET_RPC_URL;
if (!MAINNET_RPC_URL) throw new Error("Set mainnet rpc url in .env");
const AXL_ETH_EXTERNAL_GATEWAY = "0x4F4495243837681061C4743b74B3eEdf548D56A5";

const client = createPublicClient({
  chain: mainnet,
  transport: http(), //todo: grab prod rpc
});

let lastCheckedBlock: bigint;

async function monitorEvents(filterId: Number) {
  try {
    const currentBlock = await client.getBlockNumber();
    // set `lastCheckedBlock` on first run
    if (!lastCheckedBlock) {
      lastCheckedBlock = currentBlock;
      return;
    }

    const filter = await client.createContractEventFilter({
      abi: axelarAmplifierGatewayArtifact.abi,
      address: AXL_ETH_EXTERNAL_GATEWAY,
      eventName: "ContractCall",
      fromBlock: currentBlock,
      /*
            args: {
                    destinationChain: "telcoin-network",
                    destinationContractAddress: "0x07e17e17e17e17e17e17e17e17e17e17e17e17e1",
            }
            */
      strict: true,
    });

    lastCheckedBlock = currentBlock;

    // process logs
    for (const log of filteredLogs) {
      console.log("New event: ", log);
      // todo: processing
    }
  } catch (err) {
    console.error("Error monitoring events: ", err);
  }
}

// poll every 12s block
setInterval(monitorEvents, 12000);

monitorEvents();
