// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { StablecoinHandler } from "telcoin-contracts/contracts/stablecoin/StablecoinHandler.sol";
import { StablecoinManager } from "../src/StablecoinManager.sol";
import { WTEL } from "../src/WTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";

/// @dev Usage: `forge script script/TestnetDeployTokens.s.sol --rpc-url $TN_RPC_URL -vvvv --private-key $ADMIN_PK`
contract TestnetDeployStablecoinManager is Script {
    StablecoinManager stablecoinManagerImpl;
    StablecoinManager stablecoinManager;

    bytes32 stablecoinManagerSalt; // used for both impl and proxy
    address[] stables;
    StablecoinManager.eXYZ[] eXYZs;
    uint256 maxLimit;
    uint256 minLimit;

    Deployments deployments;
    address admin; // admin, support, minter, burner role

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;

        stablecoinManagerSalt = bytes32(bytes("StablecoinManager"));
        maxLimit = type(uint256).max;
        minLimit = 1000;

        // populate stables array
        stables.push(deployments.eAUD);
        stables.push(deployments.eCAD);
        stables.push(deployments.eCHF);
        stables.push(deployments.eEUR);
        stables.push(deployments.eGBP);
        stables.push(deployments.eHKD);
        stables.push(deployments.eMXN);
        stables.push(deployments.eNOK);
        stables.push(deployments.eJPY);
        stables.push(deployments.eSDR);
        stables.push(deployments.eSGD);

        // populate eXYZs
        for (uint256 i; i < stables.length; ++i) {
            eXYZs.push(StablecoinHandler.eXYZ(true, maxLimit, minLimit));
        }
    }

    function run() public {
        vm.startBroadcast();

        // deploy implementaiton
        stablecoinManagerImpl = new StablecoinManager{ salt: stablecoinManagerSalt }();

        // deploy proxy with init data
        bytes memory initData =
            abi.encodeWithSelector(StablecoinManager.initialize.selector, admin, admin, stables, eXYZs);
        stablecoinManager = StablecoinManager(
            address(new ERC1967Proxy{ salt: stablecoinManagerSalt }(address(stablecoinManagerImpl), initData))
        );

        vm.stopBroadcast();

        // asserts
        assert(stablecoinManager.getEnabledXYZs().length == 11);
        assert(stablecoinManager.getEnabledXYZsWithMetadata().length == 11);

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/deployments/deployments.json");
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(stablecoinManager))), 20), dest, ".StablecoinManager"
        );
    }
}
