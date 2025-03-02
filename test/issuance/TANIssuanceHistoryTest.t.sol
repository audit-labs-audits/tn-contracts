// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/issuance/TANIssuanceHistory.sol";
import "../../src/interfaces/ISimplePlugin.sol";
import "./mocks/MockImplementations.sol";

contract TANIssuanceHistoryTest is Test {
    MockTel tel;
    MockStakingModule public stakingModule;
    ISimplePlugin public mockPlugin;
    MockAmirX public amirX;

    TANIssuanceHistory public tanIssuanceHistory;

    // Addresses for testing
    address public owner = address(0x123);
    address public user = address(0x456);
    address public user1 = address(0x789);
    address public user2 = address(0xabc);
    address public defiAgg = address(0xdef);
    address public executor = address(0xfed);
    address public referrer = address(0xcba);

    function setUp() public {
        // Deploy TEL and mocks
        tel = new MockTel("Telcoin", "TEL");
        stakingModule = new MockStakingModule();
        mockPlugin = ISimplePlugin(address(new MockPlugin(IERC20(address(tel)))));
        // the mock amirX is owned by the executor address for simplicity
        amirX = new MockAmirX(IERC20(address(tel)), executor, defiAgg);

        // (unprotected) mint tokens to `defiAgg` and give unlimited approval to `amirX`
        tel.mint(defiAgg, 1_000_000);
        vm.prank(defiAgg);
        tel.approve(address(amirX), 1_000_000);

        // Deploy the TANIssuanceHistory contract as owner
        tanIssuanceHistory = new TANIssuanceHistory(mockPlugin, owner);
    }

    /// @dev Useful as a benchmark for the maximum batch size which is ~15000 users
    function testFuzz_increaseClaimableByBatch(uint16 numUsers) public {
        numUsers = uint16(bound(numUsers, 0, 14_000));
        address[] memory accounts = new address[](numUsers);
        uint256[] memory amounts = new uint256[](numUsers);
        for (uint256 i; i < numUsers; ++i) {
            accounts[i] = address(uint160(uint256(numUsers) + i));
            amounts[i] = uint256(numUsers) + i;
        }

        vm.prank(owner); // Ensure the caller is the owner
        uint256 someBlock = block.number + 5;
        vm.roll(someBlock);
        tanIssuanceHistory.increaseClaimableByBatch(accounts, amounts, someBlock);

        for (uint256 i; i < numUsers; ++i) {
            assertEq(tanIssuanceHistory.cumulativeRewards(accounts[i]), amounts[i]);
        }

        assertEq(tanIssuanceHistory.lastSettlementBlock(), someBlock);
    }

    function testIncreaseClaimableByBatchRevertArityMismatch() public {
        address[] memory accounts = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TANIssuanceHistory.ArityMismatch.selector));
        tanIssuanceHistory.increaseClaimableByBatch(accounts, amounts, block.number);
    }

    function testIncreaseClaimableByBatchWhenDeactivated() public {
        // Mock the plugin to return deactivated
        MockPlugin(address(mockPlugin)).setDeactivated(true);

        address[] memory accounts = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TANIssuanceHistory.Deactivated.selector));
        tanIssuanceHistory.increaseClaimableByBatch(accounts, amounts, block.number);
    }

    function testCumulativeRewardsAtBlock() public {
        vm.prank(owner);
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        tanIssuanceHistory.increaseClaimableByBatch(accounts, amounts, block.number);

        // Move forward in blocks
        vm.roll(block.number + 10);

        assertEq(tanIssuanceHistory.cumulativeRewardsAtBlock(user1, block.number - 10), 100);
        assertEq(tanIssuanceHistory.cumulativeRewardsAtBlock(user2, block.number - 10), 200);

        uint256 queryBlock = block.number - 10;
        (address[] memory users, uint256[] memory rewards) =
            tanIssuanceHistory.cumulativeRewardsAtBlockBatched(accounts, queryBlock);
        for (uint256 i; i < users.length; ++i) {
            assertEq(users[i], accounts[i]);
            assertEq(rewards[i], amounts[i]);
        }
    }

    function testIntegrationTANIssuanceHistory() public {
        // first stake for incentive eligibility
        uint256 userFeeVolume = 100;
        vm.prank(user);
        stakingModule.stake(userFeeVolume);
        vm.prank(referrer);
        stakingModule.stake(userFeeVolume);

        // perform swap, initiating user fee transfer
        MockAmirX.DefiSwap memory defi = MockAmirX.DefiSwap(
            address(0x0), address(0x0), mockPlugin, IERC20(address(0x0)), referrer, userFeeVolume, "", ""
        );

        vm.prank(executor);
        amirX.defiSwap(user, defi);

        /// @dev offchain calculator analyzes resulting user fee transfer event, checks stake eligibility
        /// and then calculates rewards for distribution (calculation simulated below for visibility)
        uint256 issuanceAmount = 3_000_000;
        // user's referrer is eligible for `userFeeVolume`  if staked
        uint256 referrerEligibility = userFeeVolume;
        uint256 totalEligibleVolume = userFeeVolume + referrerEligibility;

        // derive reward caps
        uint256 stakedByUser = stakingModule.stakedByAt(user, block.number);
        uint256 prevUserRewards = tanIssuanceHistory.cumulativeRewardsAtBlock(user, block.number);
        uint256 userRewardCap = stakedByUser - prevUserRewards;
        uint256 stakedByReferrer = stakingModule.stakedByAt(referrer, block.number);
        uint256 prevReferrerRewards = tanIssuanceHistory.cumulativeRewardsAtBlock(referrer, block.number);
        uint256 referrerRewardCap = stakedByReferrer - prevReferrerRewards;

        // calculator uses a very large scaling factor to address arithmetic decimal precision
        uint256 scalingFactor = 1_000_000_000_000_000;
        uint256 userReward = scalingFactor * userFeeVolume / totalEligibleVolume * issuanceAmount / scalingFactor;
        // in this test case does nothing but shown for calculator logic visibility
        if (userRewardCap < userReward) userReward = userRewardCap;
        uint256 referrerReward =
            scalingFactor * referrerEligibility / totalEligibleVolume * issuanceAmount / scalingFactor;
        // in this test case does nothing but shown for calculator logic visibility
        if (referrerRewardCap < referrerReward) referrerReward = referrerRewardCap;

        // once calculated, construct distribution calldata
        address[] memory rewardees = new address[](2);
        rewardees[0] = user;
        rewardees[1] = referrer;
        uint256[] memory rewards = new uint256[](2);
        rewards[0] = userReward;
        rewards[1] = referrerReward;
        uint256 endBlock = block.number;

        // pre-settlement sanity asserts
        assertEq(tanIssuanceHistory.lastSettlementBlock(), 0);
        assertEq(tanIssuanceHistory.cumulativeRewards(user), 0);
        assertEq(tanIssuanceHistory.cumulativeRewards(referrer), 0);

        // settle distribution of rewards
        vm.prank(owner);
        tanIssuanceHistory.increaseClaimableByBatch(rewardees, rewards, endBlock);

        assertEq(tanIssuanceHistory.lastSettlementBlock(), endBlock);
        assertEq(tanIssuanceHistory.cumulativeRewards(user), userReward);
        assertEq(tanIssuanceHistory.cumulativeRewards(referrer), referrerReward);
    }
}
