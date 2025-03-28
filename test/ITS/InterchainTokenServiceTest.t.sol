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
import { Create3Utils, Salts, ImplSalts } from "../../deployments/Create3Utils.sol";
import { ITSConfig } from "./utils/ITSConfig.sol";
import { HarnessCreate3FixedAddressForITS, MockTEL } from "./ITSMocks.sol";

contract InterchainTokenServiceTest is Test, Create3Utils, ITSConfig {
    // TN contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    // "Ethereum" config (no forking done here but config stands)
    MockTEL mockTEL; // not used except to etch bytecode onto canonicalTEL
    address ethereumTEL = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F; // todo: deployments.ethereumTEL
    // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
    bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
    bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL TokenManagers
    TokenManager canonicalTELTokenManager;

    // Axelar ITS core contracts
    Create3Deployer create3;
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy

    address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
    address deployerEOA = admin; // only used for devnet
    address rwtelOwner = admin; // devnet only, no owner for mainnet
    
    function setUp() public {
        // AxelarAmplifierGateway
        axelarId = TN_CHAIN_NAME;
        routerAddress = "router"; //todo: devnet router
        telChainId = 0x7e1;
        domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
        previousSignersRetention = 16; // todo: 16 signers seems high; 0 means only current signers valid (security)
        minimumRotationDelay = 86_400; // todo: default rotation delay is `1 day == 86400 seconds`
        weight = 1; // todo: for testnet handle additional signers
        singleSigner = admin; // todo: for testnet increase signers
        threshold = 1; // todo: for testnet increase threshold
        nonce = bytes32(0x0);
        /// note: weightedSignersArray = [WeightedSigners([WeightedSigner(singleSigner, weight)], threshold, nonce)];
        gatewayOperator = admin; // todo: separate operator
        gatewaySetupParams;
        /// note: = abi.encode(gatewayOperator, weightedSignersArray);
        gatewayOwner = admin; // todo: separate owner

        // AxelarGasService
        gasCollector = address(0xc011ec106); // todo: gas sponsorship key
        gsOwner = admin;
        gsSetupParams = ""; // note: unused

        // "Ethereum" InterchainTokenService
        itsOwner = admin; // todo: separate owner
        itsOperator = admin; // todo: separate operator
        chainName_ = MAINNET_CHAIN_NAME; //todo: TN_CHAIN_NAME;
        trustedChainNames.push(ITS_HUB_CHAIN_NAME); // leverage ITS hub to support remote chains
        trustedAddresses.push(ITS_HUB_ROUTING_IDENTIFIER);
        itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

        // InterchainTokenFactory
        itfOwner = admin; // todo: separate owner

        // rwTEL config
        canonicalTEL = ethereumTEL;
        canonicalChainName_ = MAINNET_CHAIN_NAME;
        consensusRegistry_ = 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1; // TN system contract
        symbol_ = "rwTEL";
        name_ = "Recoverable Wrapped Telcoin";
        recoverableWindow_ = 604_800; // todo: confirm 1 week
        governanceAddress_ = address(0xda0); // todo: multisig/council/DAO address in prod
        baseERC20_; // wTEL
        maxToClean = type(uint16).max; // todo: revisit gas expectations; clear all relevant storage?

        mockTEL = new MockTEL();
        vm.etch(canonicalTEL, address(mockTEL).code);

        wTEL = new WTEL();

        // note: devnet only: CREATE3 contract deployed via `create2`
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        // note: ITS deterministic create3 deployments depend on `sender` for devnet only
        vm.startPrank(deployerEOA);

        // deploy gateway impl
        bytes memory gatewayImplConstructorArgs =
            abi.encode(previousSignersRetention, domainSeparator, minimumRotationDelay);
        gatewayImpl = AxelarAmplifierGateway(
            create3Deploy(
                create3,
                type(AxelarAmplifierGateway).creationCode,
                gatewayImplConstructorArgs,
                implSalts.gatewayImplSalt
            )
        );

        // struct population for gateway constructor done in memory since storage structs don't work in Solidity
        WeightedSigner[] memory signerArray = new WeightedSigner[](1);
        signerArray[0] = WeightedSigner(singleSigner, weight);
        WeightedSigners memory weightedSigners = WeightedSigners(signerArray, threshold, nonce);
        WeightedSigners[] memory weightedSignersArray = new WeightedSigners[](1);
        weightedSignersArray[0] = weightedSigners;
        gatewaySetupParams = abi.encode(gatewayOperator, weightedSignersArray);
        bytes memory gatewayConstructorArgs = abi.encode(address(gatewayImpl), gatewayOwner, gatewaySetupParams);
        gateway = AxelarAmplifierGateway(
            create3Deploy(
                create3, type(AxelarAmplifierGatewayProxy).creationCode, gatewayConstructorArgs, salts.gatewaySalt
            )
        );

        tokenManagerDeployer =
            TokenManagerDeployer(create3Deploy(create3, type(TokenManagerDeployer).creationCode, "", salts.tmdSalt));

        // ITS address has no code yet but must be precalculated for TokenManager && InterchainToken constructors using
        // correct sender & salt
        precalculatedITS = create3.deployedAddress("", deployerEOA, salts.itsSalt);
        bytes memory itImplConstructorArgs = abi.encode(precalculatedITS);
        interchainTokenImpl = InterchainToken(
            create3Deploy(create3, type(InterchainToken).creationCode, itImplConstructorArgs, implSalts.itImplSalt)
        );

        bytes memory itdConstructorArgs = abi.encode(address(interchainTokenImpl));
        itDeployer = InterchainTokenDeployer(
            create3Deploy(create3, type(InterchainTokenDeployer).creationCode, itdConstructorArgs, salts.itdSalt)
        );

        bytes memory tmConstructorArgs = abi.encode(precalculatedITS);
        tokenManagerImpl = TokenManager(
            create3Deploy(create3, type(TokenManager).creationCode, tmConstructorArgs, implSalts.tmImplSalt)
        );

        tokenHandler = TokenHandler(create3Deploy(create3, type(TokenHandler).creationCode, "", salts.thSalt));

        bytes memory gsImplConstructorArgs = abi.encode(gasCollector);
        gasServiceImpl = AxelarGasService(
            create3Deploy(create3, type(AxelarGasService).creationCode, gsImplConstructorArgs, implSalts.gsImplSalt)
        );
        bytes memory gsConstructorArgs = abi.encode(address(gasServiceImpl), gsOwner, "");
        gasService = AxelarGasService(
            create3Deploy(create3, type(AxelarGasServiceProxy).creationCode, gsConstructorArgs, salts.gsSalt)
        );

        bytes memory gcConstructorArgs = abi.encode(address(gateway), address(gasService));
        gatewayCaller =
            GatewayCaller(create3Deploy(create3, type(GatewayCaller).creationCode, gcConstructorArgs, salts.gcSalt));

        // must precalculate ITF proxy to avoid `ITS::constructor()` revert
        precalculatedITFactory = create3.deployedAddress("", address(deployerEOA), salts.itfSalt);
        bytes memory itsImplConstructorArgs = abi.encode(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            precalculatedITFactory,
            chainName_,
            address(tokenManagerImpl),
            address(tokenHandler),
            address(gatewayCaller)
        );
        itsImpl = InterchainTokenService(
            create3Deploy(
                create3, type(InterchainTokenService).creationCode, itsImplConstructorArgs, implSalts.itsImplSalt
            )
        );

        bytes memory itsConstructorArgs = abi.encode(address(itsImpl), itsOwner, itsSetupParams);
        its = InterchainTokenService(
            create3Deploy(create3, type(InterchainProxy).creationCode, itsConstructorArgs, salts.itsSalt)
        );

        bytes memory itfImplConstructorArgs = abi.encode(address(its));
        itFactoryImpl = InterchainTokenFactory(
            create3Deploy(
                create3, type(InterchainTokenFactory).creationCode, itfImplConstructorArgs, implSalts.itfImplSalt
            )
        );
        bytes memory itfConstructorArgs = abi.encode(address(itFactoryImpl), itfOwner, "");
        itFactory = InterchainTokenFactory(
            create3Deploy(create3, type(InterchainProxy).creationCode, itfConstructorArgs, salts.itfSalt)
        );

        baseERC20_ = address(wTEL);
        bytes memory rwTELImplConstructorArgs = abi.encode(
            canonicalTEL,
            canonicalChainName_,
            address(its),
            name_,
            symbol_,
            recoverableWindow_,
            governanceAddress_,
            baseERC20_,
            maxToClean
        );
        rwTELImpl = RWTEL(
            payable(create3Deploy(create3, type(RWTEL).creationCode, rwTELImplConstructorArgs, implSalts.rwtelImplSalt))
        );

        bytes memory rwTELConstructorArgs = abi.encode(address(rwTELImpl), "");
        rwTEL = RWTEL(
            payable(create3Deploy(create3, type(ERC1967Proxy).creationCode, rwTELConstructorArgs, salts.rwtelSalt))
        );

        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);

        vm.stopPrank(); // `deployerEOA`

        // current & future asserts
        assertEq(precalculatedITS, address(its));
        assertEq(precalculatedITFactory, address(itFactory));
        abiEncodedWeightedSigners = abi.encode(weightedSigners);
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
        assertEq(itsImpl.tokenHandler(), address(tokenHandler));
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
        assertEq(rwTEL.consensusRegistry(), consensusRegistry_);
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
        bytes32 rwtelTokenId = rwTEL.interchainTokenId();
        assertEq(rwtelTokenId, rwTEL.tokenManagerCreate3Salt());
        assertEq(rwtelTokenId, itFactory.canonicalInterchainTokenId(address(canonicalTEL)));
        assertEq(rwtelTokenId, its.interchainTokenId(address(0x0), rwtelDeploySalt));
    }

    /// @dev Test the flow for registering a token with ITS hub + deploying its manager
    /// @notice In prod, these calls must be performed on Ethereum prior to TN genesis
    function test_eth_registerCanonicalInterchainToken() public {
        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (canonicalInterchainSalt, canonicalInterchainTokenId, canonicalTELTokenManager) = eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

        vm.expectRevert();
        canonicalTELTokenManager.proposeOperatorship(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.transferOperatorship(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.acceptOperatorship(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowLimiter(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.removeFlowLimiter(deployerEOA);
        uint256 dummyAmt = 1;
        vm.expectRevert();
        canonicalTELTokenManager.setFlowLimit(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowIn(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowOut(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.mintToken(address(canonicalTEL), address(deployerEOA), dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.burnToken(address(canonicalTEL), address(deployerEOA), dummyAmt);

        // `BaseProxy::setup()` doesn't revert but does nothing if invoked outside of `TokenManagerProxy` constructor
        canonicalTELTokenManager.setup(abi.encode(address(0), address(0x42)));
        assertFalse(canonicalTELTokenManager.isOperator(address(0x42)));

        // check expected create3 address for canonicalTEL TokenManager using harness & restore
        bytes memory restoreCodeITS = address(its).code;
        vm.etch(address(its), type(HarnessCreate3FixedAddressForITS).runtimeCode);
        HarnessCreate3FixedAddressForITS itsCreate3 = HarnessCreate3FixedAddressForITS(address(its));
        // note to deploy TokenManagers ITS uses a different create3 salt schema that 'wraps' the token's canonical
        // deploy salt
        bytes32 tmDeploySaltIsTELInterchainTokenId =
            keccak256(abi.encode(keccak256("its-interchain-token-id"), address(0x0), canonicalInterchainSalt));
        assertEq(itsCreate3.create3Address(tmDeploySaltIsTELInterchainTokenId), address(canonicalTELTokenManager));
        vm.etch(address(its), restoreCodeITS);

        // ITS asserts post registration && deployed canonicalTELTokenManager
        address canonicalTELTokenManagerExpected = its.tokenManagerAddress(canonicalInterchainTokenId);
        assertEq(address(canonicalTELTokenManager), canonicalTELTokenManagerExpected);
        assertTrue(canonicalTELTokenManagerExpected.code.length > 0);
        assertEq(address(its.deployedTokenManager(canonicalInterchainTokenId)), address(canonicalTELTokenManager));
        assertEq(its.registeredTokenAddress(canonicalInterchainTokenId), canonicalTEL);

        // canonicalTEL TokenManager asserts
        assertEq(canonicalTELTokenManager.contractId(), keccak256("token-manager"));
        assertEq(canonicalTELTokenManager.interchainTokenId(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(canonicalTELTokenManager.implementationType(), uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(canonicalTELTokenManager.tokenAddress(), address(canonicalTEL));
        assertEq(canonicalTELTokenManager.isOperator(address(0x0)), true);
        assertEq(canonicalTELTokenManager.isOperator(address(its)), true);
        assertEq(canonicalTELTokenManager.isFlowLimiter(address(its)), true);
        assertEq(canonicalTELTokenManager.flowLimit(), 0); // set by ITS
        assertEq(canonicalTELTokenManager.flowInAmount(), 0); // set by ITS
        assertEq(canonicalTELTokenManager.flowOutAmount(), 0); // set by ITS
        bytes memory ethTMSetupParams = abi.encode(bytes(""), canonicalTEL);
        assertEq(canonicalTELTokenManager.getTokenAddressFromParams(ethTMSetupParams), canonicalTEL);

        // rwtel asserts
        bytes32 rwtelTokenId = rwTEL.interchainTokenId();
        assertEq(rwtelTokenId, its.interchainTokenId(address(0x0), canonicalInterchainSalt));
        assertEq(rwtelTokenId, canonicalInterchainTokenId);
        assertEq(rwtelTokenId, tmDeploySaltIsTELInterchainTokenId);
        assertEq(rwTEL.tokenManagerCreate3Salt(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), canonicalInterchainSalt);
    }

    /// @notice `deployRemoteCanonicalInterchainToken` will route a `MESSAGE_TYPE_LINK_TOKEN` through ITS hub
    /// that is guaranteed to revert deployment to genesis contracts; skip this step for testnet & mainnet
    function test_eth_deployRemoteCanonicalInterchainToken() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) = eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        // note this remote canonical interchain token step is for devnet only, obviated by testnet & mainnet genesis
        bytes32 remoteCanonicalTokenId =
            itFactory.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL, destinationChain, gasValue);

        /// @dev for devnet, relayer will forward link msg to TN thru ITS hub & use it to deploy rwtel tokenmanager

        assertEq(remoteCanonicalTokenId, canonicalInterchainTokenId);
    }

    function test_eth_interchainTransfer_TEL() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) = eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        uint256 amount = 42;
        MockTEL(canonicalTEL).mint(address(this), amount);
        MockTEL(canonicalTEL).approve(address(its), amount);

        bytes memory destinationAddress = AddressBytes.toBytes(address(0xbeef));
        its.interchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, destinationChain, destinationAddress, amount, "", gasValue
        );
    }

    function test_eth_transmitInterchainTransfer_TEL() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) = eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

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
            canonicalInterchainTokenId, user, destinationChain, destinationAddress, amount, ""
        );
    }
}
