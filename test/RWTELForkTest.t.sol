// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2, Vm } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAxelarGateway } from "@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGateway.sol";
import { IDeploy } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IDeploy.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { TokenManagerProxy } from "@axelar-network/interchain-token-service/contracts/proxies/TokenManagerProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { IInterchainTokenService } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenService.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "../deployments/utils/Create3Utils.sol";
import { ITS } from "../deployments/Deployments.sol";
import { HarnessCreate3FixedAddressForITS, ITSTestHelper } from "./ITS/ITSTestHelper.sol";

contract RWTELForkTest is Test, ITSTestHelper {
    Deployments deployments;
    address admin;

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    address user;
    address recipient;
    string originChain; // original EVM source chain pre-wrap
    address originAddress; // original EVM source chain ITS address
    string sourceChain; // ITS hub wraps messages and becomes sourceChain
    string sourceAddressString; // ITS hub wraps messages with hub identifier as source address
    string destinationChain;
    address destinationAddress;
    string destinationAddressString;
    string name;
    string symbol;
    uint8 decimals;
    uint256 interchainAmount;
    uint256 nativeAmount;
    bytes payload;
    bytes wrappedPayload; // ITS hub wraps payloads
    string messageId;
    Message[] messages;

    Vm.Wallet mockVerifier = vm.createWallet("mock-verifier"); // simulates Axelar verifier proofs

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;
        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
        recipient = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180); // bridge to self
        name = "Telcoin";
        symbol = "TEL";
        decimals = 2;
        interchainAmount = 100; // 1 interchain ERC20 TEL
        nativeAmount = 10e18; // 1 nativeTEL

        sepoliaFork = vm.createSelectFork(SEPOLIA_RPC_URL);
        // send tokenManager sepolia TEL so it can unlock them
        vm.prank(user);
        IERC20(deployments.sepoliaTEL).transfer(address(deployments.rwTELTokenManager), interchainAmount);

        tnFork = vm.createFork(TN_RPC_URL);
    }

    function test_tn_rwtelInterchainTransfer_RWTEL() public {
        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(
            deployments.its,
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.wTEL,
            deployments.rwTELImpl,
            deployments.rwTEL,
            deployments.rwTELTokenManager
        );

        // give funds to user
        vm.deal(user, nativeAmount + gasValue);
        // user double wraps native TEL
        vm.prank(user);
        rwTEL.doubleWrap{ value: nativeAmount }();

        destinationChain = DEVNET_SEPOLIA_CHAIN_NAME;
        uint256 unsettledBal = IERC20(address(rwTEL)).balanceOf(user);
        uint256 srcBalBeforeTEL = user.balance;
        uint256 rwtelBalBefore = address(rwTEL).balance;
        assertEq(unsettledBal, 0);
        assertEq(srcBalBeforeTEL, gasValue);
        assertEq(rwtelBalBefore, telTotalSupply);

        // attempt outbound transfer without elapsing recoverable window
        vm.startPrank(user);
        bytes memory nestedErr = abi.encodeWithSignature("Error(string)", "TEL mint failed");
        vm.expectRevert(abi.encodeWithSelector(IInterchainTokenService.TakeTokenFailed.selector, nestedErr));
        rwTEL.interchainTransfer{ value: gasValue }(destinationChain, AddressBytes.toBytes(recipient), nativeAmount, "");

        // outbound interchain bridge transfers *MUST* await recoverable window to settle RWTEL balance
        uint256 recoverableEndBlock = block.timestamp + rwTEL.recoverableWindow() + 1;
        vm.warp(recoverableEndBlock);
        uint256 settledBalBefore = IERC20(address(rwTEL)).balanceOf(user);
        assertEq(settledBalBefore, nativeAmount);
        assertEq(IERC20(address(rwTEL)).totalSupply(), nativeAmount);
        rwTEL.interchainTransfer{ value: gasValue }(destinationChain, AddressBytes.toBytes(recipient), nativeAmount, "");

        vm.stopPrank();

        uint256 expectedUserBalTEL = settledBalBefore - nativeAmount;
        uint256 expectedRWTELBal = rwtelBalBefore + nativeAmount;
        assertEq(IERC20(address(rwTEL)).balanceOf(user), expectedUserBalTEL);
        assertEq(IERC20(address(rwTEL)).totalSupply(), 0);
        assertEq(address(rwTEL).balance, expectedRWTELBal);
    }

    function test_tn_rwtelInterchainTransferFrom_RWTEL() public {
        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(
            deployments.its,
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.wTEL,
            deployments.rwTELImpl,
            deployments.rwTEL,
            deployments.rwTELTokenManager
        );

        // give funds to user
        vm.deal(user, nativeAmount + gasValue);
        // user double wraps native TEL and pre-approves contract to spend rwTEL
        vm.startPrank(user);
        rwTEL.doubleWrap{ value: nativeAmount }();
        rwTEL.approve(address(this), nativeAmount);
        vm.stopPrank();

        destinationChain = DEVNET_SEPOLIA_CHAIN_NAME;
        uint256 unsettledBal = IERC20(address(rwTEL)).balanceOf(user);
        uint256 srcBalBeforeTEL = user.balance;
        uint256 rwtelBalBefore = address(rwTEL).balance;
        assertEq(unsettledBal, 0);
        assertEq(srcBalBeforeTEL, gasValue);
        assertEq(rwtelBalBefore, telTotalSupply);

        // attempt outbound transfer without elapsing recoverable window
        bytes memory nestedErr = abi.encodeWithSignature("Error(string)", "TEL mint failed");
        vm.expectRevert(abi.encodeWithSelector(IInterchainTokenService.TakeTokenFailed.selector, nestedErr));
        rwTEL.interchainTransferFrom{ value: gasValue }(
            user, destinationChain, AddressBytes.toBytes(recipient), nativeAmount, ""
        );

        // outbound interchain bridge transfers *MUST* await recoverable window to settle RWTEL balance
        uint256 recoverableEndBlock = block.timestamp + rwTEL.recoverableWindow() + 1;
        vm.warp(recoverableEndBlock);
        uint256 settledBalBefore = IERC20(address(rwTEL)).balanceOf(user);
        assertEq(settledBalBefore, nativeAmount);
        assertEq(IERC20(address(rwTEL)).totalSupply(), nativeAmount);
        rwTEL.interchainTransferFrom{ value: gasValue }(
            user, destinationChain, AddressBytes.toBytes(recipient), nativeAmount, ""
        );

        assertEq(IERC20(address(rwTEL)).totalSupply(), 0);
        assertEq(IERC20(address(rwTEL)).balanceOf(user), settledBalBefore - nativeAmount);
        assertEq(address(rwTEL).balance, rwtelBalBefore + nativeAmount);
    }

    /// @notice Test TN genesis precompiles rwTEL and rwTELTokenManager match Ethereum ITS's origin addresses
    /// by simulating `linkToken()` to Telcoin Network (obviated by Telcoin-Network genesis)
    /// @notice Ensures precompiles for RWTEL + its TokenManager match those expected (& otherwise produced) by ITS
    function test_e2eDevnet_linkToken_RWTEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.its.InterchainTokenService,
            deployments.its.InterchainTokenFactory,
            deployments.rwTELImpl
        );

        // Register origin TEL metadata and deploy origin TEL token manager on origin as linker
        destinationChain = TN_CHAIN_NAME;
        vm.startPrank(linker);
        (bytes32 returnedInterchainTokenSalt, bytes32 returnedInterchainTokenId, TokenManager returnedTELTokenManager) =
        eth_registerCustomTokenAndLinkToken(
            originTEL, linker, destinationChain, originTMType, AddressBytes.toAddress(tmOperator), gasValue, sepoliaITF
        );
        vm.stopPrank();

        // sanity asserts for post origin registration
        assertEq(address(returnedTELTokenManager), deployments.rwTELTokenManager);
        bytes32 expectedTELTokenId = sepoliaITF.linkedTokenId(linker, salts.registerCustomTokenSalt);
        assertEq(expectedTELTokenId, sepoliaITS.interchainTokenId(address(0x0), returnedInterchainTokenSalt));

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        payload = abi.encode(
            MESSAGE_TYPE_LINK_TOKEN,
            returnedInterchainTokenId,
            rwtelTMType,
            AddressBytes.toBytes(originTEL),
            AddressBytes.toBytes(address(rwTEL)),
            tmOperator
        );

        /// @notice Message is relayed through Axelar Network

        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(
            deployments.its,
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.wTEL,
            deployments.rwTELImpl,
            deployments.rwTEL,
            deployments.rwTELTokenManager
        );

        // assert returned ITS values match genesis expectations
        _devnetAsserts_rwTEL_rwTELTokenManager(
            expectedTELTokenId, returnedInterchainTokenSalt, returnedInterchainTokenId, address(returnedTELTokenManager)
        );
        /// @notice Incoming messages routed via ITS hub are in wrapped `RECEIVE_FROM_HUB` format
        /// for interchain transfers, Message's `destinationAddress = its` and payload's `recipient = user`
        originChain = DEVNET_SEPOLIA_CHAIN_NAME;
        wrappedPayload = abi.encode(MESSAGE_TYPE_RECEIVE_FROM_HUB, originChain, payload);
        sourceChain = ITS_HUB_CHAIN_NAME;
        sourceAddressString = ITS_HUB_ROUTING_IDENTIFIER;
        destinationAddress = address(its);
        messageId = "42";
        Message memory message =
            _craftITSMessage(messageId, sourceChain, sourceAddressString, destinationAddress, wrappedPayload);
        messages.push(message);

        // use gatewayOperator to overwrite devnet config verifier for tests
        vm.startPrank(admin);
        (WeightedSigners memory weightedSigners, bytes32 signersHash) = _overwriteWeightedSigners(mockVerifier.addr);
        vm.stopPrank();

        // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
        bytes32 approveMessagesHash =
            gateway.messageHashToSign(signersHash, keccak256(abi.encode(CommandType.ApproveMessages, messages)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mockVerifier.privateKey, approveMessagesHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        Proof memory proof = Proof(weightedSigners, signatures);

        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(
            commandId, sourceChain, messageId, sourceAddressString, destinationAddress, keccak256(wrappedPayload)
        );
        gateway.approveMessages(messages, proof);

        bytes memory alreadyDeployed = abi.encodePacked(IDeploy.AlreadyDeployed.selector);
        bytes memory tokenManagerCollision =
            abi.encodeWithSelector(IInterchainTokenService.TokenManagerDeploymentFailed.selector, alreadyDeployed);
        vm.expectRevert(tokenManagerCollision);
        its.execute(commandId, sourceChain, sourceAddressString, wrappedPayload);

        assertEq(its.interchainTokenAddress(expectedTELTokenId), address(rwTEL));
    }

    function test_e2eDevnet_bridgeSimulation_toTN() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.its.InterchainTokenService,
            deployments.its.InterchainTokenFactory,
            deployments.rwTELImpl
        );

        // Register origin TEL metadata and deploy origin TEL token manager on origin as linker
        destinationChain = TN_CHAIN_NAME;
        vm.startPrank(linker);
        (bytes32 returnedInterchainTokenSalt, bytes32 returnedInterchainTokenId, TokenManager returnedTELTokenManager) =
        eth_registerCustomTokenAndLinkToken(
            originTEL, linker, destinationChain, originTMType, AddressBytes.toAddress(tmOperator), gasValue, sepoliaITF
        );
        vm.stopPrank();

        // sanity asserts for post origin registration
        assertEq(sepoliaITS.interchainTokenAddress(returnedInterchainTokenId), deployments.rwTEL);
        assertEq(address(returnedTELTokenManager), deployments.rwTELTokenManager);
        bytes32 expectedTELTokenId = sepoliaITF.linkedTokenId(linker, salts.registerCustomTokenSalt);
        assertEq(expectedTELTokenId, sepoliaITS.interchainTokenId(address(0x0), returnedInterchainTokenSalt));

        // give gas funds to user and pre-approve ITS to spend its TEL
        vm.deal(user, gasValue);
        vm.prank(user);
        IERC20(originTEL).approve(address(sepoliaITS), interchainAmount);
        originAddress = address(sepoliaITS);
        payload = abi.encode(
            MESSAGE_TYPE_INTERCHAIN_TRANSFER,
            returnedInterchainTokenId,
            AddressBytes.toBytes(user),
            AddressBytes.toBytes(recipient),
            interchainAmount,
            ""
        );
        wrappedPayload = abi.encode(MESSAGE_TYPE_SEND_TO_HUB, destinationChain, payload);

        vm.startPrank(user);
        // user must have tokens and approve gateway
        IERC20(originTEL).approve(address(sepoliaITS), interchainAmount);

        uint256 srcBalBefore = IERC20(originTEL).balanceOf(user);
        uint256 destBalBefore = IERC20(originTEL).balanceOf(address(returnedTELTokenManager));

        // ITS wraps `ContractCall` events with Axelar Hub info
        vm.expectEmit(true, true, true, true);
        emit ContractCall(
            originAddress, ITS_HUB_CHAIN_NAME, ITS_HUB_ROUTER_ADDR, keccak256(wrappedPayload), wrappedPayload
        );

        sepoliaITS.interchainTransfer{ value: gasValue }(
            returnedInterchainTokenId, destinationChain, AddressBytes.toBytes(recipient), interchainAmount, "", gasValue
        );
        vm.stopPrank();

        assertEq(IERC20(originTEL).balanceOf(user), srcBalBefore - interchainAmount);
        assertEq(IERC20(originTEL).balanceOf(address(returnedTELTokenManager)), destBalBefore + interchainAmount);

        /**
         * @dev Relayer Action: Monitor Source Gateway for GMP Message Event Emission
         * subscriber picks up event + forwards to GMP API where it is processed by TN verifier
         */
        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(
            deployments.its,
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.wTEL,
            deployments.rwTELImpl,
            deployments.rwTEL,
            deployments.rwTELTokenManager
        );

        /**
         * @dev Verifier Action: Vote on GMP Message Event Validity via Ampd
         * GMP message reaches Axelar Network Voting Verifier contract, where a "verifier" (ampd client ECDSA key)
         * signs and submits signatures ie "votes" or "proofs" via RPC. Verifiers are also known as `WeightedSigners`
         * @notice Devnet config uses `admin` as a single signer with weight and threshold == 1
         */

        /// @notice Incoming messages routed via ITS hub are in wrapped `RECEIVE_FROM_HUB` format
        /// for interchain transfers, Message's `destinationAddress = its` and payload's `recipient = user`
        originChain = DEVNET_SEPOLIA_CHAIN_NAME;
        wrappedPayload = abi.encode(MESSAGE_TYPE_RECEIVE_FROM_HUB, originChain, payload);
        sourceChain = ITS_HUB_CHAIN_NAME;
        sourceAddressString = ITS_HUB_ROUTING_IDENTIFIER;
        destinationAddress = address(its);
        messageId = "42";
        Message memory message =
            _craftITSMessage(messageId, sourceChain, sourceAddressString, destinationAddress, wrappedPayload);
        messages.push(message);

        // use gatewayOperator to overwrite devnet config verifier for tests
        vm.startPrank(admin);
        (WeightedSigners memory weightedSigners, bytes32 signersHash) = _overwriteWeightedSigners(mockVerifier.addr);
        vm.stopPrank();

        // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
        bytes32 approveMessagesHash =
            gateway.messageHashToSign(signersHash, keccak256(abi.encode(CommandType.ApproveMessages, messages)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mockVerifier.privateKey, approveMessagesHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        Proof memory proof = Proof(weightedSigners, signatures);

        /**
         * @dev Relayer Action: Approve ITS Message on Destination Gateway
         * Includer polls GMP API for the message processed by Axelar Network verifiers, writes to TN gateway in TX
         * Once settled, GMP message has been successfully sent across chains (bridged) and awaits execution
         */
        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(
            commandId, sourceChain, messageId, sourceAddressString, destinationAddress, keccak256(wrappedPayload)
        );
        gateway.approveMessages(messages, proof);

        assertTrue(
            gateway.isMessageApproved(
                sourceChain, messageId, sourceAddressString, destinationAddress, keccak256(wrappedPayload)
            )
        );

        /**
         * @dev Relayer Action: Execute ITS Message (`ContractCall`) on RWTEL Module
         * Includer executes GMP messages that have been written to the TN gateway in previous step
         * execution calls RWTEL's TokenManager which in turn calls RWTEL module's `mint()` function,
         * translating interchain TEL decimals to mint native TEL to the recipient
         */
        uint256 userBalBefore = user.balance;
        uint256 rwtelBalBefore = address(rwTEL).balance;
        assertEq(rwtelBalBefore, telTotalSupply);

        vm.expectEmit(true, true, true, true);
        emit MessageExecuted(commandId);
        its.execute(commandId, sourceChain, sourceAddressString, wrappedPayload);

        assertTrue(gateway.isMessageExecuted(sourceChain, messageId));

        // sepolia TEL ERC20 has been bridged and delivered to user as native TEL
        uint256 decimalConvertedAmt = rwTEL.toEighteenDecimals(interchainAmount);
        assertEq(user.balance, userBalBefore + decimalConvertedAmt);
        assertEq(address(rwTEL).balance, rwtelBalBefore - decimalConvertedAmt);
    }

    function test_e2eDevnet_bridgeSimulation_fromTN() public {
        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(
            deployments.its,
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.wTEL,
            deployments.rwTELImpl,
            deployments.rwTEL,
            deployments.rwTELTokenManager
        );

        uint256 startingNativeBal = nativeAmount + gasValue;
        vm.deal(user, startingNativeBal);
        // user double wraps native TEL
        vm.prank(user);
        rwTEL.doubleWrap{ value: nativeAmount }();

        uint256 unsettledBal = IERC20(address(rwTEL)).balanceOf(user);
        uint256 srcBalBeforeTEL = user.balance;
        uint256 rwtelBalBefore = address(rwTEL).balance;
        assertEq(unsettledBal, 0);
        assertEq(srcBalBeforeTEL, startingNativeBal - nativeAmount);
        assertEq(rwtelBalBefore, telTotalSupply);

        // outbound interchain bridge transfers *MUST* await recoverable window to settle RWTEL balance
        uint256 recoverableEndBlock = block.timestamp + rwTEL.recoverableWindow() + 1;
        vm.warp(recoverableEndBlock);
        uint256 settledBalBefore = IERC20(address(rwTEL)).balanceOf(user);
        assertEq(settledBalBefore, nativeAmount);
        assertEq(IERC20(address(rwTEL)).totalSupply(), nativeAmount);

        (interchainAmount,) = rwTEL.toTwoDecimals(nativeAmount);
        destinationChain = DEVNET_SEPOLIA_CHAIN_NAME;
        originAddress = address(its);
        payload = abi.encode(
            MESSAGE_TYPE_INTERCHAIN_TRANSFER,
            rwTEL.interchainTokenId(),
            AddressBytes.toBytes(user),
            AddressBytes.toBytes(recipient),
            interchainAmount,
            ""
        );
        wrappedPayload = abi.encode(MESSAGE_TYPE_SEND_TO_HUB, destinationChain, payload);

        // ITS wraps `ContractCall` events with Axelar Hub info
        vm.expectEmit(true, true, true, true);
        emit ContractCall(
            originAddress, ITS_HUB_CHAIN_NAME, ITS_HUB_ROUTING_IDENTIFIER, keccak256(wrappedPayload), wrappedPayload
        );

        vm.prank(user);
        rwTEL.interchainTransfer{ value: gasValue }(destinationChain, AddressBytes.toBytes(recipient), nativeAmount, "");

        uint256 expectedUserBalTEL = settledBalBefore - nativeAmount;
        uint256 expectedRWTELBal = rwtelBalBefore + nativeAmount;
        assertEq(IERC20(address(rwTEL)).balanceOf(user), expectedUserBalTEL);
        assertEq(IERC20(address(rwTEL)).totalSupply(), 0);
        assertEq(address(rwTEL).balance, expectedRWTELBal);

        /**
         * @dev Relayer Action: Monitor Source Gateway for GMP Message Event Emission
         * subscriber picks up event + forwards to GMP API where it is processed by TN verifier
         */
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.admin,
            deployments.sepoliaTEL,
            deployments.its.InterchainTokenService,
            deployments.its.InterchainTokenFactory,
            deployments.rwTELImpl
        );

        // Register origin TEL metadata and deploy origin TEL token manager on origin as linker
        destinationChain = TN_CHAIN_NAME; // linking done out of order after TN actions
        vm.startPrank(linker);
        eth_registerCustomTokenAndLinkToken(
            originTEL, linker, destinationChain, originTMType, AddressBytes.toAddress(tmOperator), gasValue, sepoliaITF
        );
        vm.stopPrank();

        originChain = TN_CHAIN_NAME;
        wrappedPayload = abi.encode(MESSAGE_TYPE_RECEIVE_FROM_HUB, originChain, payload);

        // for interchain transfers, Message's `destinationAddress = its` and payload's `recipient = user`
        sourceChain = ITS_HUB_CHAIN_NAME;
        sourceAddressString = ITS_HUB_ROUTING_IDENTIFIER;
        destinationAddress = address(sepoliaITS);
        messageId = "42";
        Message memory message =
            _craftITSMessage(messageId, sourceChain, sourceAddressString, destinationAddress, wrappedPayload);
        messages.push(message);

        // use gatewayOperator to overwrite devnet config verifier for tests
        (, address[] memory newOperators, uint256[] memory weights) =
            _eth_overwriteWeightedSigners(address(sepoliaGateway), mockVerifier.addr);

        // approve call using sepolia gateway's legacy versioning
        bytes32 commandId = keccak256(bytes(string.concat(sourceChain, "_", messageId)));
        (bytes memory executeData, bytes32 executeHash) = _getLegacyGatewayApprovalParams(
            commandId, sourceChain, sourceAddressString, destinationAddress, wrappedPayload
        );

        // spoof verifier signature of approval params
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mockVerifier.privateKey, executeHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        bytes memory proof = abi.encode(newOperators, weights, threshold, signatures);

        // approve contract call using legacy gateway execute()
        vm.expectEmit(true, true, true, true);
        emit IAxelarGateway.ContractCallApproved(
            commandId, sourceChain, sourceAddressString, destinationAddress, keccak256(wrappedPayload), bytes32(0x0), 0
        );
        sepoliaGateway.execute(abi.encode(executeData, proof));

        // todo: clarify setTrustedAddress with Axelar
        vm.startPrank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(originChain, ITS_HUB_ROUTING_IDENTIFIER);
        sepoliaITS.setTrustedAddress(sourceChain, ITS_HUB_ROUTING_IDENTIFIER);
        vm.stopPrank();

        uint256 userBalBefore = IERC20(originTEL).balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit IInterchainTokenService.InterchainTransferReceived(
            commandId,
            customLinkedTokenId,
            originChain,
            AddressBytes.toBytes(user),
            recipient,
            interchainAmount,
            bytes32(0x0)
        );
        sepoliaITS.execute(commandId, sourceChain, sourceAddressString, wrappedPayload);

        assertTrue(sepoliaGateway.isCommandExecuted(commandId));
        // native TN TEL has been bridged and delivered to user as interchain ERC20 TEL
        assertEq(IERC20(originTEL).balanceOf(user), userBalBefore + interchainAmount);
    }

    //todo: fuzz tests for rwTEL, TEL bridging, rwteltest.t.sol
    //todo: incorporate RWTEL contracts to TN protocol on rust side
    //todo: remove ExtCall
    //todo: update readme, npm instructions
}
