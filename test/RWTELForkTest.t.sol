// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2, Vm } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
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

    Vm.Wallet mockVerifier = vm.createWallet("mock-verifier");
    address telDistributor;
    address user;
    string sourceChain;
    address sourceAddress;
    string sourceAddressString;
    address recipient;
    string destinationChain;
    address destinationAddress;
    string destinationAddressString;
    string name;
    string symbol;
    uint8 decimals;
    uint256 amount;
    bytes payload;
    bytes wrappedPayload;
    string messageId;
    Message[] messages;

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
        amount = 100; // 1 ERC20 tel

        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        tnFork = vm.createFork(TN_RPC_URL);
    }

    /// @notice Test TN genesis precompiles rwTEL and rwTELTokenManager match Ethereum ITS's canonical addresses
    /// by simulating `deployRemoteCanonicalInterchainToken` (obviated by Telcoin-Network genesis)
    /// @notice Ensures precompiles for RWTEL + its TokenManager match those expected (& otherwise produced) by ITS
    function test_e2eDevnet_deployRemoteCanonicalInterchainToken_RWTEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.sepoliaTEL, deployments.its.InterchainTokenService, deployments.its.InterchainTokenFactory
        );

        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        (bytes32 returnedInterchainTokenSalt, bytes32 returnedInterchainTokenId, TokenManager returnedTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF);

        // sanity asserts for post canonical registration
        assertEq(sepoliaITS.interchainTokenAddress(returnedInterchainTokenId), deployments.rwTEL);
        assertEq(address(returnedTELTokenManager), deployments.rwTELTokenManager);
        bytes32 expectedTELTokenId = sepoliaITF.canonicalInterchainTokenId(canonicalTEL);
        assertEq(expectedTELTokenId, sepoliaITS.interchainTokenId(address(0x0), returnedInterchainTokenSalt));

        // note that TN must be added as a trusted chain to the Ethereum ITS contract
        destinationChain = TN_CHAIN_NAME;
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        payload =
            abi.encode(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, returnedInterchainTokenId, name, symbol, decimals, "");
        wrappedPayload = abi.encode(MESSAGE_TYPE_SEND_TO_HUB, destinationChain, payload);
        vm.expectEmit(true, true, true, true);
        emit ContractCall(
            address(sepoliaITS), ITS_HUB_CHAIN_NAME, ITS_HUB_ROUTER_ADDR, keccak256(wrappedPayload), wrappedPayload
        );
        /// @notice This deployment and all following steps are obviated by genesis precompiles and must
        /// be skipped, because ITS + RWTEL are created at TN genesis, and it results in `RWTEL::decimals == 2`
        bytes32 remoteCanonicalTokenId =
            sepoliaITF.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL, destinationChain, gasValue);
        assertEq(remoteCanonicalTokenId, returnedInterchainTokenId);

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
        _devnetAsserts_rwTEL_rwTELTokenManager(expectedTELTokenId, returnedInterchainTokenSalt, returnedInterchainTokenId, address(returnedTELTokenManager));

        messageId = "42";
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        sourceAddressString = LibString.toHexString(address(sepoliaITS));
        destinationAddress = address(its);
        Message memory message = _craftITSMessage(messageId, sourceChain, sourceAddressString, destinationAddress, payload);
        messages.push(message);

        // use gatewayOperator to overwrite devnet config verifier for tests
        vm.startPrank(admin);
        (WeightedSigners memory weightedSigners, bytes32 signersHash) = _overwriteWeightedSigners(mockVerifier.addr);
        vm.stopPrank();

        // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
        bytes32 approveMessagesHash = gateway.messageHashToSign(signersHash, keccak256(abi.encode(CommandType.ApproveMessages, messages)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mockVerifier.privateKey, approveMessagesHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        Proof memory proof = Proof(weightedSigners, signatures);

        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, sourceChain, messageId, sourceAddressString, destinationAddress, keccak256(payload));
        gateway.approveMessages(messages, proof);

        /**
         * @dev Relayer Action: Execute GMP Message (`ContractCall`) on RWTEL Module
         * Includer executes GMP messages that have been written to the TN gateway in previous step
         * this tx calls RWTEL module which mints the TEL tokens and delivers them to recipient
         */
        bytes memory alreadyDeployed = abi.encodePacked(IDeploy.AlreadyDeployed.selector);
        bytes memory rwtelCollision =
            abi.encodeWithSelector(IInterchainTokenService.InterchainTokenDeploymentFailed.selector, alreadyDeployed);
        vm.expectRevert(rwtelCollision);
        its.execute(commandId, sourceChain, sourceAddressString, payload);

        // wipe genesis deployment to prevent revert on token deployment and reach revert on token manager deploy
        vm.etch(address(rwTEL), "");
        bytes memory tokenManagerCollision =
            abi.encodeWithSelector(IInterchainTokenService.TokenManagerDeploymentFailed.selector, alreadyDeployed);
        vm.expectRevert(tokenManagerCollision);
        its.execute(commandId, sourceChain, sourceAddressString, payload);
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
        amount = 10e18; // 1 nativeTEL
        vm.deal(user, amount + gasValue);
        // user double wraps native TEL
        vm.prank(user);
        rwTEL.doubleWrap{value: amount }();

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
        rwTEL.interchainTransfer{ value: gasValue }(
            destinationChain, AddressBytes.toBytes(recipient), amount, ""
        );

        // outbound interchain bridge transfers *MUST* await recoverable window to settle RWTEL balance
        uint256 recoverableEndBlock = block.timestamp + rwTEL.recoverableWindow() + 1;
        vm.warp(recoverableEndBlock);
        uint256 settledBalBefore = IERC20(address(rwTEL)).balanceOf(user);
        assertEq(settledBalBefore, amount);
        assertEq(IERC20(address(rwTEL)).totalSupply(), amount);
        rwTEL.interchainTransfer{ value: gasValue }(
            destinationChain, AddressBytes.toBytes(recipient), amount, ""
        );

        vm.stopPrank();

        uint256 expectedUserBalTEL = settledBalBefore - amount;
        uint256 expectedRWTELBal = rwtelBalBefore + amount;
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
        amount = 10e18; // 1 nativeTEL
        vm.deal(user, amount + gasValue);
        // user double wraps native TEL and pre-approves contract to spend rwTEL
        vm.startPrank(user);
        rwTEL.doubleWrap{value: amount }();
        rwTEL.approve(address(this), amount);
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
            user, destinationChain, AddressBytes.toBytes(recipient), amount, ""
        );

        // outbound interchain bridge transfers *MUST* await recoverable window to settle RWTEL balance
        uint256 recoverableEndBlock = block.timestamp + rwTEL.recoverableWindow() + 1;
        vm.warp(recoverableEndBlock);
        uint256 settledBalBefore = IERC20(address(rwTEL)).balanceOf(user);
        assertEq(settledBalBefore, amount);
        assertEq(IERC20(address(rwTEL)).totalSupply(), amount);
        rwTEL.interchainTransferFrom{ value: gasValue }(
            user, destinationChain, AddressBytes.toBytes(recipient), amount, ""
        );

        assertEq(IERC20(address(rwTEL)).totalSupply(), 0);
        assertEq(IERC20(address(rwTEL)).balanceOf(user), settledBalBefore - amount);
        assertEq(address(rwTEL).balance, rwtelBalBefore + amount);
    }

    function test_e2eDevnet_bridgeSimulation_sepoliaToTN() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.sepoliaTEL, deployments.its.InterchainTokenService, deployments.its.InterchainTokenFactory
        );
        destinationAddress = recipient;

        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        (bytes32 returnedInterchainTokenSalt, bytes32 returnedInterchainTokenId, TokenManager returnedTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF);

        // sanity asserts for post canonical registration
        assertEq(sepoliaITS.interchainTokenAddress(returnedInterchainTokenId), deployments.rwTEL);
        assertEq(address(returnedTELTokenManager), deployments.rwTELTokenManager);
        bytes32 expectedTELTokenId = sepoliaITF.canonicalInterchainTokenId(canonicalTEL);
        assertEq(expectedTELTokenId, sepoliaITS.interchainTokenId(address(0x0), returnedInterchainTokenSalt));

        // note that TN must be added as a trusted chain to the Ethereum ITS contract
        destinationChain = TN_CHAIN_NAME;
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // give gas funds to user and pre-approve ITS to spend its TEL
        vm.deal(user, gasValue);
        vm.prank(user);
        IERC20(canonicalTEL).approve(address(sepoliaITS), amount);
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        destinationAddressString = LibString.toHexString(uint256(uint160(destinationAddress)), 32);
        payload = abi.encode(
            MESSAGE_TYPE_INTERCHAIN_TRANSFER,
            returnedInterchainTokenId,
            AddressBytes.toBytes(user),
            AddressBytes.toBytes(destinationAddress),
            amount,
            ""
        );
        wrappedPayload = abi.encode(MESSAGE_TYPE_SEND_TO_HUB, destinationChain, payload);

        vm.startPrank(user);
        // user must have tokens and approve gateway
        IERC20(canonicalTEL).approve(address(sepoliaITS), amount);

        uint256 srcBalBefore = IERC20(canonicalTEL).balanceOf(user);
        uint256 destBalBefore = IERC20(canonicalTEL).balanceOf(address(returnedTELTokenManager));

        // ITS wraps `ContractCall` events with Axelar Hub info
        vm.expectEmit(true, true, true, true);
        emit ContractCall(address(sepoliaITS), ITS_HUB_CHAIN_NAME, ITS_HUB_ROUTER_ADDR, keccak256(wrappedPayload), wrappedPayload);

        sepoliaITS.interchainTransfer{ value: gasValue }(
            returnedInterchainTokenId, destinationChain, AddressBytes.toBytes(recipient), amount, "", gasValue
        );
        vm.stopPrank();

        assertEq(IERC20(canonicalTEL).balanceOf(user), srcBalBefore - amount);
        assertEq(IERC20(canonicalTEL).balanceOf(address(returnedTELTokenManager)), destBalBefore + amount);


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

        sourceAddress = address(sepoliaITS);
        sourceAddressString = LibString.toHexString(uint256(uint160(sourceAddress)), 32);
        messageId = "42";
        Message memory message = _craftITSMessage(messageId, sourceChain, sourceAddressString, destinationAddress, payload);
        messages.push(message);

        // use gatewayOperator to overwrite devnet config verifier for tests
        vm.startPrank(admin);
        (WeightedSigners memory weightedSigners, bytes32 signersHash) = _overwriteWeightedSigners(mockVerifier.addr);
        bytes32 approveMessagesHash = gateway.messageHashToSign(signersHash, keccak256(abi.encode(CommandType.ApproveMessages, messages)));
        vm.stopPrank();

        // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mockVerifier.privateKey, approveMessagesHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        Proof memory proof = Proof(weightedSigners, signatures);

        /**
         * @dev Relayer Action: Approve GMP Message on Destination Gateway
         * Includer polls GMP API for the message processed by Axelar Network verifiers, writes to TN gateway in TX
         * Once settled, GMP message has been successfully sent across chains (bridged) and awaits execution
         */
        
        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, sourceChain, messageId, sourceAddressString, destinationAddress, keccak256(payload));
        gateway.approveMessages(messages, proof);

        uint256 userBalBefore = user.balance;
        uint256 rwtelBalBefore = address(rwTEL).balance;
        assertEq(rwtelBalBefore, telTotalSupply);

        // todo: is setting this necessary
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(sourceChain, sourceAddressString);

        vm.expectEmit(true, true, true, true);
        emit MessageExecuted(commandId);
        string memory sourceITS = LibString.toHexString(uint256(uint160(address(sepoliaITS))), 32);
        its.execute(commandId, sourceChain, sourceITS, payload);

        assertTrue(
            gateway.isMessageExecuted(sourceChain, messageId)
        );

        // sepolia TEL ERC20 has been bridged and delivered to user as native TEL
        uint256 decimalConvertedAmt = rwTEL.toEighteenDecimals(amount);
        assertEq(user.balance, userBalBefore + decimalConvertedAmt);
        assertEq(address(rwTEL).balance, rwtelBalBefore - decimalConvertedAmt);
    }

    // function test_e2e_bridgeSimulation_sepoliaToTN() public {
    //         setUpForkConfig();

    //         tnFork = vm.createFork(TN_RPC_URL);
    //         vm.selectFork(tnFork);

    //         vm.deal(user, amount + 100);
    //         sourceChain = "telcoin-network";
    //         sourceAddressString = LibString.toHexString(uint256(uint160(address(tnGateway))), 20);
    //         destinationChain = "ethereum-sepolia";
    //         // Axelar Ethereum-Sepolia gateway predates AxelarExecutable contract; it contains execution logic
    //         destAddress = LibString.toHexString(uint256(uint160(address(sepoliaGateway))), 20);

    //         vm.startPrank(user);
    //         // wrap amount to wTEL and then to rwTEL, which initiates `recoverableWindow`
    //         tnWTEL.deposit{ value: amount }();
    //         tnWTEL.approve(address(tnRWTEL), amount);
    //         tnRWTEL.wrap(amount);

    //         // construct payload
    //         messageId = "42";
    //         bytes32[] memory commandIds = new bytes32[](1);
    //         bytes32 commandId = tnGateway.messageToCommandId(sourceChain, messageId);
    //         commandIds[0] = commandId;
    //         string[] memory commands = new string[](1);
    //         commands[0] = "mintToken";
    //         bytes[] memory params = new bytes[](1);
    //         bytes memory mintTokenParams = abi.encode(symbol, user, amount);
    //         params[0] = mintTokenParams;
    //         bytes memory data = abi.encode(11_155_111, commandIds, commands, params);
    //         bytes memory proof = "";
    //         payload = abi.encode(data, proof);

    //         // elapse time
    //         vm.warp(block.timestamp + recoverableWindow_);

    //         vm.expectEmit();
    //         emit ContractCall(user, destinationChain, destAddress, keccak256(payload), payload);
    //         tnGateway.callContract(destinationChain, destAddress, payload);

    //         // sepolia side
    //         sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
    //         vm.selectFork(sepoliaFork);

    //         // sepoliaGateway.execute(payload);

    //todo: token bridge test asserts
    // uint256 userBalBefore = user.balance;
    // sepolia TEL ERC20 has been bridged and delivered to user as native TEL
    // assertEq(user.balance, userBalBefore + amount); //todo: token bridge test
    // }
    //     }
}
