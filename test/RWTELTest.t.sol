// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import { WeightedSigner, WeightedSigners, Proof } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";

contract RWTELTest is Test {
    WTEL wTEL;
    RWTEL rwTEL;

    // rwTEL constructor params
    string name_;
    string symbol_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;

    // for fork tests
    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    IERC20 sepoliaTel = IERC20(0x92bc9f0D42A3194Df2C5AB55c3bbDD82e6Fb2F92);
    IAxelarGateway sepoliaGateway = IAxelarGateway(0xB906fC799C9E51f1231f37B867eEd1d9C5a6D472); //todo: mocked
    AxelarAmplifierGateway tnGateway = AxelarAmplifierGateway(0xBf02955Dc36E54Fe0274159DbAC8A7B79B4e4dc3);

    address admin;
    address telDistributor;
    address user;
    string destChain;
    string destAddress;
    string symbol;
    uint256 amount;
    bytes data;
    bytes payload;
    bytes32 payloadHash;
    string sourceAddress;
    address contractAddress;
    string messageId;
    Message[] messages;

    function setUp() public {
        wTEL = new WTEL();

        name_ = "Recoverable Wrapped Telcoin";
        symbol_ = "rwTEL";
        recoverableWindow_ = 86_400; // ~1 day; Telcoin Network blocktime is ~1s
        governanceAddress_ = address(this); // multisig/council/DAO address in prod
        baseERC20_ = address(wTEL);
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage

        // using placeholder for consensus registry
        rwTEL = new RWTEL(
            address(0x0),
            address(tnGateway),
            name_,
            symbol_,
            recoverableWindow_,
            governanceAddress_,
            baseERC20_,
            maxToClean
        );

        admin = vm.addr(vm.envUint("ADMIN_PK"));
        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // rwTEL sanity tests
        assertTrue(address(rwTEL).code.length > 0);
        string memory rwName = rwTEL.name();
        assertEq(rwName, "Recoverable Wrapped Telcoin");
        string memory rwSymbol = rwTEL.symbol();
        assertEq(rwSymbol, "rwTEL");
        uint256 recoverableWindow = rwTEL.recoverableWindow();
        assertEq(recoverableWindow, 86_400);
        address governanceAddress = rwTEL.governanceAddress();
        assertEq(governanceAddress, address(this));
    }

    function test_bridgeSimulationSepoliaToTN() public {
        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(sepoliaFork);

        destChain = "telcoin-network";
        destAddress = "0xca568d148d23a4ca9b77bef783dca0d2f5962c12"; // tn::rwtel
        symbol = "TEL";
        amount = 100; // 1 tel
        // `data` is empty for standard bridging
        payload = abi.encode(ExtCall({ target: user, value: amount, data: data }));
        payloadHash = keccak256(payload);

        vm.startPrank(user);
        // user must have tokens and approve gateway
        sepoliaTel.approve(address(sepoliaGateway), amount);
        
        // subscriber will monitor `ContractCall` events
        vm.expectEmit(true, true, true, true);
        emit ContractCallWithToken(user, destChain, destAddress, payloadHash, payload, symbol, amount);
        sepoliaGateway.callContractWithToken(destChain, destAddress, payload, symbol, amount);
        vm.stopPrank();

        // relayer actions:
        // subscriber picks up event + forwards to GMP API where it is processed by TN verifier
        // includer polls GMP API for the message processed by Axelar network and settles to TN gateway

        tnFork = vm.createFork(TN_RPC_URL);
        vm.selectFork(tnFork);

        //todo: should this be gateway or user?
        sourceAddress = "0xe432150cce91c13a887f7D836923d5597adD8E31";
        contractAddress = 0xCA568D148d23a4CA9B77BeF783dCa0d2F5962C12;
        messageId = "42";
        messages.push(Message(destChain, messageId, sourceAddress, contractAddress, payloadHash));
        // proof must be signed keccak hash of abi encoded `CommandType.ApproveMessages` & message array
        bytes32 dataHash = keccak256(abi.encode(CommandType.ApproveMessages, messages));
        // `domainSeparator` and `signersHash` for the current epoch are queriable on gateway 
        bytes32 ethSignPrefixedMsgHash =
            keccak256(bytes.concat(
                "\x19Ethereum Signed Message:\n96", 
                tnGateway.domainSeparator(), 
                tnGateway.signerHashByEpoch(tnGateway.epoch()), 
                dataHash
            ));
        
        // TN gateway currently uses a single signer of `admin` with weight 1
        WeightedSigner[] memory signers = new WeightedSigner[](1);
        signers[0] = WeightedSigner(admin, 1);
        // signer set `nonce == bytes32(0)` and for a single signer, `threshold == 1`
        WeightedSigners memory weightedSigners = WeightedSigners(signers, 1, bytes32(0x0));
        // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("ADMIN_PK"), ethSignPrefixedMsgHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        Proof memory proof = Proof(weightedSigners, signatures);

        string memory sourceChain = "ethereum-sepolia";
        bytes32 commandId = tnGateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, destChain, messageId, sourceAddress, contractAddress, payloadHash);
        vm.prank(admin);
        tnGateway.approveMessages(messages, proof);

        // todo: execute
    }
}

/// @notice Redeclared event from `AxelarGateway` for testing
event ContractCallWithToken(
    address indexed sender,
    string destinationChain,
    string destinationContractAddress,
    bytes32 indexed payloadHash,
    bytes payload,
    string symbol,
    uint256 amount
);

/// @notice Redeclared event from `BaseAmplifierGateway` for testing
event MessageApproved(
    bytes32 indexed commandId,
    string sourceChain,
    string messageId,
    string sourceAddress,
    address indexed contractAddress,
    bytes32 indexed payloadHash
);

interface IAxelarGateway {
    function sendToken(
        string calldata destinationChain,
        string calldata destinationAddress,
        string calldata symbol,
        uint256 amount
    )
        external;
    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    )
        external;
    function callContractWithToken(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    )
        external;
    function isContractCallApproved(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        address contractAddress,
        bytes32 payloadHash
    )
        external
        view
        returns (bool);
    function isContractCallAndMintApproved(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        address contractAddress,
        bytes32 payloadHash,
        string calldata symbol,
        uint256 amount
    )
        external
        view
        returns (bool);
    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    )
        external
        returns (bool);
    function validateContractCallAndMint(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash,
        string calldata symbol,
        uint256 amount
    )
        external
        returns (bool);
    function tokenAddresses(string memory symbol) external view returns (address);
    function isCommandExecuted(bytes32 commandId) external view returns (bool);
    function execute(bytes calldata input) external;
}
