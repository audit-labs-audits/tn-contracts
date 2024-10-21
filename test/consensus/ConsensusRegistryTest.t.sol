// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { IConsensusRegistry } from "src/consensus/interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "src/consensus/SystemCallable.sol";
import { StakeManager } from "src/consensus/StakeManager.sol";
import { StakeInfo, IStakeManager } from "src/consensus/interfaces/IStakeManager.sol";
import { RWTEL } from "src/RWTEL.sol";

contract ConsensusRegistryTest is Test {
    ConsensusRegistry public consensusRegistryImpl;
    ConsensusRegistry public consensusRegistry;
    RWTEL public rwTEL;

    address public owner = address(0xc0ffee);
    address public validator0 = address(0xbabe);
    IConsensusRegistry.ValidatorInfo[] initialValidators; // contains validator0 only
    address public validator1 = address(0x42);
    address public sysAddress;

    bytes public blsPubkey =
        hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456";
    bytes public blsSig =
        hex"123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890";
    bytes32 public ed25519Pubkey = bytes32(hex"1234567890123456789012345678901234567890123456789012345678901234");

    uint256 public telMaxSupply = 100_000_000_000 ether;
    uint256 public stakeAmount = 1_000_000 ether;
    uint256 public minWithdrawAmount = 10_000 ether;

    function setUp() public {
        // set RWTEL address (its bytecode is written after deploying ConsensusRegistry)
        rwTEL = RWTEL(address(0x7e1));

        // provide an initial validator as the network will launch with at least one validator
        bytes memory validator0BLSKey = _createRandomBlsPubkey(stakeAmount);
        bytes32 validator0ED25519Key = keccak256(abi.encode(minWithdrawAmount));
        initialValidators.push(
            IConsensusRegistry.ValidatorInfo(
                validator0BLSKey,
                validator0ED25519Key,
                validator0,
                uint32(0),
                uint32(0),
                uint16(1),
                bytes4(0),
                IConsensusRegistry.ValidatorStatus.Active
            )
        );
        consensusRegistryImpl = new ConsensusRegistry();
        consensusRegistry = ConsensusRegistry(payable(address(new ERC1967Proxy(address(consensusRegistryImpl), ""))));
        consensusRegistry.initialize(address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, owner);

        /// @dev debugging
        // bytes memory init = abi.encodeWithSelector(ConsensusRegistry.initialize.selector, address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, owner);
        // address(consensusRegistry).call(init);
        // console.logBytes(init);

        sysAddress = consensusRegistry.SYSTEM_ADDRESS();

        vm.deal(validator1, 100_000_000 ether);

        // deploy an RWTEL module and then use its bytecode to etch on a fixed address (use create2 in prod)
        RWTEL tmp =
            new RWTEL(address(consensusRegistry), address(0xbeef), "test", "TEST", 0, address(0x0), address(0x0), 0);
        vm.etch(address(rwTEL), address(tmp).code);
        // deal RWTEL max TEL supply to test reward distribution
        vm.deal(address(rwTEL), telMaxSupply);
    }

/* The following slots must be set at genesis, simulated in tests here with `initialize()`
0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC : 0x65B54A4646369D8AD83CB58A5A6B39F22FCD8CEE (impl addr)
0x89DC4F27410B0F3ACC713877BE759A601621941908FBC40B97C5004C02763CF8 : 1
0x9016D09D72D40FDAE2FD8CEAC6B6234C7706214FD39C1CD1E609A0528C199300 : `owner == 0xc0ffee`
0xBDB57EBF9F236E21A27420ACA53E57B3F4D9C46B35290CA11821E608CDAB5F19 : 0xBABE 
0xF0C57E16840DF040F15088DC2F81FE391C3923BEC73E23A9662EFC9C229C6A00 : 1
0xF72EACDC698A36CB279844370E2C8C845481AD672FF1E7EFFA7264BE6D6A9FD2 : 1
0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7400 : `rwTEL == 0x7e1`
0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7401 : `stakeAmount == 1000000000000000000000000`
0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7402 : `minWithdrawAmount == 10000000000000000000000`
0x6C797AE2807EC70DF875410B4E5AB5C71CCB6D14D528257BDBD8CBF0CC0E419A : 0x5252E822906CBBB969D9FA097BB45A6600000000000000000000000000000000 name
0x6C797AE2807EC70DF875410B4E5AB5C71CCB6D14D528257BDBD8CBF0CC0E4199 : 0x74F9856D5CCE56785FD436368E27C4DBFADB0AE8A9CE40873291AE4BCEBAD419
0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079300 : 0x436F6E73656E7375734E46540000000000000000000000000000000000000018 packed(symbol / decimals)
0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079301 : 0x434E465400000000000000000000000000000000000000000000000000000008 packed()
0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100 : `currentEpoch.epochPointer == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23101 : `epochInfo[0].committee.length == 1`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23102 : `epochInfo[0].blockHeight == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23103 : `epochInfo[1].committee.length == 1`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23104 : `epochInfo[1].blockHeight == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23105 : `epochInfo[2].committee.length == 1`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23106 : `epochInfo[2].blockHeight == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23107 : `epochInfo[3].committee.length == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23108 : `epochInfo[3].blockHeight == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F23109 : `futureEpochInfo[0].committee.length == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F2310a : `futureEpochInfo[1].committee.length == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F2310b : `futureEpochInfo[2].committee.length == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F2310c : `futureEpochInfo[3].committee.length == 0`
0xAF33537D204B7C8488A91AD2A40F2C043712BAD394401B7DD7BD4CB801F2310D : `validators.length == 2`
0x52B83978E270FCD9AF6931F8A7E99A1B79DC8A7AEA355D6241834B19E0A0EC39 : `keccak256(epochInfoBaseSlot) => epochInfos[0].committee` `validator0 == 0xBABE`
0x96A201C8A417846842C79BE2CD1E33440471871A6CF94B34C8F286AAEB24AD6B : `keccak256(epochInfoBaseSlot + 2) => epochInfos[1].committee` `[validator0] == [0xBABE]`
0x14D1F3AD8599CD8151592DDEADE449F790ADD4D7065A031FBE8F7DBB1833E0A9 : `keccak256(epochInfoBaseSlot + 4) => epochInfos[2].committee` `[validator0] == [0xBABE]`
0x79af749cb95fe9cb496550259d0d961dfb54cb2ad0ce32a4118eed13c438a935 : `keccak256(epochInfoBaseSlot + 6) => epochInfos[3].committee` `not set == [address(0x0)]`
0x8127b3d06d1bc4fc33994fe62c6bb5ac3963bb2d1bcb96f34a40e1bdc5624a27-2A : `validators[0]` (undefined)
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2B : `validators[1].blsPubkey.length == 97` (should be 96)
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2C : `validators[1].ed25519Pubkey == 0x011201DEED66C3B3A1B2AFB246B1436FD291A5F4B65E4FF0094A013CD922F803`
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2D : `validators[1].packed(validatorIndex.exitEpoch.activationEpoch.ecdsaPubkey) == 0x000000010000000000000000000000000000000000000000000000000000BABE`
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2E : `validators[1].packed(currentStatus.unused) == 0x0000000000000000000000000000000000000000000000000000000200000000 
*/                                                                                                                  
    function test_setUp() public {
        bytes32 ownerSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        bytes32 ownerWord = vm.load(address(consensusRegistry), ownerSlot);
        console2.logString("OwnableUpgradeable slot0");
        console2.logBytes32(ownerWord);
        assertEq(address(uint160(uint256(ownerWord))), owner);

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
        assertEq(uint256(epochInfo0Len), 1); // current len for 1 initial validator in committee

        // epochInfo[0].committee => keccak256(abi.encode(epochInfoBaseSlot)
        bytes32 epochInfo0Slot = 0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39;
        console2.logString("epochInfo[0].committee == slot 0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39");
        bytes32 epochInfo0 = vm.load(address(consensusRegistry), epochInfo0Slot);
        console2.logBytes32(epochInfo0);
        assertEq(address(uint160(uint256(epochInfo0))), validator0);

        // epochInfo[1]
        bytes32 epochInfo1Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 2));
        // blockHeight, ie slot2, is not known at genesis 
        console2.logString("ConsensusRegistry slot3 : epochInfo[1].committee.length");
        console2.logBytes32(epochInfo1Len);
        assertEq(uint256(epochInfo1Len), 1); // current len for 1 initial validator in committee

        // epochInfo[1].committee => keccak256(abi.encode(epochInfoBaseSlot + 2)
        bytes32 epochInfo1Slot = 0x96a201c8a417846842c79be2cd1e33440471871a6cf94b34c8f286aaeb24ad6b;
        console2.logString("epochInfo[1].committee == slot 0x96a201c8a417846842c79be2cd1e33440471871a6cf94b34c8f286aaeb24ad6b");
        bytes32 epochInfo1 = vm.load(address(consensusRegistry), epochInfo1Slot);
        console2.logBytes32(epochInfo1);
        assertEq(address(uint160(uint256(epochInfo1))), validator0);

        // epochInfo[2]
        bytes32 epochInfo2Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 4));
        // blockHeight, ie slot4, is not known at genesis 
        console2.logString("ConsensusRegistry slot5 : epochInfo[2].committee.length");
        console2.logBytes32(epochInfo2Len);
        assertEq(uint256(epochInfo2Len), 1); // current len for 1 initial validator in committee

        // epochInfo[2].committee => keccak256(abi.encode(epochInfoBaseSlot + 4)
        bytes32 epochInfo2Slot = 0x14d1f3ad8599cd8151592ddeade449f790add4d7065a031fbe8f7dbb1833e0a9;
        console2.logString("epochInfo[2].committee == slot 0x14d1f3ad8599cd8151592ddeade449f790add4d7065a031fbe8f7dbb1833e0a9");
        bytes32 epochInfo2 = vm.load(address(consensusRegistry), epochInfo2Slot);
        console2.logBytes32(epochInfo2);
        assertEq(address(uint160(uint256(epochInfo2))), validator0);

        // epochInfo[3] (not set at genesis so all members are 0)
        bytes32 epochInfo3Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 6));
        // blockHeight, ie slot4, is not known (and not set) at genesis 
        console2.logString("ConsensusRegistry slot7 : epochInfo[3].committee.length");
        console2.logBytes32(epochInfo3Len);
        assertEq(uint256(epochInfo3Len), 0); // not set at genesis

        // epochInfo[3].committee => keccak256(abi.encode(epochInfoBaseSlot + 6)
        bytes32 epochInfo3Slot = 0x79af749cb95fe9cb496550259d0d961dfb54cb2ad0ce32a4118eed13c438a935;
        console2.logString("epochInfo[3].committee == slot 0x79af749cb95fe9cb496550259d0d961dfb54cb2ad0ce32a4118eed13c438a935");
        bytes32 epochInfo3 = vm.load(address(consensusRegistry), epochInfo3Slot);
        console2.logBytes32(epochInfo3);
        assertEq(address(uint160(uint256(epochInfo3))), address(0x0));

        /**
        *
        *   futureEpochInfo
        *
        */

        bytes32 futureEpochInfoBaseSlot = 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23109;
        
        // all futureEpochInfo base slots store `length == 0`
        for (uint256 i; i < 4; ++i) {
            bytes32 futureEpochInfoCommitteeLen = vm.load(address(consensusRegistry), futureEpochInfoBaseSlot + i);
            console2.logString("futureEpochInfo[i].committee.length");
            console2.logBytes32(futureEpochInfoCommitteeLen);
            assertEq(uint256(futureepochInfo0Len), 0);
        }

        
        for (uint256 i; i < 4; ++i) {
            bytes32 futureEpochInfoSlot = keccak256(abi.encode(uint256(futureEpochInfoBaseSlot) + i));
            console2.logString("slot :");
            console2.logBytes32(futureEpochInfoSlot);
            bytes32 futureEpochInfo = vm.load(address(consensusRegistry), futureEpochInfoSlot);
            console2.logString("value :");
            console2.logBytes32(futureEpochInfo);
            assertEq(address(uint160(uint256(futureEpochInfo))), address(0x0));
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
        assertEq(uint256(validatorsLen), 2); // current len for 1 undefined and 1 active validator

        // keccak256(abi.encode(validatorsBaseSlot))
        bytes32 validatorsSlot = 0x8127b3d06d1bc4fc33994fe62c6bb5ac3963bb2d1bcb96f34a40e1bdc5624a27;

        ValidatorInfo storage undefinedValidator;
        assembly {
            undefinedValidator.slot := validatorsSlot
        }

        bytes32 validatorsSlotActual = 0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2B;
        // to skip undefined validator, iterate starting at 1 to match validator index, terminate at `initialValidators.length + 1`
        for (uint256 i = 1; i <= initialValidators.length + 1; ++i) {
            // ValidatorInfo occupies 4 base slots (blsPubkeyLen, ed25519Pubkey, packed(ecdsaPubkey, activation, exit, index, unused), currentStatus)
            uint256 offset = i * 4;
            bytes32 currentSlot = bytes32(uint256(validatorsSlotActual) + offset);
            ValidatorInfo storage currentInitialValidator;
            assembly {
                currentInitialValidator.slot := currentSlot
            }
            
            assertEq(currentInitialValidator.blsPubkey.length, 96);
            assertEq(currentInitialValidator.ed25519Pubkey, ed25519Pubkey);
            assertEq(currentInitialValidator.ecdsaPubkey, initialValidators[i - 1].ecdsaPubkey);
            assertEq(currentInitialValidator.activationEpoch, 0);
            assertEq(currentInitialValidator.exitEpoch, 0);
            assertEq(currentInitialValidator.validatorIndex, i);
            assertEq(currentInitialValidator.unused, bytes4(0x0));
            assertEq(currentInitialValidator.currentStatus, ValidatorStatus.Active);
        }
    }


    // Test for successful staking
    function test_stake() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // Check event emission
        uint32 activationEpoch = uint32(2);
        uint16 expectedIndex = uint16(2);
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.ValidatorPendingActivation(
            IConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator1,
                activationEpoch,
                uint32(0),
                expectedIndex,
                bytes4(0),
                IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator1);
        assertEq(validators[0].blsPubkey, blsPubkey);
        assertEq(validators[0].ed25519Pubkey, ed25519Pubkey);
        assertEq(validators[0].activationEpoch, activationEpoch);
        assertEq(validators[0].exitEpoch, uint32(0));
        assertEq(validators[0].unused, bytes4(0));
        assertEq(validators[0].validatorIndex, expectedIndex);
        assertEq(uint8(validators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingActivation));

        // Finalize epoch twice to reach validator1 activationEpoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        // use 2 member array for committee now that there are 2 active
        consensusRegistry.finalizePreviousEpoch(new address[](2), new StakeInfo[](0));
        vm.stopPrank();

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory activeValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Active);
        assertEq(activeValidators.length, 2);
        assertEq(activeValidators[0].ecdsaPubkey, validator0);
        assertEq(activeValidators[1].ecdsaPubkey, validator1);
        assertEq(uint8(activeValidators[1].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Active));
    }

    function testRevert_stake_inblsPubkeyLength() public {
        vm.prank(validator1);
        vm.expectRevert(IConsensusRegistry.InvalidBLSPubkey.selector);
        consensusRegistry.stake{ value: stakeAmount }("", blsSig, ed25519Pubkey);
    }

    function testRevert_stake_invalidBlsSigLength() public {
        vm.prank(validator1);
        vm.expectRevert(IConsensusRegistry.InvalidProof.selector);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, "", ed25519Pubkey);
    }

    // Test for incorrect stake amount
    function testRevert_stake_invalidStakeAmount() public {
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(IStakeManager.InvalidStakeAmount.selector, 0));
        consensusRegistry.stake{ value: 0 }(blsPubkey, blsSig, ed25519Pubkey);
    }

    function test_exit() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to twice reach activation epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](2), new StakeInfo[](0));
        vm.stopPrank();

        // Check event emission
        uint32 activationEpoch = uint32(2);
        uint32 exitEpoch = uint32(4);
        uint16 expectedIndex = 2;
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.ValidatorPendingExit(
            IConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator1,
                activationEpoch,
                exitEpoch,
                expectedIndex,
                bytes4(0),
                IConsensusRegistry.ValidatorStatus.PendingExit
            )
        );
        // Exit
        vm.prank(validator1);
        consensusRegistry.exit();

        // Check validator information is pending exit
        IConsensusRegistry.ValidatorInfo[] memory pendingExitValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingExit));

        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        vm.stopPrank();

        // Check validator information is exited
        IConsensusRegistry.ValidatorInfo[] memory exitValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Exited);
        assertEq(exitValidators.length, 1);
        assertEq(exitValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(exitValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Exited));
    }

    function test_exit_rejoin() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to twice reach activation epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](2), new StakeInfo[](0));
        vm.stopPrank();

        // Exit
        vm.prank(validator1);
        consensusRegistry.exit();

        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        vm.stopPrank();

        // Check event emission
        uint32 newActivationEpoch = consensusRegistry.getCurrentEpoch() + 2;
        uint32 exitEpoch = uint32(4);
        uint16 expectedIndex = 2;
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.ValidatorPendingActivation(
            IConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator1,
                newActivationEpoch,
                exitEpoch,
                expectedIndex,
                bytes4(0),
                IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        // Re-stake after exit
        vm.prank(validator1);
        consensusRegistry.rejoin(blsPubkey, ed25519Pubkey);

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator1);
        assertEq(uint8(validators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingActivation));
    }

    // Test for exit by a non-validator
    function testRevert_exit_nonValidator() public {
        address nonValidator = address(0x3);

        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(IConsensusRegistry.NotValidator.selector, nonValidator));
        consensusRegistry.exit();
    }

    // Test for exit by a validator who is not active
    function testRevert_exit_notActive() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Attempt to exit without being active
        vm.prank(validator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConsensusRegistry.InvalidStatus.selector, IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        consensusRegistry.exit();
    }

    function test_unstake() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to process stake
        vm.prank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));

        // Finalize epoch again to reach validator1 activationEpoch
        vm.prank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](2), new StakeInfo[](0));

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Active);
        assertEq(validators.length, 2);
        assertEq(validators[0].ecdsaPubkey, validator0);
        assertEq(validators[1].ecdsaPubkey, validator1);
        assertEq(uint8(validators[1].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Active));

        // Exit
        vm.prank(validator1);
        consensusRegistry.exit();

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory pendingExitValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingExit));

        // Finalize epoch twice to process exit
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        vm.stopPrank();

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory exitedValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Exited);
        assertEq(exitedValidators.length, 1);
        assertEq(exitedValidators[0].ecdsaPubkey, validator1);
        assertEq(uint8(exitedValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Exited));

        // Capture pre-exit balance
        uint256 initialBalance = validator1.balance;

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.RewardsClaimed(validator1, stakeAmount);
        // Unstake
        vm.prank(validator1);
        consensusRegistry.unstake();

        // Check balance after unstake
        uint256 finalBalance = validator1.balance;
        assertEq(finalBalance, initialBalance + stakeAmount);
    }

    // Test for unstake by a non-validator
    function testRevert_unstake_nonValidator() public {
        address nonValidator = address(0x3);

        vm.prank(owner);
        consensusRegistry.mint(nonValidator);

        vm.prank(nonValidator);
        vm.expectRevert();
        consensusRegistry.unstake();
    }

    // Test for unstake by a validator who has not exited
    function testRevert_unstake_notExited() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Attempt to unstake without exiting
        vm.prank(validator1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConsensusRegistry.InvalidStatus.selector, IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        consensusRegistry.unstake();
    }

    // Test for successful claim of staking rewards
    function testFuzz_claimStakeRewards(uint240 fuzzedRewards) public {
        fuzzedRewards = uint240(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Capture initial rewards info
        uint256 initialRewards = consensusRegistry.getRewards(validator1);

        // Finalize epoch twice to reach validator1 activationEpoch
        vm.startPrank(sysAddress);
        (, uint256 numActiveValidators) = consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        // use 2 member array for committee now that there are 2 active
        consensusRegistry.finalizePreviousEpoch(new address[](numActiveValidators + 1), new StakeInfo[](0));

        // Simulate earning rewards by finalizing an epoch with a `StakeInfo` for validator1
        uint16 validator1Index = 2;
        StakeInfo[] memory validator1Rewards = new StakeInfo[](1);
        validator1Rewards[0] = StakeInfo(validator1Index, fuzzedRewards);
        consensusRegistry.finalizePreviousEpoch(new address[](2), validator1Rewards);
        vm.stopPrank();

        // Check rewards were incremented
        uint256 updatedRewards = consensusRegistry.getRewards(validator1);
        assertEq(updatedRewards, initialRewards + fuzzedRewards);

        // Capture initial validator balance
        uint256 initialBalance = validator1.balance;

        // Check event emission and claim rewards
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.RewardsClaimed(validator1, fuzzedRewards);
        vm.prank(validator1);
        consensusRegistry.claimStakeRewards();

        // Check balance after claiming
        uint256 updatedBalance = validator1.balance;
        assertEq(updatedBalance, initialBalance + fuzzedRewards);
    }

    // Test for claim by a non-validator
    function testRevert_claimStakeRewards_nonValidator() public {
        address nonValidator = address(0x3);
        vm.deal(nonValidator, 10 ether);

        vm.prank(nonValidator);
        vm.expectRevert(abi.encodeWithSelector(IConsensusRegistry.NotValidator.selector, nonValidator));
        consensusRegistry.claimStakeRewards();
    }

    // Test for claim by a validator with insufficient rewards
    function testRevert_claimStakeRewards_insufficientRewards() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // First stake
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch twice to reach validator1 activationEpoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        // use 2 member array for committee now that there are 2 active
        consensusRegistry.finalizePreviousEpoch(new address[](2), new StakeInfo[](0));

        // earn too little rewards for withdrawal
        uint240 notEnoughRewards = uint240(minWithdrawAmount - 1);
        uint16 validator1Index = 2;
        StakeInfo[] memory validator1Rewards = new StakeInfo[](1);
        validator1Rewards[0] = StakeInfo(validator1Index, notEnoughRewards);
        consensusRegistry.finalizePreviousEpoch(new address[](2), validator1Rewards);
        vm.stopPrank();

        // Attempt to claim rewards
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(IStakeManager.InsufficientRewards.selector, notEnoughRewards));
        consensusRegistry.claimStakeRewards();
    }

    function test_finalizePreviousEpoch_updatesEpochInfo() public {
        // Initialize test data
        address[] memory newCommittee = new address[](1);
        newCommittee[0] = address(0x69);

        uint32 initialEpoch = consensusRegistry.getCurrentEpoch();
        assertEq(initialEpoch, 0);

        // Call the function
        vm.prank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(newCommittee, new StakeInfo[](0));

        // Fetch current epoch and verify it has incremented
        uint32 currentEpoch = consensusRegistry.getCurrentEpoch();
        assertEq(currentEpoch, initialEpoch + 1);

        // Verify new epoch information
        IConsensusRegistry.EpochInfo memory epochInfo = consensusRegistry.getEpochInfo(currentEpoch);
        assertEq(epochInfo.blockHeight, block.number);
        for (uint256 i; i < epochInfo.committee.length; ++i) {
            assertEq(epochInfo.committee[i], newCommittee[i]);
        }
    }

    function test_finalizePreviousEpoch_activatesValidators() public {
        vm.prank(owner);
        consensusRegistry.mint(validator1);

        // enter validator in PendingActivation state
        vm.prank(validator1);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, new bytes(96), ed25519Pubkey);

        // Fast forward epochs to reach activatino epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](2), new StakeInfo[](0));
        vm.stopPrank();

        // check validator1 activated
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Active);
        assertEq(validators.length, 2);
        assertEq(validators[0].ecdsaPubkey, validator0);
        assertEq(validators[1].ecdsaPubkey, validator1);
        uint16 returnedIndex = consensusRegistry.getValidatorIndex(validator1);
        assertEq(returnedIndex, 2);
        IConsensusRegistry.ValidatorInfo memory returnedVal = consensusRegistry.getValidatorByIndex(returnedIndex);
        assertEq(returnedVal.ecdsaPubkey, validator1);
    }

    function testFuzz_finalizePreviousEpoch(uint16 numValidators, uint240 fuzzedRewards) public {
        numValidators = uint16(bound(uint256(numValidators), 4, 8000)); // fuzz up to 8k validators
        fuzzedRewards = uint240(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        // exit existing validator0 which was activated in constructor to clean up calculations
        vm.prank(validator0);
        consensusRegistry.exit();
        // Finalize epoch once to reach `PendingExit` for `validator0`
        vm.prank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));

        numValidators = 2000;
        fuzzedRewards = uint240(minWithdrawAmount);

        // activate validators using `stake()` and construct `newCommittee` array as pseudorandom subset (1/3) of all
        // validators
        uint256 committeeSize = uint256(numValidators) * 10_000 / 3 / 10_000 + 1; // address precision loss
        address[] memory newCommittee = new address[](committeeSize);
        uint256 committeeCounter;
        for (uint256 i; i < numValidators; ++i) {
            // create random new validator keys
            bytes memory newBLSPubkey = _createRandomBlsPubkey(i);
            bytes memory newBLSSig = _createRandomBlsSig(i);
            bytes32 newED25519Pubkey = _createRandomED25519Pubkey(i);
            address newValidator = address(uint160(uint256(keccak256(abi.encode(i)))));

            // deal `stakeAmount` funds and prank governance NFT mint to `newValidator`
            vm.deal(newValidator, stakeAmount);
            vm.prank(owner);
            consensusRegistry.mint(newValidator);

            vm.prank(newValidator);
            consensusRegistry.stake{ value: stakeAmount }(newBLSPubkey, newBLSSig, newED25519Pubkey);

            // assert initial rewards info is 0
            uint256 initialRewards = consensusRegistry.getRewards(newValidator);
            assertEq(initialRewards, 0);

            // conditionally push validator address to array (deterministic but random enough for tests)
            if (uint256(keccak256(abi.encode(i))) % 2 == 0) {
                // if the `newCommittee` array has been populated, continue
                if (committeeCounter == newCommittee.length) continue;

                newCommittee[committeeCounter] = newValidator;
                committeeCounter++;
            }
        }

        // Finalize epoch twice to reach activationEpoch for validators entered in the `stake()` loop
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](1), new StakeInfo[](0));
        // use 2 member array for committee now that there are 2 active
        consensusRegistry.finalizePreviousEpoch(newCommittee, new StakeInfo[](0));

        uint256 numRecipients = newCommittee.length; // all committee members receive rewards
        uint240 rewardPerValidator = uint240(fuzzedRewards / numRecipients);
        // construct `committeeRewards` array to compensate voting committee equally (total `fuzzedRewards` divided
        // across committee)
        StakeInfo[] memory committeeRewards = new StakeInfo[](numRecipients);
        for (uint256 i; i < newCommittee.length; ++i) {
            uint16 recipientIndex = consensusRegistry.getValidatorIndex(newCommittee[i]);
            committeeRewards[i] = StakeInfo(recipientIndex, rewardPerValidator);
        }

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.NewEpoch(IConsensusRegistry.EpochInfo(newCommittee, uint64(block.number)));
        // increment rewards by finalizing an epoch with a `StakeInfo` for constructed committee (new committee not
        // relevant)
        consensusRegistry.finalizePreviousEpoch(newCommittee, committeeRewards);
        vm.stopPrank();

        // Check rewards were incremented for each committee member
        for (uint256 i; i < newCommittee.length; ++i) {
            uint16 index = consensusRegistry.getValidatorIndex(newCommittee[i]);
            address committeeMember = consensusRegistry.getValidatorByIndex(index).ecdsaPubkey;
            uint256 updatedRewards = consensusRegistry.getRewards(committeeMember);
            assertEq(updatedRewards, rewardPerValidator);
        }
    }

    // Attempt to call without sysAddress should revert
    function testRevert_finalizePreviousEpoch_OnlySystemCall() public {
        vm.expectRevert(abi.encodeWithSelector(SystemCallable.OnlySystemCall.selector, address(this)));
        consensusRegistry.finalizePreviousEpoch(new address[](0), new StakeInfo[](0));
    }

    function _createRandomBlsPubkey(uint256 seed) internal pure returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, bytes16(keccak256(abi.encode(seedHash))));
    }

    function _createRandomBlsSig(uint256 seed) internal pure returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, keccak256(abi.encode(seedHash)), bytes32(0));
    }

    function _createRandomED25519Pubkey(uint256 seed) internal pure returns (bytes32) {
        return keccak256(abi.encode(seed));
    }
}
