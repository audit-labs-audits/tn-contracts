// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/StablecoinManager.sol";
import { StablecoinHandler } from "telcoin-contracts/contracts/stablecoin/StablecoinHandler.sol";

contract StablecoinManagerTest is Test {
    StablecoinManager stablecoinManager;
    address admin = address(0xABCD);
    address maintainer = address(0x1234);
    address token1 = address(0x1111);
    address token2 = address(0x2222);
    address[] faucets; // empty
    uint256 dripAmount = 42;

    function setUp() public {
        stablecoinManager = new StablecoinManager();
        stablecoinManager.initialize(admin, maintainer, new address[](0), new StablecoinHandler.eXYZ[](0), faucets, dripAmount);
    }

    function testUpdateXYZ() public {
        vm.startPrank(maintainer);
        stablecoinManager.UpdateXYZ(token1, true, 1000, 1);

        bool validity = stablecoinManager.isXYZ(token1);
        uint256 maxLimit = stablecoinManager.getMaxLimit(token1);
        uint256 minLimit = stablecoinManager.getMinLimit(token1);
        assertEq(validity, true);
        assertEq(maxLimit, 1000);
        assertEq(minLimit, 1);

        stablecoinManager.UpdateXYZ(token1, false, 100, 10);
        bool updatedValidity = stablecoinManager.isXYZ(token1);
        uint256 updatedMaxLimit = stablecoinManager.getMaxLimit(token1);
        uint256 updatedMinLimit = stablecoinManager.getMinLimit(token1);
        assertEq(updatedValidity, false);
        assertEq(updatedMaxLimit, 100);
        assertEq(updatedMinLimit, 10);

        vm.stopPrank();
    }

    function testAddEnabledXYZ() public {
        address[] memory noEnabledXYZs = stablecoinManager.getEnabledXYZs();
        assertEq(noEnabledXYZs.length, 0);

        vm.prank(maintainer);
        stablecoinManager.UpdateXYZ(token1, true, 1000, 1);
        address[] memory enabledXYZs = stablecoinManager.getEnabledXYZs();
        assertEq(enabledXYZs.length, 1);
        assertEq(enabledXYZs[0], token1);

        vm.prank(maintainer);
        stablecoinManager.UpdateXYZ(token2, true, 2000, 2);
        address[] memory moreEnabledXYZs = stablecoinManager.getEnabledXYZs();
        assertEq(moreEnabledXYZs.length, 2);
        assertEq(moreEnabledXYZs[1], token2);

        vm.stopPrank();
    }

    function testRemoveEnabledXYZ() public {
        vm.startPrank(maintainer);
        stablecoinManager.UpdateXYZ(token1, true, 1000, 1);
        stablecoinManager.UpdateXYZ(token2, true, 2000, 2);
        stablecoinManager.UpdateXYZ(token1, false, 1000, 1);
        vm.stopPrank();

        address[] memory enabledXYZs = stablecoinManager.getEnabledXYZs();
        assertEq(enabledXYZs.length, 1);
        assertEq(enabledXYZs[0], token2);
    }

    function testFuzzUpdateXYZ(uint8 numTokens, uint8 numRemove) public {
        vm.assume(numTokens >= numRemove);

        // make array of mock addresses
        address[] memory tokens = new address[](numTokens);
        for (uint256 i; i < numTokens; i++) {
            tokens[i] = address(uint160(i));
        }

        uint256 maxSupply = 1000;
        uint256 minSupply = 1;

        for (uint256 i; i < numTokens; i++) {
            address token = tokens[i];
            vm.prank(maintainer);
            stablecoinManager.UpdateXYZ(token, true, maxSupply, minSupply);

            bool validityStored = stablecoinManager.isXYZ(token);
            uint256 maxLimitStored = stablecoinManager.getMaxLimit(token);
            uint256 minLimitStored = stablecoinManager.getMinLimit(token);
            assertTrue(validityStored);
            assertEq(maxLimitStored, maxSupply);
            assertEq(minLimitStored, minSupply);
        }

        for (uint256 i; i < numRemove; i++) {
            address token = tokens[i];
            vm.prank(maintainer);
            stablecoinManager.UpdateXYZ(token, false, maxSupply, minSupply);

            bool validityStored = stablecoinManager.isXYZ(token);
            uint256 maxLimitStored = stablecoinManager.getMaxLimit(token);
            uint256 minLimitStored = stablecoinManager.getMinLimit(token);
            assertFalse(validityStored);
            assertEq(maxLimitStored, maxSupply);
            assertEq(minLimitStored, minSupply);
        }

        address[] memory enabledXYZs = stablecoinManager.getEnabledXYZs();
        assertEq(enabledXYZs.length, numTokens - numRemove);

        for (uint256 i; i < tokens.length; ++i) {
            bool validity = i >= numRemove ? true : false;
            address token = tokens[i];
            bool found = false;
            for (uint256 j; j < enabledXYZs.length; ++j) {
                if (enabledXYZs[j] == token) {
                    found = true;
                    break;
                }
            }

            if (validity) {
                assertTrue(found);
            } else {
                assertFalse(found);
            }
        }
    }
}
