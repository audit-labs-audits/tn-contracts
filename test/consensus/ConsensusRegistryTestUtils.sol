// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { RWTEL } from "src/RWTEL.sol";

contract ConsensusRegistryTestUtils is ConsensusRegistry, Test {
    ConsensusRegistry public consensusRegistryImpl;
    ConsensusRegistry public consensusRegistry;
    RWTEL public rwTEL;

    address public crOwner = address(0xc0ffee);
    address public validator1 = _createRandomAddress(1);
    address public validator2 = _createRandomAddress(2);
    address public validator3 = _createRandomAddress(3);
    address public validator4 = _createRandomAddress(4);

    ValidatorInfo validatorInfo1;
    ValidatorInfo validatorInfo2;
    ValidatorInfo validatorInfo3;
    ValidatorInfo validatorInfo4;

    ValidatorInfo[] initialValidators; // contains validatorInfo1-4

    address public sysAddress;

    // non-genesis validator for testing
    address public validator5 = _createRandomAddress(5);
    bytes public validator5BlsPubkey = _createRandomBlsPubkey(5);

    uint256 public telMaxSupply = 100_000_000_000 ether;
    uint256 public stakeAmount_ = 1_000_000 ether;
    uint256 public minWithdrawAmount_ = 10_000 ether;
    // `OZ::ERC721Upgradeable::mint()` supports up to ~14_300 fuzzed mint iterations
    uint256 public MAX_MINTABLE = 14_000;

    constructor() {
        // deploy an RWTEL module
        rwTEL = new RWTEL(
            address(0xbabe),
            address(0xdead),
            bytes32(0x0),
            "chain",
            address(0xbeef),
            "test",
            "TEST",
            0,
            address(0x0),
            address(0x0),
            0
        );

        // provide initial validator set as the network will launch with at least four validators
        validatorInfo1 = ValidatorInfo(
            _createRandomBlsPubkey(1), validator1, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        validatorInfo2 = ValidatorInfo(
            _createRandomBlsPubkey(2), validator2, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        validatorInfo3 = ValidatorInfo(
            _createRandomBlsPubkey(3), validator3, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        validatorInfo4 = ValidatorInfo(
            _createRandomBlsPubkey(4), validator4, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        initialValidators.push(validatorInfo1);
        initialValidators.push(validatorInfo2);
        initialValidators.push(validatorInfo3);
        initialValidators.push(validatorInfo4);

        consensusRegistryImpl = new ConsensusRegistry();
    }

    function _createRandomAddress(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed)))));
    }

    function _createRandomBlsPubkey(uint256 seed) internal pure returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, seedHash, seedHash);
    }

    function _fuzz_stake(uint24 numValidators, uint256 amount) internal {
        for (uint256 i; i < numValidators; ++i) {
            // recreate `newValidator` address minted a ConsensusNFT in `setUp()` loop
            uint256 tokenId = i + 5;
            address newValidator = _createRandomAddress(tokenId);

            // create random new validator keys
            bytes memory newBLSPubkey = _createRandomBlsPubkey(tokenId);

            // stake and activate
            vm.deal(newValidator, amount);
            vm.prank(newValidator);
            consensusRegistry.stake{ value: amount }(newBLSPubkey);
        }
    }

    function _fuzz_activate(uint24 numValidators) internal {
        for (uint256 i; i < numValidators; ++i) {
            // recreate `newValidator` address minted a ConsensusNFT in `setUp()` loop
            uint256 tokenId = i + 5;
            address newValidator = _createRandomAddress(tokenId);

            vm.prank(newValidator);
            consensusRegistry.activate();
        }
    }

    function _fuzz_computeCommitteeSize(
        uint256 numActive,
        uint256 numFuzzedValidators
    )
        internal
        pure
        returns (uint256)
    {
        // identify expected committee size
        uint256 committeeSize;
        if (numFuzzedValidators <= 6) {
            // 4 initial and 6 new validators would be under the 10 committee size
            committeeSize = numActive;
        } else {
            committeeSize = (numActive * PRECISION_FACTOR) / 3 / PRECISION_FACTOR + 1;
        }

        return committeeSize;
    }

    function _fuzz_createNewCommittee(
        uint256 numActive,
        uint256 committeeSize
    )
        internal
        pure
        returns (address[] memory)
    {
        // reloop to construct `newCommittee` array
        address[] memory newCommittee = new address[](committeeSize);
        uint256 committeeCounter;
        // `tokenId` is 1-indexed
        uint256 index = 1 + uint256(keccak256(abi.encode(committeeSize))) % committeeSize;
        // handle index overflow by wrapping around to first index
        uint256 nonOverflowIndex = 1 + numActive - committeeSize;
        index = index > nonOverflowIndex ? nonOverflowIndex : index;
        while (committeeCounter < newCommittee.length) {
            // recreate `validator` address with ConsensusNFT in `setUp()` loop
            address validator = _createRandomAddress(index);
            newCommittee[committeeCounter] = validator;
            committeeCounter++;
            index++;
        }

        return newCommittee;
    }
}
