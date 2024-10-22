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
    address public validator1 = address(0xbababee);
    address public validator2 = address(0xbabababeee);
    address public validator3 = address(0xbababababeeee);
    address public validator4 = address(0xbabababababeeeee);

    IConsensusRegistry.ValidatorInfo validatorInfo0;
    IConsensusRegistry.ValidatorInfo validatorInfo1;
    IConsensusRegistry.ValidatorInfo validatorInfo2;
    IConsensusRegistry.ValidatorInfo validatorInfo3;

    IConsensusRegistry.ValidatorInfo[] initialValidators; // contains validatorInfo0-3

    address public sysAddress;

    bytes public blsPubkey =
        hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
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
        bytes memory validator0BLSKey = _createRandomBlsPubkey(0);
        bytes32 validator0ED25519Key = keccak256(abi.encode(0));
        validatorInfo0 = IConsensusRegistry.ValidatorInfo(
            validator0BLSKey,
            validator0ED25519Key,
            validator0,
            uint32(0),
            uint32(0),
            uint24(1),
            IConsensusRegistry.ValidatorStatus.Active
        );
        validatorInfo1 = IConsensusRegistry.ValidatorInfo(
            _createRandomBlsPubkey(1),
            keccak256(abi.encode(1)),
            validator1,
            uint32(0),
            uint32(0),
            uint24(2),
            IConsensusRegistry.ValidatorStatus.Active
        );
        validatorInfo2 = IConsensusRegistry.ValidatorInfo(
            _createRandomBlsPubkey(2),
            keccak256(abi.encode(2)),
            validator2,
            uint32(0),
            uint32(0),
            uint24(3),
            IConsensusRegistry.ValidatorStatus.Active
        );
        validatorInfo3 = IConsensusRegistry.ValidatorInfo(
            _createRandomBlsPubkey(3),
            keccak256(abi.encode(3)),
            validator3,
            uint32(0),
            uint32(0),
            uint24(4),
            IConsensusRegistry.ValidatorStatus.Active
        );
        initialValidators.push(validatorInfo0);
        initialValidators.push(validatorInfo1);
        initialValidators.push(validatorInfo2);
        initialValidators.push(validatorInfo3);

        consensusRegistryImpl = new ConsensusRegistry();
        consensusRegistry = ConsensusRegistry(payable(address(new ERC1967Proxy(address(consensusRegistryImpl), ""))));
        consensusRegistry.initialize(address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, owner);

        /// @dev debugging
        // bytes memory init = abi.encodeWithSelector(ConsensusRegistry.initialize.selector, address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, owner);
        // bytes memory alloySolCalldata = bytes(hex'61af9e690000000000000000000000002b8fff9ddbebada8c44e26481ed20f0d33abddf300000000000000000000000000000000000000000000d3c21bcecceda000000000000000000000000000000000000000000000000000021e19e0c9bab240000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000d0309dc1d4d74b508453f2769bde804a7132048b0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000004a000000000000000000000000000000000000000000000000000000000000000e05c2cf00a87454e353040cda6b13f89384d79a32ce28bd4ca31bcf49c507f08bb000000000000000000000000adc6bead9c9851ace029757ebc709a6712c6a3a40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000006097f8ce9fd7dd08e9b1bc2438edc740f1163ebac9d7e771a2e00a77b80e1858a9b5d6f9f9255271f30ff34854bebcc72a196e110c806a5fc3ff23b574c6e9e0f8e3e70e7e2c66e0e3cd9183ab49c148483d219197b7843c047483774e5341e7a600000000000000000000000000000000000000000000000000000000000000e030710b15d2bd43974866f4a7a008ac55c4ffcd5258d5fdca3cedc9dd7485732700000000000000000000000027c5c95c755b0e4f7f1d1807ed22d3b8e6e522ad00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000060814b4be81553a9acc708ffe1368175ea90a5547651f13100195a97160c96d209aaa4bc6b4754df0cb7510a74b0f9d55e0f252c9038491c7c8ed770425f76df580eba52ccb03da82611b617fdac5c288dcc341cec907bb5c757151c6d6878155a00000000000000000000000000000000000000000000000000000000000000e0bf85176cc0f677942d2ffc5c97a060dac6467ed075f2da36094e6b551d4faea7000000000000000000000000c9b8899b3725fc07df5e4b0fc3c030136e77b854000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000608d2822eccbfeb03de2501f6fd71b7af3e62b78a5fcf80305421c05967761398ae88a02796361574c7dc97a04811af694178663a9be9229e2f8a6c104ecd6fb663c04abec8eb58c4c6d212b9eec7242fcbf17ea28f77b5e7431a5f2305cc4831e00000000000000000000000000000000000000000000000000000000000000e0c7d972d946c2c19e5f034b878e9bffdaaa97349d27b60f9333ac0c4ff36fe30b000000000000000000000000b890150dca0e49cf380bafbca93c6753e0133f7a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000006090553e55328b315077ce36d7fe5487454bf145aa7c18b709e11ad24d723e26b20f8d97bf3cbc78d1d3862e9db6611d850450792eb00a316ddb21a153c69b76a21b2924f1cc4dfe102492cd1474e288365dd7ff1bb7915481cc69deaa4b5278f6');
        // address(consensusRegistry).call(alloySolCalldata);
        // console.logBytes(init);

        sysAddress = consensusRegistry.SYSTEM_ADDRESS();

        vm.deal(validator4, 100_000_000 ether);

        // deploy an RWTEL module and then use its bytecode to etch on a fixed address (use create2 in prod)
        RWTEL tmp =
            new RWTEL(address(consensusRegistry), address(0xbeef), "test", "TEST", 0, address(0x0), address(0x0), 0);
        vm.etch(address(rwTEL), address(tmp).code);
        // deal RWTEL max TEL supply to test reward distribution
        vm.deal(address(rwTEL), telMaxSupply);
    }

