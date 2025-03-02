// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Deployments } from "../../deployments/Deployments.sol";
import "./mocks/MockImplementations.sol";
import "../../src/issuance/TANIssuanceHistory.sol";
import "../../src/interfaces/ISimplePlugin.sol";

contract TANIssuanceHistoryForkTest is Test {
    // for forking
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    uint256 polygonFork;

    // read from deployments.json
    Deployments deployments;
    ISimplePlugin public plugin;
    TANIssuanceHistory public tanIssuanceHistory;

    // polygon-specific addresses required for forking
    MockAmirX public amirX = MockAmirX(0x8d52367c87bDb6A957529d2aeD95C17260Db1B93);
    ERC20 public tel = ERC20(0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32);
    address public stakingModule = 0x92e43Aec69207755CB1E6A8Dc589aAE630476330;
    address public tanSafe = 0x8Dcf8d134F22aC625A7aFb39514695801CD705b5;
    // used only to source funds for `user` and `defiAgg` in forked environment
    address public existingTelHolder = 0x2ff79955Aad11fA93B84d79D45F504E6168935BC;

    // testing addresses
    address public defiAgg = address(0x456);
    address public executor = address(0x789);
    address public user = address(0xabc);

    uint256 issuanceAmount;
    uint256 scalingFactor;
    uint256 totalEligibleVolume;
    address[] rewardees;
    uint256[] rewards;
    uint256 endBlock;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        plugin = ISimplePlugin(deployments.TANIssuancePlugin);
        tanIssuanceHistory = TANIssuanceHistory(deployments.TANIssuanceHistory);

        issuanceAmount = 3_000_000;
        // calculator uses a very large scaling factor to address arithmetic decimal precision
        scalingFactor = 1_000_000_000_000_000;

        polygonFork = vm.createFork(POLYGON_RPC_URL);
    }

    function testForkTANIssuanceHistory() public {
        vm.selectFork(polygonFork);

        // (fork tests only) fund user with TEL from existing holder
        uint256 userFeeVolume = 100;
        vm.prank(existingTelHolder);
        tel.transfer(user, userFeeVolume);

        // first stake for incentive eligibility (shown for visibility)
        vm.startPrank(user);
        tel.approve(stakingModule, userFeeVolume);
        (bool success,) = stakingModule.call(abi.encodeWithSignature("stake(uint256)", userFeeVolume));
        require(success);
        vm.stopPrank();

        // (fork testing only) deploy mock amirX to fork
        amirX = new MockAmirX{ salt: bytes32(0) }(IERC20(address(tel)), executor, defiAgg);

        // (fork testing only): fund `defiAgg` who then approves tokens to `amirX`
        vm.prank(existingTelHolder);
        tel.transfer(defiAgg, userFeeVolume);
        vm.prank(defiAgg);
        tel.approve(address(amirX), userFeeVolume);

        // perform swap, initiating user fee transfer
        MockAmirX.DefiSwap memory defi = MockAmirX.DefiSwap(
            address(0x0), address(0x0), plugin, IERC20(address(0x0)), address(0x0), userFeeVolume, "", ""
        );

        /// @notice in prod, users invoke `AmirX::defiSwap()` as part of app flow and
        /// the ERC20 transfer of TEL from the defi aggregator to AmirX comprises the user fee paid
        vm.prank(executor);
        amirX.defiSwap(address(0x0), defi);

        /// @dev offchain calculator analyzes resulting user fee transfer event, checks stake eligibility
        /// and then calculates rewards for distribution (calculation simulated below for visibility)
        totalEligibleVolume = userFeeVolume;

        // derive reward caps
        vm.roll(block.number + 1);
        uint256 prevBlock = block.number - 1;
        (bool r, bytes memory ret) =
            stakingModule.call(abi.encodeWithSignature("stakedByAt(address,uint256)", user, prevBlock));
        require(r);
        uint256 stakedByUser = uint256(bytes32(ret));
        uint256 prevUserRewards = tanIssuanceHistory.cumulativeRewardsAtBlock(user, prevBlock);
        uint256 userRewardCap = stakedByUser - prevUserRewards;

        uint256 userReward = scalingFactor * userFeeVolume / totalEligibleVolume * issuanceAmount / scalingFactor;
        // in this test case does nothing but shown for calculator logic visibility
        if (userRewardCap < userReward) userReward = userRewardCap;

        // once calculated, construct distribution calldata
        rewardees.push(user);
        rewards.push(userReward);
        endBlock = block.number;

        // distribute rewards (funds come from TAN safe)
        vm.prank(tanSafe);
        tel.transfer(address(tanIssuanceHistory), userFeeVolume);

        // pre-settlement sanity asserts
        assertEq(tel.balanceOf(address(tanIssuanceHistory)), userFeeVolume);
        assertEq(tel.balanceOf(address(plugin)), 0);

        // owner of TANIssuanceHistory contract is configured as TAN safe
        vm.prank(tanSafe);
        tanIssuanceHistory.increaseClaimableByBatch(rewardees, rewards, endBlock);

        // asserts
        assertEq(tel.balanceOf(address(tanIssuanceHistory)), 0);
        assertEq(tel.balanceOf(address(plugin)), userFeeVolume);
        assertEq(tanIssuanceHistory.lastSettlementBlock(), endBlock);
        assertEq(tanIssuanceHistory.cumulativeRewards(user), userReward);
    }
}
