// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";

contract ConsensusRegistryTest is Test {
    ConsensusRegistry public registry;
    address public owner = address(0x1);
    address public validator0 = address(0x2);
    ConsensusRegistry.ValidatorInfo[] initialValidators; // contains validator0 only
    address public validator1 = address(0x42);
    address public sysAddress;

    bytes public blsPubkey = hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456";
    bytes public blsSig = hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890";
    bytes32 public ed25519Pubkey = bytes32(hex"1234567890123456789012345678901234567890123456789012345678901234");

    uint256 public stakeAmount = 1_000_000 ether;
    uint256 public minWithdrawAmount = 10_000 ether;

    function setUp() public {
        initialValidators.push(ConsensusRegistry.ValidatorInfo(
            _createRandomBlsPubkey(stakeAmount), keccak256(abi.encode(stakeAmount)), validator0, uint32(0), uint32(0), uint16(1), bytes4(0), ConsensusRegistry.ValidatorStatus.Active
        ));
        registry = new ConsensusRegistry(
            stakeAmount,
            minWithdrawAmount,
            initialValidators,
            new uint256[](0),
            owner
        );
        sysAddress = registry.SYSTEM_ADDRESS();
        
        vm.deal(validator1, 100_000_000 ether);
    }

    // Test for successful staking
    function test_stake() public {
        // Check event emission
        uint32 activationEpoch = uint32(2);
        uint16 expectedIndex = uint16(2);
        vm.expectEmit(true, true, true, true);
        emit ConsensusRegistry.ValidatorPendingActivation(
            ConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator1,
                activationEpoch,
                uint32(0),
                expectedIndex,
                bytes4(0),
                ConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);
        
        // Check validator information
        ConsensusRegistry.ValidatorInfo[] memory validators = registry.getValidators(ConsensusRegistry.ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator1);
        assertEq(validators[0].blsPubkey, blsPubkey);
        assertEq(validators[0].ed25519Pubkey, ed25519Pubkey);
        assertEq(validators[0].activationEpoch, activationEpoch);
        assertEq(validators[0].exitEpoch, uint32(0));
        assertEq(validators[0].unused, bytes4(0));
        assertEq(validators[0].validatorIndex, expectedIndex);
        assertEq(uint8(validators[0].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.PendingActivation));

        // Finalize epoch twice to reach validator1 activationEpoch
        vm.startPrank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        // use 2 member array for committee now that there are 2 active
        registry.finalizePreviousEpoch(32, new uint256[](2), new ConsensusRegistry.StakeInfo[](0));
        vm.stopPrank();

        // Check validator information
        ConsensusRegistry.ValidatorInfo[] memory activeValidators = registry.getValidators(ConsensusRegistry.ValidatorStatus.Active);
        assertEq(activeValidators.length, 2);
        assertEq(activeValidators[0].ecdsaPubkey, validator0);
        assertEq(activeValidators[1].ecdsaPubkey, validator1);
        assertEq(uint8(activeValidators[1].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.Active));
    }

    function testRevert_stake_inblsPubkeyLength() public {        
        vm.prank(validator1);
        vm.expectRevert(ConsensusRegistry.InvalidBLSPubkey.selector);
        registry.stake{value: stakeAmount}('', blsSig, ed25519Pubkey);
    }

    function testRevert_stake_invalidBlsSigLength() public {        
        vm.prank(validator1);
        vm.expectRevert(ConsensusRegistry.InvalidProof.selector);
        registry.stake{value: stakeAmount}(blsPubkey, '', ed25519Pubkey);
    }

    // Test for incorrect stake amount
    function test_stake_incorrectStakeAmount() public {
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ConsensusRegistry.InvalidStakeAmount.selector, 0));
        registry.stake{value: 0}(blsPubkey, blsSig, ed25519Pubkey);
    }
        
