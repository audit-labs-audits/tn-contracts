// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Deployments } from "../../deployments/Deployments.sol";
import { TANIssuanceHistory } from "../../src/issuance/TANIssuanceHistory.sol";
// todo: get access to repos for these contracts
// import { SimplePlugin } from "";
// import { StakingModule } from "";

contract TestnetDeployTANIssuanceHistory is Script {
    
    TANIssuanceHistory tanIssuanceHistory;
    // SimplePlugin tanIssuancePlugin;

    // config
    Deployments deployments;
    // polygon addresses for `SimplePlugin::constructor()`
    IERC20 tel = IERC20(0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32);
    // StakingModule stakingModule = StakingModule(0x92e43Aec69207755CB1E6A8Dc589aAE630476330);

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));
    }

    function run() public {
        vm.startBroadcast();

        // tanIssuancePlugin = new SimplePlugin{salt: bytes32(0x0)}()
        tanIssuanceHistory = new TANIssuanceHistory{salt: bytes32(0x0)}(tanIssuancePlugin);

        vm.stopBroadcast();
    }
}