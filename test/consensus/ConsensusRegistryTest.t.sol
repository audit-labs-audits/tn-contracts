// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { SystemCallable } from "src/consensus/SystemCallable.sol";
import { StakeManager } from "src/consensus/StakeManager.sol";
import { StakeInfo, IStakeManager } from "src/consensus/interfaces/IStakeManager.sol";
import { RWTEL } from "src/RWTEL.sol";
import { ConsensusRegistryTestUtils } from "./ConsensusRegistryTestUtils.sol";

contract ConsensusRegistryTest is ConsensusRegistryTestUtils {
    function setUp() public {
        // etch code and storage onto registry precompile address
        consensusRegistry = ConsensusRegistry(0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        vm.etch(address(consensusRegistry), type(ERC1967Proxy).runtimeCode);
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(consensusRegistry), implementationSlot, bytes32(abi.encode(address(consensusRegistryImpl))));

        consensusRegistry.initialize(
            address(rwTEL), stakeAmount_, minWithdrawAmount_, consensusBlockReward_, initialValidators, crOwner
        );

        sysAddress = consensusRegistry.SYSTEM_ADDRESS();

        vm.deal(validator5, 100_000_000 ether);

        // deal RWTEL max TEL supply to test reward distribution
        vm.deal(address(rwTEL), telMaxSupply);
    }

    function test_setUp() public {
        assertEq(consensusRegistry.getCurrentEpoch(), 0);
        ValidatorInfo[] memory active = consensusRegistry.getValidators(ValidatorStatus.Active);
        for (uint256 i; i < 3; ++i) {
            assertEq(active[i].ecdsaPubkey, initialValidators[i].ecdsaPubkey);
            assertEq(consensusRegistry.getValidatorTokenId(initialValidators[i].ecdsaPubkey), i + 1);
            assertEq(consensusRegistry.getValidatorByTokenId(i + 1).ecdsaPubkey, initialValidators[i].ecdsaPubkey);
            vm.expectRevert();
            consensusRegistry.isRetired(i + 1);

            EpochInfo memory info = consensusRegistry.getEpochInfo(uint32(i));
            for (uint256 j; j < 4; ++j) {
                assertEq(info.committee[j], initialValidators[j].ecdsaPubkey);
                assertEq(consensusRegistry.stakeInfo(initialValidators[j].ecdsaPubkey).tokenId, j + 1);
            }
        }
        assertEq(consensusRegistry.totalSupply(), 4);
        assertEq(consensusRegistry.stakeVersion(), 0);
        assertEq(consensusRegistry.stakeConfig(0).stakeAmount, stakeAmount_);
        assertEq(consensusRegistry.stakeConfig(0).minWithdrawAmount, minWithdrawAmount_);
    }

    // Test for successful staking
    function test_stake() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        assertEq(consensusRegistry.getValidators(ValidatorStatus.Staked).length, 0);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit ValidatorStaked(
            ValidatorInfo(
                validator5BlsPubkey,
                validator5,
                PENDING_EPOCH,
                uint32(0),
                ValidatorStatus.Staked,
                false,
                false,
                uint8(0)
            )
        );
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount_ }(validator5BlsPubkey);

        // Check validator information
        ValidatorInfo[] memory validators = consensusRegistry.getValidators(ValidatorStatus.Staked);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator5);
        assertEq(validators[0].blsPubkey, validator5BlsPubkey);
        assertEq(validators[0].activationEpoch, PENDING_EPOCH);
        assertEq(validators[0].exitEpoch, uint32(0));
        assertEq(validators[0].isRetired, false);
        assertEq(validators[0].isDelegated, false);
        assertEq(validators[0].stakeVersion, uint8(0));
        assertEq(uint8(validators[0].currentStatus), uint8(ValidatorStatus.Staked));
    }

    function test_activate() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount_ }(validator5BlsPubkey);

        // activate and conclude epoch to reach validator5 activationEpoch
        uint256 numActiveBefore = consensusRegistry.getValidators(ValidatorStatus.Active).length;
        vm.prank(validator5);
        consensusRegistry.activate();

        ValidatorInfo[] memory activeValidators = consensusRegistry.getValidators(ValidatorStatus.Active);
        assertEq(activeValidators.length, numActiveBefore + 1);

        uint32 activationEpoch = consensusRegistry.getCurrentEpoch() + 1;
        vm.expectEmit(true, true, true, true);
        emit ValidatorActivated(
            ValidatorInfo(
                validator5BlsPubkey,
                validator5,
                activationEpoch,
                uint32(0),
                ValidatorStatus.Active,
                false,
                false,
                uint8(0)
            )
        );
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](activeValidators.length));
        vm.stopPrank();

        // Check validator information
        assertEq(activeValidators[0].ecdsaPubkey, validator1);
        assertEq(activeValidators[1].ecdsaPubkey, validator2);
        assertEq(activeValidators[2].ecdsaPubkey, validator3);
        assertEq(activeValidators[3].ecdsaPubkey, validator4);
        assertEq(activeValidators[4].ecdsaPubkey, validator5);
        for (uint256 i; i < activeValidators.length - 1; ++i) {
            assertEq(uint8(activeValidators[i].currentStatus), uint8(ValidatorStatus.Active));
        }
        assertEq(uint8(activeValidators[4].currentStatus), uint8(ValidatorStatus.PendingActivation));
    }

    function testRevert_stake_invalidblsPubkeyLength() public {
        vm.prank(validator5);
        vm.expectRevert(InvalidBLSPubkey.selector);
        consensusRegistry.stake{ value: stakeAmount_ }("");
    }

    // Test for incorrect stake amount
    function testRevert_stake_invalidStakeAmount() public {
        vm.prank(validator5);
        vm.expectRevert(abi.encodeWithSelector(IStakeManager.InvalidStakeAmount.selector, 0));
        consensusRegistry.stake{ value: 0 }(validator5BlsPubkey);
    }

    function test_beginExit() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount_ }(validator5BlsPubkey);

        // activate and conclude epoch to reach validator5 activationEpoch
        vm.prank(validator5);
        consensusRegistry.activate();

        uint32 activationEpoch = consensusRegistry.getCurrentEpoch() + 1;
        uint256 numActiveBefore = consensusRegistry.getValidators(ValidatorStatus.Active).length;

        vm.prank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](numActiveBefore)).length;

        assertEq(consensusRegistry.getValidators(ValidatorStatus.PendingExit).length, 0);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit ValidatorPendingExit(
            ValidatorInfo(
                validator5BlsPubkey,
                validator5,
                activationEpoch,
                PENDING_EPOCH,
                ValidatorStatus.PendingExit,
                false,
                false,
                uint8(0)
            )
        );
        // begin exit
        vm.prank(validator5);
        consensusRegistry.beginExit();

        // Check validator information is pending exit
        ValidatorInfo[] memory pendingExitValidators = consensusRegistry.getValidators(ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator5);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(ValidatorStatus.PendingExit));

        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](4));
        consensusRegistry.concludeEpoch(new address[](4));
        vm.stopPrank();

        assertEq(consensusRegistry.getValidators(ValidatorStatus.PendingExit).length, 0);
        assertEq(consensusRegistry.getValidators(ValidatorStatus.Active).length, 4);

        // Check validator information is exited
        ValidatorInfo[] memory exitValidators = consensusRegistry.getValidators(ValidatorStatus.Exited);
        assertEq(exitValidators.length, 1);
        assertEq(exitValidators[0].ecdsaPubkey, validator5);
        assertEq(uint8(exitValidators[0].currentStatus), uint8(ValidatorStatus.Exited));
    }

    // Test for exit by a non-validator
    function testRevert_beginExit_nonValidator() public {
        address nonValidator = address(0x3);

        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenId.selector, 0));
        consensusRegistry.beginExit();
    }

    // Test for exit by a validator who is not active
    function testRevert_beginExit_notActive() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount_ }(validator5BlsPubkey);

        // Attempt to exit without being active
        vm.prank(validator5);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, ValidatorStatus.Staked));
        consensusRegistry.beginExit();
    }

    function test_unstake() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount_ }(validator5BlsPubkey);

        // activate and conclude epoch twice to reach validator5 activationEpoch
        vm.prank(validator5);
        consensusRegistry.activate();

        uint256 numActive = consensusRegistry.getValidators(ValidatorStatus.Active).length;
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](numActive));
        consensusRegistry.concludeEpoch(new address[](numActive));
        vm.stopPrank();

        // Exit
        vm.prank(validator5);
        consensusRegistry.beginExit();

        // Finalize epoch twice to process exit
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](4));
        consensusRegistry.concludeEpoch(new address[](4));
        vm.stopPrank();

        // Capture pre-exit balance
        uint256 initialBalance = validator5.balance;

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(validator5, stakeAmount_);
        // Unstake
        vm.prank(validator5);
        consensusRegistry.unstake(validator5);

        // Check balance after unstake
        uint256 finalBalance = validator5.balance;
        assertEq(finalBalance, initialBalance + stakeAmount_);
    }

    // Test for unstake by a non-validator
    function testRevert_unstake_nonValidator() public {
        address nonValidator = address(0x3);

        vm.prank(crOwner);
        consensusRegistry.mint(nonValidator, 5);

        vm.prank(nonValidator);
        vm.expectRevert();
        consensusRegistry.unstake(nonValidator);
    }

    // Test for unstake by a validator who has not exited
    function testRevert_unstake_notExited() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount_ }(validator5BlsPubkey);

        // Attempt to unstake without exiting
        vm.prank(validator5);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, ValidatorStatus.Staked));
        consensusRegistry.unstake(validator5);
    }

    // Test for claim by a non-validator
    function testRevert_claimStakeRewards_nonValidator() public {
        address nonValidator = address(0x3);
        vm.deal(nonValidator, 10 ether);

        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenId.selector, 0));
        consensusRegistry.claimStakeRewards(nonValidator);
    }

    // Test for claim by a validator with insufficient rewards
    function testRevert_claimStakeRewards_insufficientRewards() public {
        // earn too little rewards for withdrawal
        uint232 notEnoughRewards = uint232(minWithdrawAmount_ - 1);
        uint24 validator1TokenId = 1;
        StakeInfo[] memory validator5Rewards = new StakeInfo[](1);
        validator5Rewards[0] = StakeInfo(validator1TokenId, notEnoughRewards);

        // finalize epoch to reach activation
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](4));
        consensusRegistry.incrementRewards(validator5Rewards);
        vm.stopPrank();

        // Attempt to claim rewards
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(IStakeManager.InsufficientRewards.selector, notEnoughRewards));
        consensusRegistry.claimStakeRewards(validator1);
    }

    function test_concludeEpoch_updatesEpochInfo() public {
        // Initialize test data
        address[] memory newCommittee = new address[](4);
        newCommittee[0] = address(0x69);
        newCommittee[1] = address(0x70);
        newCommittee[2] = address(0x71);
        newCommittee[3] = address(0x72);

        uint32 initialEpoch = consensusRegistry.getCurrentEpoch();
        assertEq(initialEpoch, 0);

        // Call the function
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(newCommittee);
        consensusRegistry.concludeEpoch(newCommittee);
        vm.stopPrank();

        // Fetch current epoch and verify it has incremented
        uint32 currentEpoch = consensusRegistry.getCurrentEpoch();
        assertEq(currentEpoch, initialEpoch + 2);

        // Verify future epoch information
        EpochInfo memory epochInfo = consensusRegistry.getEpochInfo(currentEpoch + 2);
        assertEq(epochInfo.blockHeight, 0);
        for (uint256 i; i < epochInfo.committee.length; ++i) {
            assertEq(epochInfo.committee[i], newCommittee[i]);
        }
    }

    // Attempt to call without sysAddress should revert
    function testRevert_concludeEpoch_OnlySystemCall() public {
        vm.expectRevert(abi.encodeWithSelector(SystemCallable.OnlySystemCall.selector, address(this)));
        consensusRegistry.concludeEpoch(new address[](4));
    }
}