function test_exit() public {
        // First stake
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to twice reach activation epoch
        vm.startPrank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        registry.finalizePreviousEpoch(32, new uint256[](2), new ConsensusRegistry.StakeInfo[](0));
        vm.stopPrank();

        // Check event emission
        uint32 activationEpoch = uint32(2);
        uint32 exitEpoch = uint32(4);
        uint16 expectedIndex = 2;
        vm.expectEmit(true, true, true, true);
        emit ConsensusRegistry.ValidatorPendingExit(
            ConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator1,
                activationEpoch,
                exitEpoch,
                expectedIndex,
                bytes4(0),
                ConsensusRegistry.ValidatorStatus.PendingExit
            )
        );        
        // Exit
        vm.prank(validator1);
        registry.exit();

        // Check validator information is pending exit
        ConsensusRegistry.ValidatorInfo[] memory pendingExitValidators = registry.getValidators(ConsensusRegistry.ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.PendingExit));
        
        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        vm.stopPrank();

        // Check validator information is exited
        ConsensusRegistry.ValidatorInfo[] memory exitValidators = registry.getValidators(ConsensusRegistry.ValidatorStatus.Exited);
        assertEq(exitValidators.length, 1);
        assertEq(exitValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(exitValidators[0].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.Exited));
    }

    function test_exit_rejoin() public {
        // First stake
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to twice reach activation epoch
        vm.startPrank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        registry.finalizePreviousEpoch(32, new uint256[](2), new ConsensusRegistry.StakeInfo[](0));
        vm.stopPrank();

        // Exit
        vm.prank(validator1);
        registry.exit();
        
        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        vm.stopPrank();

        // Check event emission
        uint32 newActivationEpoch = registry.getCurrentEpoch() + 2;
        uint32 exitEpoch = uint32(4);
        uint16 expectedIndex = 2;
        vm.expectEmit(true, true, true, true);
        emit ConsensusRegistry.ValidatorPendingActivation(
            ConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator1,
                newActivationEpoch,
                exitEpoch,
                expectedIndex,
                bytes4(0),
                ConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        // Re-stake after exit
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);
        
        // Check validator information
        ConsensusRegistry.ValidatorInfo[] memory validators = registry.getValidators(ConsensusRegistry.ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator1);
        assertEq(uint8(validators[0].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.PendingActivation));
    }

    // Test for exit by a non-validator
    function test_exit_nonValidator() public {
        address nonValidator = address(0x3);
        
        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(ConsensusRegistry.NotValidator.selector, nonValidator));
        registry.exit();
    }

    // Test for exit by a validator who is not active
    function testFuzz_exit_notActive() public {
        // First stake
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);
        
        // Attempt to exit without being active
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ConsensusRegistry.InvalidStatus.selector, ConsensusRegistry.ValidatorStatus.PendingActivation));
        registry.exit();
    }

    function test_unstake() public {
        // First stake
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to process stake
        vm.prank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        
        // Finalize epoch again to reach validator1 activationEpoch
        vm.prank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](2), new ConsensusRegistry.StakeInfo[](0));

        // Check validator information
        ConsensusRegistry.ValidatorInfo[] memory validators = registry.getValidators(ConsensusRegistry.ValidatorStatus.Active);
        assertEq(validators.length, 2);
        assertEq(validators[0].ecdsaPubkey, validator0);
        assertEq(validators[1].ecdsaPubkey, validator1);
        assertEq(uint8(validators[1].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.Active));

        // Exit
        vm.prank(validator1);
        registry.exit();

        // Check validator information
        ConsensusRegistry.ValidatorInfo[] memory pendingExitValidators = registry.getValidators(ConsensusRegistry.ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.PendingExit));
        
        // Finalize epoch twice to process exit
        vm.startPrank(sysAddress);
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        registry.finalizePreviousEpoch(32, new uint256[](1), new ConsensusRegistry.StakeInfo[](0));
        vm.stopPrank();

        // Check validator information
        ConsensusRegistry.ValidatorInfo[] memory exitedValidators = registry.getValidators(ConsensusRegistry.ValidatorStatus.Exited);
        assertEq(exitedValidators.length, 1);
        assertEq(exitedValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(exitedValidators[0].currentStatus), uint8(ConsensusRegistry.ValidatorStatus.Exited));

        // Capture pre-exit balance
        uint256 initialBalance = validator1.balance;

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit ConsensusRegistry.RewardsClaimed(validator1, stakeAmount);
        // Unstake
        vm.prank(validator1);
        registry.unstake();
        
        // Check balance after unstake
        uint256 finalBalance = validator1.balance;
        assertEq(finalBalance, initialBalance + stakeAmount);
    }

     // Test for unstake by a non-validator
    function test_unstake_nonValidator() public {
        address nonValidator = address(0x3);
        
        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(ConsensusRegistry.NotValidator.selector, nonValidator));
        registry.unstake();
    }

    // Test for unstake by a validator who has not exited
    function testFuzz_unstake_notExited() public {
        // First stake
        vm.prank(validator1);
        registry.stake{value: stakeAmount}(blsPubkey, blsSig, ed25519Pubkey);
        
        // Attempt to unstake without exiting
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ConsensusRegistry.InvalidStatus.selector, ConsensusRegistry.ValidatorStatus.PendingActivation));
        registry.unstake();
    }


    function _createRandomBlsPubkey(uint256 seed) internal returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, bytes16(keccak256(abi.encode(seedHash))));
    }


    function _createRandomBlsSig(uint256 seed) internal returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, keccak256(abi.encode(seedHash)), bytes32(0));
    }
}