/* The following slots must be set at genesis, simulated in `test_setUp()` here using `initialize()`
0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC : `implementation`
0xF0C57E16840DF040F15088DC2F81FE391C3923BEC73E23A9662EFC9C229C6A00 : `_initialized == uint64(1)`
0x9016D09D72D40FDAE2FD8CEAC6B6234C7706214FD39C1CD1E609A0528C199300 : `owner == 0xc0ffee`
0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079300 : `shortString("ConsensusNFT", length * 2) == 0x436F6E73656E7375734E46540000000000000000000000000000000000000018`
0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079301 : `shortString("CNFT", length * 2) == 0x434E465400000000000000000000000000000000000000000000000000000008`
0xBDB57EBF9F236E21A27420ACA53E57B3F4D9C46B35290CA11821E608CDAB5F19 : `keccak256(abi.encodePacked(validator0, _owners.slot)) == _owners[validator0] (== validator0)`
0x89DC4F27410B0F3ACC713877BE759A601621941908FBC40B97C5004C02763CF8 : `keccak256(abi.encodePacked(validator0, _balances.slot)) == _balances[validator0] (== 1)`
0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7400 : `rwTEL == 0x7e1`
0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7401 : `stakeAmount == 1000000000000000000000000`
0x0636E6890FEC58B60F710B53EFA0EF8DE81CA2FDDCE7E46303A60C9D416C7402 : `minWithdrawAmount == 10000000000000000000000`
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
0x8127b3d06d1bc4fc33994fe62c6bb5ac3963bb2d1bcb96f34a40e1bdc5624a27-9 : `validators[0]` (undefined)
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2A : `validators[1].blsPubkey.length == validator0.blsPubkey.length * 2 + 1 ( == 193)`
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2B : `validators[1].ed25519Pubkey == 0x011201DEED66C3B3A1B2AFB246B1436FD291A5F4B65E4FF0094A013CD922F803`
0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2C : `validators[1].packed(currentStatus.validatorIndex.exitEpoch.activationEpoch.ecdsaPubkey) == 20000010000000000000000000000000000000000000000000000000000BABE`
0xF693A3577F5F3699D01F01F396D12A401509191AB0370286D497942A2F24F271-3 : `validators[1].blsPubkey` (96 bytes, 3 words)
0xF72EACDC698A36CB279844370E2C8C845481AD672FF1E7EFFA7264BE6D6A9FD2 : `keccak256(abi.encodePacked(validator0, stakeInfo.slot)) == validatorIndex(1)`
0x52B83978E270FCD9AF6931F8A7E99A1B79DC8A7AEA355D6241834B19E0A0EC39 : `keccak256(epochInfoBaseSlot) => epochInfos[0].committee` `validator0 == 0xBABE`
0x96A201C8A417846842C79BE2CD1E33440471871A6CF94B34C8F286AAEB24AD6B : `keccak256(epochInfoBaseSlot + 2) => epochInfos[1].committee` `[validator0] == [0xBABE]`
0x14D1F3AD8599CD8151592DDEADE449F790ADD4D7065A031FBE8F7DBB1833E0A9 : `keccak256(epochInfoBaseSlot + 4) => epochInfos[2].committee` `[validator0] == [0xBABE]`
0x79af749cb95fe9cb496550259d0d961dfb54cb2ad0ce32a4118eed13c438a935 : `keccak256(epochInfoBaseSlot + 6) => epochInfos[3].committee` `not set == [address(0x0)]`
*/
    function test_setUp() public view {
        bytes32 ownerSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        bytes32 ownerWord = vm.load(address(consensusRegistry), ownerSlot);
        console2.logString("OwnableUpgradeable slot0");
        console2.logBytes32(ownerWord);
        assertEq(address(uint160(uint256(ownerWord))), owner);

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
        assertEq(address(uint160(uint256(returnedOwner))), validator0);

        bytes32 _balancesSlot = 0x80bb2b638cc20bc4d0a60d66940f3ab4a00c1d7b313497ca82fb0b4ab0079303;
        // 0x89DC4F27410B0F3ACC713877BE759A601621941908FBC40B97C5004C02763CF8
        bytes32 validator0BalancesSlot = keccak256(abi.encodePacked(uint256(uint160(validator0)), _balancesSlot));
        bytes32 returnedBalance = vm.load(address(consensusRegistry), validator0BalancesSlot);
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
        bytes32 stakeInfoValidator0Slot = keccak256(abi.encodePacked(uint256(uint160(validator0)), stakeInfoSlot));
        bytes32 returnedStakeInfoIndex = vm.load(address(consensusRegistry), stakeInfoValidator0Slot);
        assertEq(returnedStakeInfoIndex, bytes32(uint256(uint24(1)))); // validator0's index == 1


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
        console2.logString("epochInfo[0].committee == slot 0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39");
        bytes32 epochInfo0 = vm.load(address(consensusRegistry), epochInfo0Slot);
        console2.logBytes32(epochInfo0);
        assertEq(address(uint160(uint256(epochInfo0))), validator0);

        // epochInfo[1]
        bytes32 epochInfo1Len = vm.load(address(consensusRegistry), bytes32(uint256(epochInfoBaseSlot) + 2));
        // blockHeight, ie slot2, is not known at genesis 
        console2.logString("ConsensusRegistry slot3 : epochInfo[1].committee.length");
        console2.logBytes32(epochInfo1Len);
        assertEq(uint256(epochInfo1Len), 4); // current len for 4 initial validators in committee

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
        assertEq(uint256(epochInfo2Len), 4); // current len for 4 initial validators in committee

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
            bytes32 futureEpochInfoCommitteeLen = vm.load(address(consensusRegistry), bytes32(uint256(futureEpochInfoBaseSlot) + i));
            console2.logString("futureEpochInfo[i].committee.length");
            console2.logBytes32(futureEpochInfoCommitteeLen);
            assertEq(uint256(futureEpochInfoCommitteeLen), 0);
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
        assertEq(uint256(validatorsLen), 5); // current len for 1 undefined and 4 active validators

        // keccak256(abi.encode(validatorsBaseSlot))
        bytes32 validatorsSlot = 0x8127b3d06d1bc4fc33994fe62c6bb5ac3963bb2d1bcb96f34a40e1bdc5624a27;
        
        // first 3 slots belong to the undefined validator
        for (uint256 i; i < 3; ++i) {
            bytes32 emptySlot = vm.load(address(consensusRegistry), bytes32(uint256(validatorsSlot) + i));
            assertEq(emptySlot, bytes32(0x0));
        }
        
        // ValidatorInfo occupies 3 base slots (blsPubkeyLen, ed25519Pubkey, packed(ecdsaPubkey, activation, exit, index, currentStatus))
        bytes32 firstValidatorSlot = 0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2A;        

        // check BLS pubkey
        bytes32 returnedBLSPubkeyLen = vm.load(address(consensusRegistry), firstValidatorSlot);
        /// @notice For byte arrays that store data.length >= 32, the main slot stores `length * 2 + 1` (content is stored as usual in keccak256(slot))
        assertEq(returnedBLSPubkeyLen, bytes32(uint256(0xc1))); // `0xc1 == blsPubkey.length * 2 + 1`
        
        /// @notice this only checks against `validator0` - must change to test multiple initial validators 
        bytes memory blsKey = validatorInfo0.blsPubkey;
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

        bytes32 returnedBLSPubkeyA = vm.load(address(consensusRegistry), keccak256(abi.encode(firstValidatorSlot)));
        assertEq(returnedBLSPubkeyA, blsPubkeyPartA);
        bytes32 returnedBLSPubkeyB = vm.load(address(consensusRegistry), bytes32(uint256(keccak256(abi.encode(firstValidatorSlot))) + 1));
        assertEq(returnedBLSPubkeyB, blsPubkeyPartB);
        bytes32 returnedBLSPubkeyC = vm.load(address(consensusRegistry), bytes32(uint256(keccak256(abi.encode(firstValidatorSlot))) + 2));
        assertEq(returnedBLSPubkeyC, blsPubkeyPartC);

        // check ED25519 pubkey
        bytes32 returnedED25519Pubkey = vm.load(address(consensusRegistry), bytes32(uint256(firstValidatorSlot) + 1));
        assertEq(returnedED25519Pubkey, validatorInfo0.ed25519Pubkey);

        // check packed slot
        /// @notice `ValidatorInfo.ecdsaPubkey == validator0` only for `validator0`; this test should be updated if launching with > 1 validator at genesis 
        bytes32 expectedPackedValues = bytes32(abi.encodePacked(IConsensusRegistry.ValidatorStatus.Active, uint24(1), uint32(0), uint32(0), validator0));
        bytes32 returnedPackedValues = vm.load(address(consensusRegistry), bytes32(uint256(firstValidatorSlot) + 2));
        assertEq(expectedPackedValues, returnedPackedValues);
    }


    // Test for successful staking
    function test_stake() public {
        vm.prank(owner);
        consensusRegistry.mint(validator4);

        // Check event emission
        uint32 activationEpoch = uint32(2);
        uint24 expectedIndex = uint24(5);
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.ValidatorPendingActivation(
            IConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator4,
                activationEpoch,
                uint32(0),
                expectedIndex,
                IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator4);
        assertEq(validators[0].blsPubkey, blsPubkey);
        assertEq(validators[0].ed25519Pubkey, ed25519Pubkey);
        assertEq(validators[0].activationEpoch, activationEpoch);
        assertEq(validators[0].exitEpoch, uint32(0));
        assertEq(validators[0].validatorIndex, expectedIndex);
        assertEq(uint8(validators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingActivation));

        // Finalize epoch twice to reach validator4 activationEpoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory activeValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Active);
        assertEq(activeValidators.length, 5);
        assertEq(activeValidators[0].ecdsaPubkey, validator0);
        assertEq(activeValidators[1].ecdsaPubkey, validator1);
        assertEq(activeValidators[2].ecdsaPubkey, validator2);
        assertEq(activeValidators[3].ecdsaPubkey, validator3);
        assertEq(activeValidators[4].ecdsaPubkey, validator4);
        assertEq(uint8(activeValidators[1].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Active));
    }

    function testRevert_stake_invalidblsPubkeyLength() public {
        vm.prank(validator4);
        vm.expectRevert(IConsensusRegistry.InvalidBLSPubkey.selector);
        consensusRegistry.stake{ value: stakeAmount }("", blsSig, ed25519Pubkey);
    }

    function testRevert_stake_invalidBlsSigLength() public {
        vm.prank(validator4);
        vm.expectRevert(IConsensusRegistry.InvalidProof.selector);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, "", ed25519Pubkey);
    }

    // Test for incorrect stake amount
    function testRevert_stake_invalidStakeAmount() public {
        vm.prank(validator4);
        vm.expectRevert(abi.encodeWithSelector(IStakeManager.InvalidStakeAmount.selector, 0));
        consensusRegistry.stake{ value: 0 }(blsPubkey, blsSig, ed25519Pubkey);
    }

    function test_exit() public {
        vm.prank(owner);
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to twice reach activation epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // Check event emission
        uint32 activationEpoch = uint32(2);
        uint32 exitEpoch = uint32(4);
        uint24 expectedIndex = 5;
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.ValidatorPendingExit(
            IConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator4,
                activationEpoch,
                exitEpoch,
                expectedIndex,
                IConsensusRegistry.ValidatorStatus.PendingExit
            )
        );
        // Exit
        vm.prank(validator4);
        consensusRegistry.exit();

        // Check validator information is pending exit
        IConsensusRegistry.ValidatorInfo[] memory pendingExitValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator4);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingExit));

        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // Check validator information is exited
        IConsensusRegistry.ValidatorInfo[] memory exitValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Exited);
        assertEq(exitValidators.length, 1);
        assertEq(exitValidators[0].ecdsaPubkey, validator4);
        assertEq(uint8(exitValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Exited));
    }

    function test_exit_rejoin() public {
        vm.prank(owner);
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to twice reach activation epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // Exit
        vm.prank(validator4);
        consensusRegistry.exit();

        // Finalize epoch twice to reach exit epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // Check event emission
        uint32 newActivationEpoch = consensusRegistry.getCurrentEpoch() + 2;
        uint32 exitEpoch = uint32(4);
        uint24 expectedIndex = 5;
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.ValidatorPendingActivation(
            IConsensusRegistry.ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                validator4,
                newActivationEpoch,
                exitEpoch,
                expectedIndex,
                IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        // Re-stake after exit
        vm.prank(validator4);
        consensusRegistry.rejoin(blsPubkey, ed25519Pubkey);

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingActivation);
        assertEq(validators.length, 1);
        assertEq(validators[0].ecdsaPubkey, validator4);
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
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Attempt to exit without being active
        vm.prank(validator4);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConsensusRegistry.InvalidStatus.selector, IConsensusRegistry.ValidatorStatus.PendingActivation
            )
        );
        consensusRegistry.exit();
    }

    function test_unstake() public {
        vm.prank(owner);
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch to process stake
        vm.prank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));

        // Finalize epoch again to reach validator4 activationEpoch
        vm.prank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Active);
        assertEq(validators.length, 5);
        assertEq(validators[0].ecdsaPubkey, validator0);
        assertEq(validators[1].ecdsaPubkey, validator1);
        assertEq(validators[2].ecdsaPubkey, validator2);
        assertEq(validators[3].ecdsaPubkey, validator3);
        assertEq(validators[4].ecdsaPubkey, validator4);
        assertEq(uint8(validators[1].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Active));

        // Exit
        vm.prank(validator4);
        consensusRegistry.exit();

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory pendingExitValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.PendingExit);
        assertEq(pendingExitValidators.length, 1);
        assertEq(pendingExitValidators[0].ecdsaPubkey, validator4);
        assertEq(uint8(pendingExitValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.PendingExit));

        // Finalize epoch twice to process exit
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // Check validator information
        IConsensusRegistry.ValidatorInfo[] memory exitedValidators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Exited);
        assertEq(exitedValidators.length, 1);
        assertEq(exitedValidators[0].ecdsaPubkey, validator4);
        assertEq(uint8(exitedValidators[0].currentStatus), uint8(IConsensusRegistry.ValidatorStatus.Exited));

        // Capture pre-exit balance
        uint256 initialBalance = validator4.balance;

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.RewardsClaimed(validator4, stakeAmount);
        // Unstake
        vm.prank(validator4);
        consensusRegistry.unstake();

        // Check balance after unstake
        uint256 finalBalance = validator4.balance;
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
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Attempt to unstake without exiting
        vm.prank(validator4);
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
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Capture initial rewards info
        uint256 initialRewards = consensusRegistry.getRewards(validator4);

        // Finalize epoch twice to reach validator4 activationEpoch
        vm.startPrank(sysAddress);
        (, uint256 numActiveValidators) = consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](numActiveValidators + 1), new StakeInfo[](0));

        // Simulate earning rewards by finalizing an epoch with a `StakeInfo` for validator4
        uint24 validator4Index = 5;
        StakeInfo[] memory validator4Rewards = new StakeInfo[](1);
        validator4Rewards[0] = StakeInfo(validator4Index, fuzzedRewards);
        consensusRegistry.finalizePreviousEpoch(new address[](4), validator4Rewards);
        vm.stopPrank();

        // Check rewards were incremented
        uint256 updatedRewards = consensusRegistry.getRewards(validator4);
        assertEq(updatedRewards, initialRewards + fuzzedRewards);

        // Capture initial validator balance
        uint256 initialBalance = validator4.balance;

        // Check event emission and claim rewards
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.RewardsClaimed(validator4, fuzzedRewards);
        vm.prank(validator4);
        consensusRegistry.claimStakeRewards();

        // Check balance after claiming
        uint256 updatedBalance = validator4.balance;
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
        consensusRegistry.mint(validator4);

        // First stake
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, blsSig, ed25519Pubkey);

        // Finalize epoch twice to reach validator4 activationEpoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));

        // earn too little rewards for withdrawal
        uint240 notEnoughRewards = uint240(minWithdrawAmount - 1);
        uint24 validator4Index = 5;
        StakeInfo[] memory validator4Rewards = new StakeInfo[](1);
        validator4Rewards[0] = StakeInfo(validator4Index, notEnoughRewards);
        consensusRegistry.finalizePreviousEpoch(new address[](4), validator4Rewards);
        vm.stopPrank();

        // Attempt to claim rewards
        vm.prank(validator4);
        vm.expectRevert(abi.encodeWithSelector(IStakeManager.InsufficientRewards.selector, notEnoughRewards));
        consensusRegistry.claimStakeRewards();
    }

    function test_finalizePreviousEpoch_updatesEpochInfo() public {
        // Initialize test data
        address[] memory newCommittee = new address[](4);
        newCommittee[0] = address(0x69);
        newCommittee[0] = address(0x70);
        newCommittee[0] = address(0x71);
        newCommittee[0] = address(0x72);

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
        consensusRegistry.mint(validator4);

        // enter validator in PendingActivation state
        vm.prank(validator4);
        consensusRegistry.stake{ value: stakeAmount }(blsPubkey, new bytes(96), ed25519Pubkey);

        // Fast forward epochs to reach activation epoch
        vm.startPrank(sysAddress);
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
        vm.stopPrank();

        // check validator4 activated
        IConsensusRegistry.ValidatorInfo[] memory validators =
            consensusRegistry.getValidators(IConsensusRegistry.ValidatorStatus.Active);
        assertEq(validators.length, 5);
        assertEq(validators[0].ecdsaPubkey, validator0);
        assertEq(validators[1].ecdsaPubkey, validator1);
        assertEq(validators[2].ecdsaPubkey, validator2);
        assertEq(validators[3].ecdsaPubkey, validator3);
        assertEq(validators[4].ecdsaPubkey, validator4);
        uint24 returnedIndex = consensusRegistry.getValidatorIndex(validator4);
        assertEq(returnedIndex, 5);
        IConsensusRegistry.ValidatorInfo memory returnedVal = consensusRegistry.getValidatorByIndex(returnedIndex);
        assertEq(returnedVal.ecdsaPubkey, validator4);
    }

    function testFuzz_finalizePreviousEpoch(uint24 numValidators, uint240 fuzzedRewards) public {
        numValidators = uint24(bound(uint256(numValidators), 4, 8000)); // fuzz up to 8k validators
        fuzzedRewards = uint240(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        // exit existing validator0 which was activated in constructor to clean up calculations
        vm.prank(validator0);
        consensusRegistry.exit();
        // Finalize epoch once to reach `PendingExit` for `validator0`
        vm.prank(sysAddress);
        // provide `committeeSize == 3` since there are now only 3 active validators
        consensusRegistry.finalizePreviousEpoch(new address[](3), new StakeInfo[](0));

        // to prevent exceeding block gas limit, `mint(newValidator)` is performed in separate loop from `stake()`
        for (uint256 i; i < numValidators; ++i) {
            address newValidator = address(uint160(uint256(keccak256(abi.encode(i)))));

            // deal `stakeAmount` funds and prank governance NFT mint to `newValidator`
            vm.deal(newValidator, stakeAmount);
            vm.prank(owner);
            consensusRegistry.mint(newValidator);
        }

        // activate validators via `stake()` and construct `newCommittee` array as pseudorandom subset (1/3)
        uint256 numActiveValidators = uint256(numValidators) + 4;
        uint256 committeeSize = uint256(numActiveValidators) * 10_000 / 3 / 10_000 + 1; // address precision loss
        address[] memory newCommittee = new address[](committeeSize);
        uint256 committeeCounter;
        for (uint256 i; i < numValidators; ++i) {
            // recreate `newValidator` address minted a ConsensusNFT in previous loop
            address newValidator = address(uint160(uint256(keccak256(abi.encode(i)))));

            // create random new validator keys
            bytes memory newBLSPubkey = _createRandomBlsPubkey(i);
            bytes memory newBLSSig = _createRandomBlsSig(i);
            bytes32 newED25519Pubkey = _createRandomED25519Pubkey(i);


            vm.prank(newValidator);
            consensusRegistry.stake{ value: stakeAmount }(newBLSPubkey, newBLSSig, newED25519Pubkey);

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
        // provide `committeeSize == 3` since there are now only 3 active validators
        consensusRegistry.finalizePreviousEpoch(new address[](3), new StakeInfo[](0));
        consensusRegistry.finalizePreviousEpoch(newCommittee, new StakeInfo[](0));

        uint256 numRecipients = newCommittee.length; // all committee members receive rewards
        uint240 rewardPerValidator = uint240(fuzzedRewards / numRecipients);
        // construct `committeeRewards` array to compensate voting committee equally (total `fuzzedRewards` divided
        // across committee)
        StakeInfo[] memory committeeRewards = new StakeInfo[](numRecipients);
        for (uint256 i; i < newCommittee.length; ++i) {
            uint24 recipientIndex = consensusRegistry.getValidatorIndex(newCommittee[i]);
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
            uint24 index = consensusRegistry.getValidatorIndex(newCommittee[i]);
            address committeeMember = consensusRegistry.getValidatorByIndex(index).ecdsaPubkey;
            uint256 updatedRewards = consensusRegistry.getRewards(committeeMember);
            assertEq(updatedRewards, rewardPerValidator);
        }
    }

    // Attempt to call without sysAddress should revert
    function testRevert_finalizePreviousEpoch_OnlySystemCall() public {
        vm.expectRevert(abi.encodeWithSelector(SystemCallable.OnlySystemCall.selector, address(this)));
        consensusRegistry.finalizePreviousEpoch(new address[](4), new StakeInfo[](0));
    }

    function _createRandomBlsPubkey(uint256 seed) internal pure returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, seedHash, seedHash);
    }

    function _createRandomBlsSig(uint256 seed) internal pure returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, keccak256(abi.encode(seedHash)), bytes32(0));
    }

    function _createRandomED25519Pubkey(uint256 seed) internal pure returns (bytes32) {
        return keccak256(abi.encode(seed));
    }
}
