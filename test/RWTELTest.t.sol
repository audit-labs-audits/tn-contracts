// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRecoverableWrapper } from "recoverable-wrapper/contracts/interfaces/IRecoverableWrapper.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { IRWTEL } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "../deployments/utils/Create3Utils.sol";
import { MockTEL, ITSTestHelper } from "./ITS/ITSTestHelper.sol";

contract RWTELTest is Test, ITSTestHelper {
    address admin = address(0xbeef);
    address user = address(0xabc);

    function setUp() public {
        setUp_tnFork_devnetConfig_create3(admin, originTEL);
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // rwTEL sanity tests
        assertEq(rwTEL.stakeManager(), 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        assertEq(address(rwTEL.interchainTokenService()), address(its));
        assertEq(rwTEL.owner(), admin);
        assertTrue(address(rwTEL).code.length > 0);
        string memory rwName = rwTEL.name();
        assertEq(rwName, "Recoverable Wrapped Telcoin");
        string memory rwSymbol = rwTEL.symbol();
        assertEq(rwSymbol, "rwTEL");
        uint256 recoverableWindow = rwTEL.recoverableWindow();
        assertEq(recoverableWindow, recoverableWindow_);
        address governanceAddress = rwTEL.governanceAddress();
        assertEq(governanceAddress, governanceAddress_);
    }

    function testFuzz_permitWrap(uint96 amount, uint256 deadline) public {
        vm.assume(amount > 0 && deadline > block.timestamp);

        uint256 zeroPK = uint256(keccak256("zero"));
        address testAddr = vm.addr(zeroPK);
        vm.deal(testAddr, amount);
        vm.prank(testAddr);
        wTEL.deposit{ value: amount }();

        bytes32 domainSeparator = wTEL.DOMAIN_SEPARATOR();
        bytes32 permitTypehash = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
        // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 permitDigest = keccak256(
            abi.encodePacked(
                hex"1901",
                domainSeparator,
                keccak256(abi.encode(permitTypehash, testAddr, address(rwTEL), amount, wTEL.nonces(testAddr), deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(zeroPK, permitDigest);

        vm.expectEmit(true, true, true, true);
        emit IRecoverableWrapper.Wrap(testAddr, amount);

        rwTEL.permitWrap(testAddr, amount, deadline, v, r, s);

        assertEq(wTEL.balanceOf(testAddr), 0);
        assertEq(wTEL.balanceOf(address(rwTEL)), amount);
        assertEq(rwTEL.balanceOf(testAddr), 0);
        vm.warp(block.timestamp + recoverableWindow_);
        assertEq(rwTEL.balanceOf(testAddr), amount);
        assertEq(rwTEL.totalSupply(), amount);
    }

    function testFuzz_doubleWrap(uint96 amount) public {
        vm.assume(amount > 0);
        // uint96 is ~ the total supply of TEL
        vm.deal(address(this), amount);

        vm.expectEmit(true, true, true, true);
        emit IRecoverableWrapper.Wrap(address(this), amount);

        uint256 wtelBalBefore = address(wTEL).balance;

        rwTEL.doubleWrap{ value: amount }();

        assertEq(address(wTEL).balance, wtelBalBefore + amount);
        assertEq(address(this).balance, 0);
        assertEq(rwTEL.balanceOf(address(this)), 0);
        assertEq(rwTEL.unsettledRecords(address(this)).length, 1);

        vm.warp(block.timestamp + recoverableWindow_);
        assertEq(rwTEL.balanceOf(address(this)), amount);
        assertEq(rwTEL.totalSupply(), amount);

        rwTEL.transfer(address(user), 1);
        assertEq(rwTEL.unsettledRecords(address(this)).length, 0);
    }

    function testRevert_doubleWrap_mintFailed() public {
        uint256 amount = 0;
        vm.expectRevert();
        rwTEL.doubleWrap{ value: amount }();
    }

    function testFuzz_mint(uint40 interchainAmount) public {
        vm.assume(interchainAmount > 0 && interchainAmount < 1e11);

        vm.startPrank(rwTEL.tokenManager());

        uint256 expectedNativeAmount = rwTEL.toEighteenDecimals(interchainAmount);
        uint256 initialRecipientBalance = user.balance;

        uint256 result = rwTEL.mint(user, interchainAmount);

        assertEq(result, expectedNativeAmount);
        assertEq(user.balance, initialRecipientBalance + expectedNativeAmount);

        vm.stopPrank();
    }

    function testRevert_mint_revertIfNotTokenManager(uint40 interchainAmount) public {
        vm.assume(interchainAmount > 0);

        vm.expectRevert();
        rwTEL.mint(user, interchainAmount);
    }

    function testFuzz_burn(uint96 nativeAmount) public {
        vm.assume(nativeAmount > 0 && nativeAmount < 1e29);

        vm.deal(user, nativeAmount);
        vm.prank(user);
        rwTEL.doubleWrap{ value: nativeAmount }();
        vm.warp(block.timestamp + recoverableWindow_);

        vm.startPrank(rwTEL.tokenManager());
        uint256 initialBal = rwTEL.balanceOf(user);
        assertEq(initialBal, nativeAmount);

        bool willRevert = nativeAmount < rwTEL.DECIMALS_CONVERTER();
        if (willRevert) vm.expectRevert();
        (uint256 interchainAmount, uint256 remainder) = rwTEL.toTwoDecimals(nativeAmount);

        if (willRevert) vm.expectRevert();
        uint256 result = rwTEL.burn(user, nativeAmount);

        vm.stopPrank();

        if (!willRevert) {
            assertEq((result * rwTEL.DECIMALS_CONVERTER()) + remainder, nativeAmount);
            assertEq(result, nativeAmount / rwTEL.DECIMALS_CONVERTER());
            assertEq(remainder, nativeAmount % rwTEL.DECIMALS_CONVERTER());
            assertEq(result, interchainAmount);
            assertEq(rwTEL.balanceOf(user), 0);
        }
    }

    function test_burn_revertIfNotTokenManager(uint96 nativeAmount) public {
        vm.assume(nativeAmount > 0 && nativeAmount >= rwTEL.DECIMALS_CONVERTER());

        vm.expectRevert();
        rwTEL.burn(user, nativeAmount);
    }

    function testFuzz_toEighteenDecimals(uint40 interchainAmount) public view {
        uint256 expected = interchainAmount * rwTEL.DECIMALS_CONVERTER();
        assertEq(rwTEL.toEighteenDecimals(interchainAmount), expected);
    }

    function testFuzz_toTwoDecimals(uint96 nativeAmount) public {
        bool willRevert = nativeAmount < rwTEL.DECIMALS_CONVERTER();
        if (willRevert) vm.expectRevert();
        (uint256 interchainAmount, uint256 remainder) = rwTEL.toTwoDecimals(nativeAmount);

        if (!willRevert) {
            assertEq((interchainAmount * rwTEL.DECIMALS_CONVERTER()) + remainder, nativeAmount);
            assertEq(interchainAmount, nativeAmount / rwTEL.DECIMALS_CONVERTER());
            assertEq(remainder, nativeAmount % rwTEL.DECIMALS_CONVERTER());
        }
    }

    function test_transfer_zero() public {
        // RecoverableWrapper allows zero amount transfers
        rwTEL.transfer(address(wTEL), 0);
    }

    function testRevert_transfer_self(uint8 amount) public {
        vm.assume(amount > 0);
        rwTEL.doubleWrap{ value: amount }();
        vm.expectRevert();
        rwTEL.transfer(address(this), amount);
    }
}
