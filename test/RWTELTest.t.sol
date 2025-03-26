// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";

contract RWTELTest is Test {
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    // rwTEL constructor params
    bytes32 rwTELsalt;
    address consensusRegistry_; // currently points to TN
    address its_; // currently points to TN
    string name_;
    string symbol_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;

    // for fork tests
    Deployments deployments;

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    //todo: separate unit from forks
    // todo: using duplicate gateway until Axelar registers TEL to canonical gateway
    IAxelarGateway sepoliaGateway;
    IERC20 sepoliaTel;
    AxelarAmplifierGateway tnGateway;
    WTEL tnWTEL;
    RWTEL tnRWTEL;

    address admin;
    address telDistributor;
    address user;
    string sourceChain;
    string sourceAddress; // todo bytes
    string destChain;
    string destAddress;
    address token; //todo
    bytes32 tokenId; //todo
    string symbol;
    uint256 amount;
    bytes extCallData;
    bytes payload;
    bytes32 payloadHash;
    string messageId;
    Message[] messages;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        wTEL = new WTEL();

        // todo: separate unit & fork tests to new file
        // todo: currently using duplicate gateway while awaiting Axelar token registration
        its_ = deployments.its.InterchainTokenService;
        name_ = "Recoverable Wrapped Telcoin";
        symbol_ = "rwTEL";
        recoverableWindow_ = 604_800; // 1 week
        governanceAddress_ = address(this); // multisig/council/DAO address in prod
        baseERC20_ = address(wTEL);
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage
        admin = deployments.admin;

        // todo: use create3: deploy impl + proxy and initialize
        rwTELImpl = new RWTEL{ salt: rwTELsalt }(
            address(0xbabe), "chain", its_, name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean
        );
        rwTEL = RWTEL(payable(address(new ERC1967Proxy{ salt: rwTELsalt }(address(rwTELImpl), ""))));
        rwTEL.initialize(governanceAddress_, maxToClean, admin);
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // rwTEL sanity tests
        assertEq(rwTEL.consensusRegistry(), deployments.ConsensusRegistry);
        assertEq(address(rwTEL.interchainTokenService()), deployments.its.InterchainTokenService);
        assertEq(rwTEL.owner(), admin);
        assertTrue(address(rwTEL).code.length > 0);
        string memory rwName = rwTEL.name();
        assertEq(rwName, "Recoverable Wrapped Telcoin");
        string memory rwSymbol = rwTEL.symbol();
        assertEq(rwSymbol, "rwTEL");
        uint256 recoverableWindow = rwTEL.recoverableWindow();
        assertEq(recoverableWindow, recoverableWindow_);
        address governanceAddress = rwTEL.governanceAddress();
        assertEq(governanceAddress, address(this));
    }

    function setUpForkConfig() internal {
        // todo: currently replica; change to canonical Axelar sepolia gateway
        sepoliaGateway = IAxelarGateway(0xB906fC799C9E51f1231f37B867eEd1d9C5a6D472);
        sepoliaTel = IERC20(deployments.sepoliaTEL);
        tnGateway = AxelarAmplifierGateway(deployments.its.AxelarAmplifierGateway);
        tnWTEL = WTEL(payable(deployments.wTEL));
        tnRWTEL = RWTEL(payable(deployments.rwTEL));

        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
        symbol = "TEL";
        amount = 100; // 1 tel
        // `extCallData` is empty for standard bridging
        payload = abi.encode(ExtCall({ target: user, value: amount, data: extCallData }));
        payloadHash = keccak256(payload);
    }

    // todo: refactor for ITS
    function test_bridgeSimulationSepoliaToTN() public {
        /// @dev This test is skipped because it relies on signing with a local key
        /// and to save on RPC calls. Remove to unskip
        vm.skip(true); //todo

        setUpForkConfig();

        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(sepoliaFork);

        sourceChain = "ethereum-sepolia";
        sourceAddress = LibString.toHexString(uint256(uint160(address(sepoliaGateway))), 20);
        destChain = "telcoin-network";
        destAddress = LibString.toHexString(uint256(uint160(address(tnRWTEL))), 20);

        vm.startPrank(user);
        // user must have tokens and approve gateway
        sepoliaTel.approve(address(sepoliaGateway), amount);

        // subscriber will monitor `ContractCall` events
        vm.expectEmit(true, true, true, true);
        emit ContractCall(user, destChain, destAddress, payloadHash, payload);
        sepoliaGateway.callContract(destChain, destAddress, payload);
        vm.stopPrank();

        /**
         * @dev Relayer Action: Monitor Source Gateway for GMP Message Event Emission
         * subscriber picks up event + forwards to GMP API where it is processed by TN verifier
         */
        tnFork = vm.createFork(TN_RPC_URL);
        vm.selectFork(tnFork);

        messageId = "42";
        messages.push(Message(sourceChain, messageId, sourceAddress, address(tnRWTEL), payloadHash));
        // proof must be signed keccak hash of abi encoded `CommandType.ApproveMessages` & message array
        bytes32 dataHash = keccak256(abi.encode(CommandType.ApproveMessages, messages));
        // `domainSeparator` and `signersHash` for the current epoch are queriable on gateway
        bytes32 ethSignPrefixedMsgHash = keccak256(
            bytes.concat(
                "\x19Ethereum Signed Message:\n96",
                tnGateway.domainSeparator(),
                tnGateway.signersHashByEpoch(tnGateway.epoch()),
                dataHash
            )
        );

        /**
         * @dev Verifier Action: Vote on GMP Message Event Validity via Ampd
         * GMP message reaches Axelar Network Voting Verifier contract, where a "verifier" (ampd client ECDSA key)
         * signs and submits signatures ie "votes" or "proofs" via RPC. Verifiers are also known as `WeightedSigners`
         * @notice Must restrict verifiers to only signing "voting" GMP messages emitted as `ContractCallWithToken`
         * todo: revisit above requirement for ITS
         */

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

        /**
         * @dev Relayer Action: Approve GMP Message on Destination Gateway
         * includer polls GMP API for the message processed by Axelar Network verifiers, writes to TN gateway in TX
         * Once settled, GMP message has been successfully sent across chains (bridged) and awaits execution
         */
        bytes32 commandId = tnGateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, sourceChain, messageId, sourceAddress, address(tnRWTEL), payloadHash);
        vm.prank(admin);
        tnGateway.approveMessages(messages, proof);

        /**
         * @dev Relayer Action: Execute GMP Message (`ContractCallWithToken`) on RWTEL Module
         * includer executes GMP messages that have been written to the TN gateway in previous step
         * this tx calls RWTEL module which mints the TEL tokens and delivers them to recipient
         * todo: revisit above
         */

        //todo: RWTEL funding transaction can't be submitted to chain RN so prank it here
        (bool res,) = address(tnRWTEL).call{ value: amount }("");
        require(res);

        uint256 userBalBefore = user.balance;

        vm.expectEmit(true, true, true, true);
        emit MessageExecuted(commandId);
        vm.prank(admin);
        tnRWTEL.executeWithInterchainToken(
            commandId, sourceChain, bytes(sourceAddress), payload, tokenId, token, amount
        );

        // sepolia TEL ERC20 has been bridged and delivered to user as native TEL
        //todo: consider how to handle cross chain decimals (native TEL uses 18; ERC20 TEL uses 2)
        assertEq(user.balance, userBalBefore + amount);
    }

    // todo: refactor for ITS
    function test_bridgeSimulationTNToSepolia() public {
        /// @dev This test is skipped because it relies on signing with a local key
        /// and to save on RPC calls. Remove to unskip
        // vm.skip(true); //todo

        setUpForkConfig();

        tnFork = vm.createFork(TN_RPC_URL);
        vm.selectFork(tnFork);

        vm.deal(user, amount + 100);
        sourceChain = "telcoin-network";
        sourceAddress = LibString.toHexString(uint256(uint160(address(tnGateway))), 20);
        destChain = "ethereum-sepolia";
        // Axelar Ethereum-Sepolia gateway predates AxelarExecutable contract; it contains execution logic
        destAddress = LibString.toHexString(uint256(uint160(address(sepoliaGateway))), 20);

        vm.startPrank(user);
        // wrap amount to wTEL and then to rwTEL, which initiates `recoverableWindow`
        tnWTEL.deposit{ value: amount }();
        tnWTEL.approve(address(tnRWTEL), amount);
        tnRWTEL.wrap(amount);

        // construct payload
        messageId = "42";
        bytes32[] memory commandIds = new bytes32[](1);
        bytes32 commandId = tnGateway.messageToCommandId(sourceChain, messageId);
        commandIds[0] = commandId;
        string[] memory commands = new string[](1);
        commands[0] = "mintToken";
        bytes[] memory params = new bytes[](1);
        bytes memory mintTokenParams = abi.encode(symbol, user, amount);
        params[0] = mintTokenParams;
        bytes memory data = abi.encode(11_155_111, commandIds, commands, params);
        bytes memory proof = "";
        payload = abi.encode(data, proof);

        //todo: bridge attempts should revert until `recoverableWindow` has elapsed

        // elapse time
        vm.warp(block.timestamp + recoverableWindow_);

        //todo: ensure tokenHandler is called as part of ITS flow
        vm.expectEmit();
        emit ContractCall(user, destChain, destAddress, keccak256(payload), payload);
        tnGateway.callContract(destChain, destAddress, payload);

        // sepolia side
        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(sepoliaFork);

        //todo: this was deprecated?
        // sepoliaGateway.execute(payload);
    }
}

/// @notice Redeclared event from `BaseAmplifierGateway` for testing
event MessageApproved(
    bytes32 indexed commandId,
    string sourceChain,
    string messageId,
    string sourceAddress,
    address indexed contractAddress,
    bytes32 indexed payloadHash
);

/// @notice Redeclared event from `IAxelarGMPGateway` for testing
event ContractCall(
    address indexed sender,
    string destinationChain,
    string destinationContractAddress,
    bytes32 indexed payloadHash,
    bytes payload
);

/// @notice Redeclared event from `BaseAmplifierGateway` for testing
event MessageExecuted(bytes32 indexed commandId);
