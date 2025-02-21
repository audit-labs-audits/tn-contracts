// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Deployments } from "../../deployments/Deployments.sol";
import { TANIssuanceHistory } from "../../src/issuance/TANIssuanceHistory.sol";
import { ISimplePlugin } from "../../src/interfaces/ISimplePlugin.sol";

/// @dev Usage: `forge script script/deploy/DeployTANIssuanceHistory.s.sol -vvvv \
/// --rpc-url $POLYGON_RPC_URL --private-key $ADMIN_PK --verify`
contract DeployTANIssuanceHistory is Script {
    TANIssuanceHistory tanIssuanceHistory;

    // config
    Deployments deployments;
    IERC20 tel;
    ISimplePlugin tanIssuancePlugin;
    address owner;
    bytes32 tanIssuanceHistorySalt;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        // TAN Safe; calls `TANIssuanceHistory::increaseClaimableByBatch()`
        owner = 0x8Dcf8d134F22aC625A7aFb39514695801CD705b5;
        tanIssuanceHistorySalt = bytes32(abi.encode("TANIssuanceHistory"));

        // both mocks and prod contracts use canonical TEL
        tel = IERC20(0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32);

        // TAN issuance specific plugin on Polygon
        tanIssuancePlugin = ISimplePlugin(0xd8e7a80570d37D3fBe6eD5228c75475c81cEd094);
    }

    function run() public {
        vm.startBroadcast();

        tanIssuanceHistory = new TANIssuanceHistory{ salt: tanIssuanceHistorySalt }(tanIssuancePlugin, owner);

        vm.stopBroadcast();

        // asserts
        assert(tanIssuanceHistory.tel() == tel);
        assert(tanIssuanceHistory.owner() == owner);
        assert(tanIssuanceHistory.tanIssuancePlugin() == tanIssuancePlugin);
        assert(tanIssuanceHistory.clock() == block.number);

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/deployments/deployments.json");
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(tanIssuancePlugin))), 20), dest, ".TANIssuancePlugin"
        );
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(tanIssuanceHistory))), 20), dest, ".TANIssuanceHistory"
        );
    }
}
