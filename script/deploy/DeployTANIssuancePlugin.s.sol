// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Deployments } from "../../deployments/Deployments.sol";
import { TANIssuancePlugin } from "../../src/issuance/TANIssuancePlugin.sol";

contract TestnetDeployTANIssuancePlugin is Script {
    TANIssuancePlugin plugin;

    // config
    Deployments deployments;
    IERC20 tel = 0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32; // polygon TEL
    address increaser; // admin

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        increaser = deployments.admin;
    }

    function run() public {
        vm.startBroadcast();

        plugin = new TANIssuancePlugin{ salt: bytes32(0x0) }();

        vm.stopBroadcast();
    }
}
