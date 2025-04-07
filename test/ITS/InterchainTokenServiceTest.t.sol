// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
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
import { ITokenManager } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../../src/WTEL.sol";
import { RWTEL } from "../../src/RWTEL.sol";
import { ExtCall } from "../../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "../../deployments/utils/Create3Utils.sol";
import { ITSConfig } from "../../deployments/utils/ITSConfig.sol";
import { HarnessCreate3FixedAddressForITS, MockTEL } from "./ITSTestHelper.sol";

contract InterchainTokenServiceTest is Test, ITSConfig {
    MockTEL mockTEL; // not used except to etch bytecode onto canonicalTEL

    address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;

    function setUp() public {
        mockTEL = new MockTEL();
        canonicalTEL = MAINNET_TEL;
        vm.etch(canonicalTEL, address(mockTEL).code);

        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        (address precalculatedITS, address precalculatedWTEL, address precalculatedRWTEL) = _precalculateCreate3ConstructorArgs(create3, admin);

        _setUpDevnetConfig(admin, canonicalTEL, precalculatedWTEL, precalculatedRWTEL);

        // add or overwrite configs outside of devnet setup in test context
        rwtelOwner = admin;
        chainName_ = MAINNET_CHAIN_NAME;
        canonicalChainName_ = MAINNET_CHAIN_NAME;
        itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

        // note: ITS deterministic create3 deployments depend on `sender` for devnet only
        vm.startPrank(admin);

        // rwtel impl bytecode used for tokenId in TokenHandler constructor arg
        wTEL = instantiateWTEL();
        rwTELImpl = instantiateRWTELImpl(precalculatedITS);

        canonicalInterchainTokenSalt = rwTELImpl.canonicalInterchainTokenDeploySalt();
        canonicalInterchainTokenId = rwTELImpl.interchainTokenId();
        canonicalTELTokenManager = TokenManager(rwTELImpl.tokenManagerAddress()); // TNTokenManager in forks

        // deploy ITS core suite; use config from storage
        gatewayImpl = instantiateAxelarAmplifierGatewayImpl();
        gateway = instantiateAxelarAmplifierGateway(address(gatewayImpl));
        tokenManagerDeployer = instantiateTokenManagerDeployer();
        interchainTokenImpl = instantiateInterchainTokenImpl(create3.deployedAddress("", admin, salts.itsSalt));
        itDeployer = instantiateInterchainTokenDeployer(address(interchainTokenImpl));
        tokenManagerImpl = instantiateTokenManagerImpl(create3.deployedAddress("", admin, salts.itsSalt));
        tnTokenHandler = instantiateTokenHandler(canonicalInterchainTokenId);
        gasServiceImpl = instantiateAxelarGasServiceImpl();
        gasService = instantiateAxelarGasService(address(gasServiceImpl));
        gatewayCaller = instantiateGatewayCaller(address(gateway), address(gasService));
        itsImpl = instantiateITSImpl(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            create3.deployedAddress("", admin, salts.itfSalt),
            address(tokenManagerImpl),
            address(tnTokenHandler),
            address(gatewayCaller)
        );
        its = instantiateITS(address(itsImpl));
        itFactoryImpl = instantiateITFImpl(address(its));
        itFactory = instantiateITF(address(itFactoryImpl));

        rwTEL = instantiateRWTEL(address(rwTELImpl));
        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);

        vm.stopPrank(); // `admin`

        // asserts
        assertEq(address(its), create3.deployedAddress("", admin, salts.itsSalt));
        assertEq(address(itFactory), create3.deployedAddress("", admin, salts.itfSalt));
        assertEq(canonicalInterchainTokenId, rwTEL.interchainTokenId());
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // gateway sanity tests
        assertEq(gateway.owner(), gatewayOwner);
        assertEq(gateway.implementation(), address(gatewayImpl));
        assertEq(gateway.contractId(), salts.gatewaySalt);
        assertEq(gateway.operator(), gatewayOperator);
        assertEq(gateway.previousSignersRetention(), previousSignersRetention);
        assertEq(gateway.domainSeparator(), domainSeparator);
        assertEq(gateway.minimumRotationDelay(), minimumRotationDelay);
        assertEq(gateway.epoch(), 1);
        assertEq(gateway.signersHashByEpoch(1), keccak256(abiEncodedWeightedSigners));
        assertEq(gateway.epochBySignersHash(keccak256(abiEncodedWeightedSigners)), 1);
        assertEq(gateway.lastRotationTimestamp(), block.number);
        assertEq(gateway.timeSinceRotation(), 0);

        // ITS periphery sanity tests
        assertEq(interchainTokenImpl.interchainTokenService(), address(its));
        assertEq(itDeployer.implementationAddress(), address(interchainTokenImpl));
        assertEq(tokenManagerImpl.interchainTokenService(), address(its));
        assertEq(gasService.implementation(), address(gasServiceImpl));
        assertEq(gasService.gasCollector(), gasCollector);
        assertEq(gasService.contractId(), salts.gsSalt);
        assertEq(address(gatewayCaller.gateway()), address(gateway));
        assertEq(address(gatewayCaller.gasService()), address(gasService));
        // ITS sanity tests for immutables can be checked on impl since they're set in bytecode
        assertEq(itsImpl.tokenManagerDeployer(), address(tokenManagerDeployer));
        assertEq(itsImpl.interchainTokenDeployer(), address(itDeployer));
        assertEq(address(itsImpl.gateway()), address(gateway));
        assertEq(address(itsImpl.gasService()), address(gasService));
        assertEq(itsImpl.interchainTokenFactory(), address(itFactory));
        assertEq(itsImpl.chainNameHash(), keccak256(bytes(chainName_)));
        assertEq(itsImpl.tokenManager(), address(tokenManagerImpl));
        assertEq(itsImpl.tokenHandler(), address(tnTokenHandler));
        assertEq(itsImpl.gatewayCaller(), address(gatewayCaller));
        assertEq(itsImpl.tokenManagerImplementation(0), address(tokenManagerImpl));
        // ITS proxy sanity tests
        assertEq(its.tokenManagerImplementation(0), address(tokenManagerImpl));
        assertEq(
            its.getExpressExecutor(
                bytes32(0x0), chainName_, Strings.toString(uint256(uint160(address(rwTEL)))), bytes32(0x0)
            ),
            address(0x0)
        );

        // rwTEL sanity tests
        assertEq(rwTEL.stakeManager(), 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        assertEq(address(rwTEL.interchainTokenService()), address(its));
        assertEq(rwTEL.owner(), rwtelOwner);
        assertTrue(address(rwTEL).code.length > 0);
        assertEq(rwTEL.name(), name_);
        assertEq(rwTEL.symbol(), symbol_);
        assertEq(rwTEL.recoverableWindow(), recoverableWindow_);
        assertEq(rwTEL.governanceAddress(), governanceAddress_);
        assertEq(rwTEL.baseToken(), address(wTEL));
        assertEq(rwTEL.decimals(), wTEL.decimals());
        // note that rwTEL ITS salt and tokenId are based on canonicalTEL
        bytes32 rwtelDeploySalt = rwTEL.canonicalInterchainTokenDeploySalt();
        assertEq(rwtelDeploySalt, itFactory.canonicalInterchainTokenDeploySalt(address(canonicalTEL)));
        assertEq(canonicalInterchainTokenId, rwTEL.tokenManagerCreate3Salt());
        assertEq(canonicalInterchainTokenId, itFactory.canonicalInterchainTokenId(address(canonicalTEL)));
        assertEq(canonicalInterchainTokenId, its.interchainTokenId(address(0x0), rwtelDeploySalt));
    }

    function test_eth_registerCanonicalInterchainToken() public {
        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        (bytes32 returnedInterchainTokenSalt, bytes32 returnedInterchainTokenId, TokenManager returnedTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory);

        assertEq(returnedInterchainTokenSalt, canonicalInterchainTokenSalt);
        assertEq(returnedInterchainTokenId, canonicalInterchainTokenId);
        assertEq(returnedInterchainTokenId, its.interchainTokenId(address(0x0), returnedInterchainTokenSalt));
        assertEq(address(returnedTELTokenManager), address(canonicalTELTokenManager));

        vm.expectRevert();
        returnedTELTokenManager.proposeOperatorship(admin);
        vm.expectRevert();
        returnedTELTokenManager.transferOperatorship(admin);
        vm.expectRevert();
        returnedTELTokenManager.acceptOperatorship(admin);
        vm.expectRevert();
        returnedTELTokenManager.addFlowLimiter(admin);
        vm.expectRevert();
        returnedTELTokenManager.removeFlowLimiter(admin);
        uint256 dummyAmt = 1;
        vm.expectRevert();
        returnedTELTokenManager.setFlowLimit(dummyAmt);
        vm.expectRevert();
        returnedTELTokenManager.addFlowIn(dummyAmt);
        vm.expectRevert();
        returnedTELTokenManager.addFlowOut(dummyAmt);
        vm.expectRevert();
        returnedTELTokenManager.mintToken(address(canonicalTEL), address(admin), dummyAmt);
        vm.expectRevert();
        returnedTELTokenManager.burnToken(address(canonicalTEL), address(admin), dummyAmt);

        // `BaseProxy::setup()` doesn't revert but does nothing if invoked outside of `TokenManagerProxy` constructor
        returnedTELTokenManager.setup(abi.encode(address(0), address(0x42)));
        assertFalse(returnedTELTokenManager.isOperator(address(0x42)));

        // check expected create3 address for canonicalTEL TokenManager using harness & restore
        bytes memory restoreCodeITS = address(its).code;
        vm.etch(address(its), type(HarnessCreate3FixedAddressForITS).runtimeCode);
        HarnessCreate3FixedAddressForITS itsCreate3 = HarnessCreate3FixedAddressForITS(address(its));
        // note to deploy TokenManagers ITS uses a different create3 salt schema that 'wraps' the token's canonical
        // deploy salt
        bytes32 tmDeploySaltIsTELInterchainTokenId =
            keccak256(abi.encode(keccak256("its-interchain-token-id"), address(0x0), returnedInterchainTokenSalt));
        assertEq(itsCreate3.create3Address(tmDeploySaltIsTELInterchainTokenId), address(returnedTELTokenManager));
        vm.etch(address(its), restoreCodeITS);

        // ITS asserts post registration && deployed returnedTELTokenManager
        address returnedTELTokenManagerExpected = its.tokenManagerAddress(returnedInterchainTokenId);
        assertEq(address(returnedTELTokenManager), returnedTELTokenManagerExpected);
        assertTrue(returnedTELTokenManagerExpected.code.length > 0);
        assertEq(address(its.deployedTokenManager(returnedInterchainTokenId)), address(returnedTELTokenManager));
        assertEq(its.registeredTokenAddress(returnedInterchainTokenId), canonicalTEL);

        // canonicalTEL TokenManager asserts
        assertEq(returnedTELTokenManager.contractId(), keccak256("token-manager"));
        assertEq(returnedTELTokenManager.interchainTokenId(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(returnedTELTokenManager.implementationType(), uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(returnedTELTokenManager.tokenAddress(), address(canonicalTEL));
        assertEq(returnedTELTokenManager.isOperator(address(0x0)), true);
        assertEq(returnedTELTokenManager.isOperator(address(its)), true);
        assertEq(returnedTELTokenManager.isFlowLimiter(address(its)), true);
        assertEq(returnedTELTokenManager.flowLimit(), 0); // set by ITS
        assertEq(returnedTELTokenManager.flowInAmount(), 0); // set by ITS
        assertEq(returnedTELTokenManager.flowOutAmount(), 0); // set by ITS
        bytes memory ethTMSetupParams = abi.encode(bytes(""), canonicalTEL);
        assertEq(returnedTELTokenManager.getTokenAddressFromParams(ethTMSetupParams), canonicalTEL);
        (uint256 implementationType, address tokenAddress) =
            TokenManagerProxy(payable(address(returnedTELTokenManager))).getImplementationTypeAndTokenAddress();
        assertEq(implementationType, uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(tokenAddress, canonicalTEL);

        // rwtel asserts
        assertEq(canonicalInterchainTokenId, itFactory.canonicalInterchainTokenId(canonicalTEL));
        assertEq(canonicalInterchainTokenId, tmDeploySaltIsTELInterchainTokenId);
        assertEq(rwTEL.tokenManagerCreate3Salt(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), itFactory.canonicalInterchainTokenDeploySalt(canonicalTEL));
        assertEq(rwTEL.tokenManagerAddress(), address(returnedTELTokenManager));
    }

    function test_eth_deployRemoteCanonicalInterchainToken() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        (, bytes32 returnedInterchainTokenId,) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory);

        // note that TN must be added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        // note this remote canonical interchain token step is for devnet only, obviated by testnet & mainnet genesis
        bytes32 remoteCanonicalTokenId =
            itFactory.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL, destinationChain, gasValue);

        assertEq(remoteCanonicalTokenId, returnedInterchainTokenId);
    }

    function test_eth_interchainTransfer_TEL() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        (, bytes32 returnedInterchainTokenId,) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        uint256 amount = 42;
        MockTEL(canonicalTEL).mint(address(this), amount);
        MockTEL(canonicalTEL).approve(address(its), amount);

        bytes memory destinationAddress = AddressBytes.toBytes(address(0xbeef));
        its.interchainTransfer{ value: gasValue }(
            returnedInterchainTokenId, destinationChain, destinationAddress, amount, "", gasValue
        );
    }

    function test_eth_transmitInterchainTransfer_TEL() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        (, bytes32 returnedInterchainTokenId,) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        address user = address(0x42);
        uint256 amount = 42;
        MockTEL(canonicalTEL).mint(user, amount);
        vm.prank(user);
        MockTEL(canonicalTEL).approve(address(its), amount);

        bytes memory destinationAddress = AddressBytes.toBytes(address(0xbeef));

        // note: direct calls to `ITS::transmitInterchainTransfer()` can only be called by the token
        // thus it is disabled on Ethereum since ethTEL doesn't have this function
        vm.expectRevert();
        its.transmitInterchainTransfer{ value: gasValue }(
            returnedInterchainTokenId, user, destinationChain, destinationAddress, amount, ""
        );
    }
}
