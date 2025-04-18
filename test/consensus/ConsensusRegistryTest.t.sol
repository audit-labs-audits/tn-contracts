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

contract ConsensusRegistryTest is ConsensusRegistryTestUtils, Test {
    function setUp() public {
        // etch code and storage onto registry precompile address
        consensusRegistry = ConsensusRegistry(0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        vm.etch(address(consensusRegistry), type(ERC1967Proxy).runtimeCode);
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(consensusRegistry), implementationSlot, bytes32(abi.encode(address(consensusRegistryImpl))));

        consensusRegistry.initialize(address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, crOwner);

        sysAddress = consensusRegistry.SYSTEM_ADDRESS();

        vm.deal(validator5, 100_000_000 ether);

        // deal RWTEL max TEL supply to test reward distribution
        vm.deal(address(rwTEL), telMaxSupply);
    }

    /// @dev To examine the ConsensusRegistry's storage, uncomment the console log statements
    function test_setUp() public view {
        bytes32 ownerSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        bytes32 ownerWord = vm.load(address(consensusRegistry), ownerSlot);
        console2.logString("OwnableUpgradeable slot0");
        console2.logBytes32(ownerWord);
        assertEq(address(uint160(uint256(ownerWord))), crOwner);

        /**
         *
         *   ERC721StorageLocation
         *
         */
        bytes32 _ownersSlot = 0x80bb2b638cc20bc4d0a60d66940f3ab4a00c1d7b313497ca82fb0b4ab0079302;
        uint256 tokenId = 1;
        // 0xbdb57ebf9f236e21a27420aca53e57b3f4d9c46b35290ca11821e608cdab5f19
        bytes32 tokenId1OwnersSlot = keccak256(abi.encodePacked(bytes32(tokenId), _ownersSlot));
        bytes32 returnedOwner = vm.load(address(consensusRegistry), tokenId1OwnersSlot);
        assertEq(address(uint160(uint256(returnedOwner))), validator1);

        bytes32 _balancesSlot = 0x80bb2b638cc20bc4d0a60d66940f3ab4a00c1d7b313497ca82fb0b4ab0079303;
        // 0x89DC4F27410B0F3ACC713877BE759A601621941908FBC40B97C5004C02763CF8
        bytes32 validator1BalancesSlot = keccak256(abi.encodePacked(uint256(uint160(validator1)), _balancesSlot));
        bytes32 returnedBalance = vm.load(address(consensusRegistry), validator1BalancesSlot);
        assertEq(uint256(returnedBalance), 1);

        /**
         *
         *   stakeManagerStorage
         *
         */
        bytes32 stakeManagerSlot = 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400;

        bytes32 rwtelWord = vm.load(address(consensusRegistry), stakeManagerSlot);
        console2.logString("StakeManager slot0");
        console2.logBytes32(rwtelWord);
        assertEq(address(uint160(uint256(rwtelWord))), address(rwTEL));

        bytes32 stakeAmountWord = vm.load(address(consensusRegistry), bytes32(uint256(stakeManagerSlot) + 1));
        console2.logString("StakeManager slot1");
        console2.logBytes32(stakeAmountWord);
        assertEq(uint256(stakeAmountWord), stakeAmount);

        bytes32 minWithdrawAmountWord = vm.load(address(consensusRegistry), bytes32(uint256(stakeManagerSlot) + 2));
        console2.logString("StakeManager slot2");
        console2.logBytes32(minWithdrawAmountWord);
        assertEq(uint256(minWithdrawAmountWord), minWithdrawAmount);

        bytes32 stakeInfoSlot = 0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7403;
        // 0xf72eacdc698a36cb279844370e2c8c845481ad672ff1e7effa7264be6d6a9fd2
        bytes32 stakeInfovalidator1Slot = keccak256(abi.encodePacked(uint256(uint160(validator1)), stakeInfoSlot));
        bytes32 returnedStakeInfoTokenId = vm.load(address(consensusRegistry), stakeInfovalidator1Slot);
        assertEq(returnedStakeInfoTokenId, bytes32(uint256(uint24(1)))); // validator1's tokenId == 1

        /**
         *
         *   consensusRegistryStorage
         *
         */
        bytes32 consensusRegistrySlot = 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100;

        bytes32 currentEpochAndPointer = vm.load(address(consensusRegistry), consensusRegistrySlot);
        console2.logString("ConsensusRegistry slot0 : currentEpoch & epochPointer");
        console2.logBytes32(currentEpochAndPointer);
        assertEq(uint256(currentEpochAndPointer), 0);

        /**
         *
         *   epochInfo
         *
         */
        bytes32 epochInfoBaseSlot = 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23101;

        // epochInfo[0]
        bytes32 epochInfo0Len = vm.load(address(consensusRegistry), epochInfoBaseSlot);
        console2.logString("ConsensusRegistry slot1 : epochInfo[0].committee.length");
        console2.logBytes32(epochInfo0Len);
        assertEq(uint256(epochInfo0Len), 4); // current len for 4 initial validators in committee

        // epochInfo[0].committee => keccak256(abi.encode(epochInfoBaseSlot)
        bytes32 epochInfo0Slot = 0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39;
        console2.logString(
            "epochInfo[0].committee == slot 0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39"
        );
        bytes32 epochInfo0 = vm.load(address(consensusRegistry), epochInfo0Slot);
        console2.logBytes32(epochInfo0);
        assertEq(address(uint160(uint256(epochInfo0))), validator1);

        // epochInfo[1]
        bytes32 epochInfo1Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 2));
        // blockHeight, ie slot2, is not known at genesis
        console2.logString("ConsensusRegistry slot3 : epochInfo[1].committee.length");
        console2.logBytes32(epochInfo1Len);
        assertEq(uint256(epochInfo1Len), 4); // current len for 4 initial validators in committee

        // epochInfo[1].committee => keccak256(abi.encode(epochInfoBaseSlot + 2)
        bytes32 epochInfo1Slot = 0x96a201c8a417846842c79be2cd1e33440471871a6cf94b34c8f286aaeb24ad6b;
        console2.logString(
            "epochInfo[1].committee == slot 0x96a201c8a417846842c79be2cd1e33440471871a6cf94b34c8f286aaeb24ad6b"
        );
        bytes32 epochInfo1 = vm.load(address(consensusRegistry), epochInfo1Slot);
        console2.logBytes32(epochInfo1);
        assertEq(address(uint160(uint256(epochInfo1))), validator1);

        // epochInfo[2]
        bytes32 epochInfo2Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 4));
        // blockHeight, ie slot4, is not known at genesis
        console2.logString("ConsensusRegistry slot5 : epochInfo[2].committee.length");
        console2.logBytes32(epochInfo2Len);
        assertEq(uint256(epochInfo2Len), 4); // current len for 4 initial validators in committee

        // epochInfo[2].committee => keccak256(abi.encode(epochInfoBaseSlot + 4)
        bytes32 epochInfo2Slot = 0x14d1f3ad8599cd8151592ddeade449f790add4d7065a031fbe8f7dbb1833e0a9;
        console2.logString(
            "epochInfo[2].committee == slot 0x14d1f3ad8599cd8151592ddeade449f790add4d7065a031fbe8f7dbb1833e0a9"
        );
        bytes32 epochInfo2 = vm.load(address(consensusRegistry), epochInfo2Slot);
        console2.logBytes32(epochInfo2);
        assertEq(address(uint160(uint256(epochInfo2))), validator1);

        // epochInfo[3] (not set at genesis so all members are 0)
        bytes32 epochInfo3Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 6));
        // blockHeight, ie slot4, is not known (and not set) at genesis
        console2.logString("ConsensusRegistry slot7 : epochInfo[3].committee.length");
        console2.logBytes32(epochInfo3Len);
        assertEq(uint256(epochInfo3Len), 0); // not set at genesis

        // epochInfo[3].committee => keccak256(abi.encode(epochInfoBaseSlot + 6)
        bytes32 epochInfo3Slot = 0x79af749cb95fe9cb496550259d0d961dfb54cb2ad0ce32a4118eed13c438a935;
        console2.logString(
            "epochInfo[3].committee == slot 0x79af749cb95fe9cb496550259d0d961dfb54cb2ad0ce32a4118eed13c438a935"
        );
        bytes32 epochInfo3 = vm.load(address(consensusRegistry), epochInfo3Slot);
        console2.logBytes32(epochInfo3);
        assertEq(address(uint160(uint256(epochInfo3))), address(0x0));

        /**
         *
         *   futureEpochInfo
         *
         */
        bytes32 futureEpochInfoBaseSlot = 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23109;

        // first 3 futureEpochInfo base slots store `length == 4`
        for (uint256 i; i < 3; ++i) {
            bytes32 futureEpochInfoCommitteeLen =
                vm.load(address(consensusRegistry), bytes32(uint256(futureEpochInfoBaseSlot) + i));
            console2.logString(string.concat("futureEpochInfo[", LibString.toString(i), "].committee.length"));
            console2.logBytes32(futureEpochInfoCommitteeLen);
            assertEq(uint256(futureEpochInfoCommitteeLen), 4);
        }

        // first 3 futureEpochInfo arrays store
        for (uint256 i; i < 3; ++i) {
            bytes32 futureEpochInfoSlot = keccak256(abi.encode(uint256(futureEpochInfoBaseSlot) + i));
            console2.logString("Start of `futureEpochInfo` array, slot :");
            console2.logBytes32(futureEpochInfoSlot);

            bytes32 futureEpochInfo0 = vm.load(address(consensusRegistry), futureEpochInfoSlot);
            console2.logString("value :");
            console2.logBytes32(futureEpochInfo0);
            assertEq(address(uint160(uint256(futureEpochInfo0))), validator1);

            bytes32 futureEpochInfo1 = vm.load(address(consensusRegistry), bytes32(uint256(futureEpochInfoSlot) + 1));
            console2.logString("value :");
            console2.logBytes32(futureEpochInfo1);
            assertEq(address(uint160(uint256(futureEpochInfo1))), validator2);

            bytes32 futureEpochInfo2 = vm.load(address(consensusRegistry), bytes32(uint256(futureEpochInfoSlot) + 2));
            console2.logString("value :");
            console2.logBytes32(futureEpochInfo2);
            assertEq(address(uint160(uint256(futureEpochInfo2))), validator3);

            bytes32 futureEpochInfo3 = vm.load(address(consensusRegistry), bytes32(uint256(futureEpochInfoSlot) + 3));
            console2.logString("value :");
            console2.logBytes32(futureEpochInfo3);
            assertEq(address(uint160(uint256(futureEpochInfo3))), validator4);
        }

        /**
         *
         *   validators
         *
         */
        bytes32 validatorsBaseSlot = 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f2310d;

        bytes32 validatorsLen = vm.load(address(consensusRegistry), validatorsBaseSlot);
        console2.logString("validators.length");
        console2.logBytes32(validatorsLen);
        assertEq(uint256(validatorsLen), 5); // current len for 1 undefined and 4 active validators

        // keccak256(abi.encode(validatorsBaseSlot))
        bytes32 validatorsSlot = 0x8127b3d06d1bc4fc33994fe62c6bb5ac3963bb2d1bcb96f34a40e1bdc5624a27;

        // first 2 slots belong to the undefined validator
        for (uint256 i; i < 2; ++i) {
            bytes32 emptySlot = vm.load(address(consensusRegistry), bytes32(uint256(validatorsSlot) + i));
            assertEq(emptySlot, bytes32(0x0));
        }

        // ValidatorInfo occupies 2 base slots (blsPubkeyLen, packed(ecdsaPubkey, activation, exit, tokenId,
        // currentStatus))
        bytes32 firstValidatorSlot = 0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A29;

        // check BLS pubkey
        bytes32 returnedBLSPubkeyLen = vm.load(address(consensusRegistry), firstValidatorSlot);
        /// @notice For byte arrays that store data.length >= 32, the main slot stores `length * 2 + 1` (content is
        /// stored as usual in keccak256(slot))
        assertEq(returnedBLSPubkeyLen, bytes32(uint256(0xc1))); // `0xc1 == blsPubkey.length * 2 + 1`

        // check bls pubkeys and packed slots
        for (uint256 i; i < initialValidators.length; ++i) {
            ValidatorInfo memory currentValidator = initialValidators[i];

            bytes memory blsKey = currentValidator.blsPubkey;
            // since BLS pubkey is 96bytes, it occupies 3 slots
            bytes32 blsPubkeyPartA;
            bytes32 blsPubkeyPartB;
            bytes32 blsPubkeyPartC;
            assembly {
                // Load the first 32 bytes (leftmost)
                blsPubkeyPartA := mload(add(blsKey, 0x20))
                // Load the second 32 bytes (middle)
                blsPubkeyPartB := mload(add(blsKey, 0x40))
                // Load the third 32 bytes (rightmost)
                blsPubkeyPartC := mload(add(blsKey, 0x60))
            }

            bytes32 currentValidatorSlot = bytes32(uint256(firstValidatorSlot) + i * 2);
            bytes32 returnedBLSPubkeyA =
                vm.load(address(consensusRegistry), keccak256(abi.encode(currentValidatorSlot)));
            assertEq(returnedBLSPubkeyA, blsPubkeyPartA);
            bytes32 returnedBLSPubkeyB =
                vm.load(address(consensusRegistry), bytes32(uint256(keccak256(abi.encode(currentValidatorSlot))) + 1));
            assertEq(returnedBLSPubkeyB, blsPubkeyPartB);
            bytes32 returnedBLSPubkeyC =
                vm.load(address(consensusRegistry), bytes32(uint256(keccak256(abi.encode(currentValidatorSlot))) + 2));
            assertEq(returnedBLSPubkeyC, blsPubkeyPartC);

            // check packed slots
            uint256 currentValidatorTokenId = i + 1;
            bytes32 expectedPackedValues = bytes32(
                abi.encodePacked(
                    ValidatorStatus.Active,
                    uint24(currentValidatorTokenId),
                    uint32(0),
                    uint32(0),
                    currentValidator.ecdsaPubkey
                )
            );

            // packed slots are offset by 1
            bytes32 currentValidatorPackedSlot = bytes32(uint256(currentValidatorSlot) + 1);
            bytes32 returnedPackedValues = vm.load(address(consensusRegistry), currentValidatorPackedSlot);
            assertEq(expectedPackedValues, returnedPackedValues);
        }

        // (consensusRegistrySlot + 5)
        bytes32 numGenesisValidatorsSlot = 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f2310E;
        bytes32 returnedNumGenesisValidators = vm.load(address(consensusRegistry), numGenesisValidatorsSlot);
        assertEq(uint256(returnedNumGenesisValidators), 4);
    }

    // Test for successful staking
    function test_stake() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        assertEq(consensusRegistry.getValidators(ValidatorStatus.PendingActivation).length, 0);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit ValidatorPendingActivation(
            ValidatorInfo(
                validator5BlsPubkey,
                validator5,
                PENDING_EPOCH,
                uint32(0),
                uint24(tokenId),
                ValidatorStatus.PendingActivation
            )
        );
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // Check validator information
        ValidatorInfo[] memory validators = consensusRegistry.getValidators(ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator5);
        assertEq(validators[0].blsPubkey, validator5BlsPubkey);
        assertEq(validators[0].activationEpoch, PENDING_EPOCH);
        assertEq(validators[0].exitEpoch, uint32(0));
        assertEq(validators[0].tokenId, tokenId);
        assertEq(uint8(validators[0].currentStatus), uint8(ValidatorStatus.PendingActivation));
    }

    function test_activate() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // activate and conclude epoch twice to reach validator5 activationEpoch
        uint256 numActiveBefore = consensusRegistry.getValidators(ValidatorStatus.Active).length;
        uint32 activationEpoch = consensusRegistry.getCurrentEpoch() + 2;
        vm.expectEmit(true, true, true, true);
        emit ValidatorActivated(
            ValidatorInfo(
                validator5BlsPubkey, validator5, activationEpoch, uint32(0), uint24(tokenId), ValidatorStatus.Active
            )
        );
        vm.prank(validator5);
        consensusRegistry.activate();

        ValidatorInfo[] memory activeValidators = consensusRegistry.getValidators(ValidatorStatus.Active);
        assertEq(activeValidators.length, numActiveBefore + 1);

        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](activeValidators.length));
        consensusRegistry.concludeEpoch(new address[](activeValidators.length));
        vm.stopPrank();

        // Check validator information
        assertEq(activeValidators[0].ecdsaPubkey, validator1);
        assertEq(activeValidators[1].ecdsaPubkey, validator2);
        assertEq(activeValidators[2].ecdsaPubkey, validator3);
        assertEq(activeValidators[3].ecdsaPubkey, validator4);
        assertEq(activeValidators[4].ecdsaPubkey, validator5);
        for (uint256 i; i < activeValidators.length; ++i) {
            assertEq(uint8(activeValidators[i].currentStatus), uint8(ValidatorStatus.Active));
        }
    }

    function testRevert_stake_invalidblsPubkeyLength() public {
        vm.prank(validator5);
        vm.expectRevert(InvalidBLSPubkey.selector);
        consensusRegistry.stake{ value: stakeAmount }("");
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
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // activate and conclude epoch to reach validator5 activationEpoch
        vm.prank(validator5);
        consensusRegistry.activate();

        uint32 activationEpoch = consensusRegistry.getCurrentEpoch() + 2;
        uint256 numActiveAfter = consensusRegistry.getValidators(ValidatorStatus.Active).length;

        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](numActiveAfter));
        consensusRegistry.concludeEpoch(new address[](numActiveAfter));
        vm.stopPrank();

        assertEq(consensusRegistry.getValidators(ValidatorStatus.PendingExit).length, 0);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit ValidatorPendingExit(
            ValidatorInfo(
                validator5BlsPubkey,
                validator5,
                activationEpoch,
                PENDING_EPOCH,
                uint24(tokenId),
                ValidatorStatus.PendingExit
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
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // Attempt to exit without being active
        vm.prank(validator5);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, ValidatorStatus.PendingActivation));
        consensusRegistry.beginExit();
    }

    function test_unstake() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

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
        emit RewardsClaimed(validator5, stakeAmount);
        // Unstake
        vm.prank(validator5);
        consensusRegistry.unstake();

        // Check balance after unstake
        uint256 finalBalance = validator5.balance;
        assertEq(finalBalance, initialBalance + stakeAmount);
    }

    // todo test unstake with rewards applied

    // Test for unstake by a non-validator
    function testRevert_unstake_nonValidator() public {
        address nonValidator = address(0x3);

        vm.prank(crOwner);
        consensusRegistry.mint(nonValidator, 5);

        vm.prank(nonValidator);
        vm.expectRevert();
        consensusRegistry.unstake();
    }

    // Test for unstake by a validator who has not exited
    function testRevert_unstake_notExited() public {
        vm.prank(crOwner);
        uint256 tokenId = 5;
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // Attempt to unstake without exiting
        vm.prank(validator5);
        vm.expectRevert(abi.encodeWithSelector(InvalidStatus.selector, ValidatorStatus.PendingActivation));
        consensusRegistry.unstake();
    }

    // Test for claim by a non-validator
    function testRevert_claimStakeRewards_nonValidator() public {
        address nonValidator = address(0x3);
        vm.deal(nonValidator, 10 ether);

        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenId.selector, 0));
        consensusRegistry.claimStakeRewards();
    }

    // Test for claim by a validator with insufficient rewards
    function testRevert_claimStakeRewards_insufficientRewards() public {
        // earn too little rewards for withdrawal
        uint232 notEnoughRewards = uint232(minWithdrawAmount - 1);
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
        consensusRegistry.claimStakeRewards();
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
