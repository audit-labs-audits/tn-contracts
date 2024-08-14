// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { StablecoinManager } from "../src/StablecoinManager.sol";
import { Deployments } from "../deployments/Deployments.sol";

/// @dev Usage: `forge script script/TestnetDisableStablecoin.s.sol --rpc-url $TN_RPC_URL -vvvv --private-key $ADMIN_PK`
contract TestnetDisableStablecoin is Script {
    StablecoinManager stablecoinManager;

    Deployments deployments;
    address admin; // admin, support, minter, burner role
    address tokenToManage;
    uint256 maxLimit;
    uint256 minLimit;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;

        stablecoinManager = StablecoinManager(deployments.StablecoinManager);
        tokenToManage = deployments.eEUR;
        maxLimit = type(uint256).max;
        minLimit = 1000;
    }

    function run() public {
        vm.startBroadcast();

        stablecoinManager.UpdateXYZ(tokenToManage, false, maxLimit, minLimit);

        vm.stopBroadcast();
    }
}