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
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "../deployments/Create3Utils.sol";

contract InterchainTokenServiceTest is Test, Create3Utils {
    // TN contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    // "Ethereum" contracts
    MockTEL mockTEL; // not used except to etch bytecode onto ethTEL 
    address ethTEL = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;

    // Axelar ITS contracts
    Create3Deployer create3;
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    // InterchainToken interchainToken; // InterchainProxy //todo use deployer? salt?
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenManager tokenManager;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy

    // shared params
    string ITS_HUB_CHAIN_NAME = "axelar";
    string ITS_HUB_ROUTING_IDENTIFIER = "hub";
    string DEVNET_SEPOLIA_CHAIN_NAME = "eth-sepolia";
    bytes32 DEVNET_SEPOLIA_CHAINNAMEHASH = 0x24f78f6b35533491ef3d467d5e8306033cca94049b9b76db747dfc786df43f86;
    address DEVNET_SEPOLIA_ITS = 0x2269B93c8D8D4AfcE9786d2940F5Fcd4386Db7ff;
    //todo move to fork test
    string TESTNET_CHAIN_NAME = "ethereum-sepolia";
    bytes32 TESTNET_CHAINNAMEHASH = 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2;
    address TESTNET_ITS = 0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C;
    string MAINNET_CHAIN_NAME = "Ethereum";
    bytes32 MAINNET_CHAINNAMEHASH = 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2;
    address MAINNET_ITS = 0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C;

    address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
    address deployerEOA = admin; //todo: separate deployer
    address tmOperator = admin; //todo: should ethTEL tm have operator / should rwTEL tm have operator?

    // stored assertion vars
    address precalculatedITS;
    address precalculatedITFactory;
    bytes abiEncodedWeightedSigners;

    // AxelarAmplifierGateway
    string axelarId = "telcoin-network"; // used as `chainName_` for ITS
    string routerAddress = "router"; //todo: devnet router
    uint256 telChainId = 0x7e1;
    bytes32 domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
    uint256 previousSignersRetention = 16; // todo: 16 signers seems high; 0 means only current signers valid (security)
    uint256 minimumRotationDelay = 86_400; // todo: default rotation delay is `1 day == 86400 seconds`
    uint128 weight = 1; // todo: for testnet handle additional signers
    address singleSigner = admin; // todo: for testnet increase signers
    uint128 threshold = 1; // todo: for testnet increase threshold
    bytes32 nonce = bytes32(0x0);
    /// note: weightedSignersArray = [WeightedSigners([WeightedSigner(singleSigner, weight)], threshold, nonce)];
    address gatewayOperator = admin; // todo: separate operator
    bytes gatewaySetupParams;
    /// note: = abi.encode(gatewayOperator, weightedSignersArray);
    address gatewayOwner = admin; // todo: separate owner

    // AxelarGasService
    address gasCollector = address(0xc011ec106); // todo: gas sponsorship key
    address gsOwner = admin;
    bytes gsSetupParams = ""; // note: unused

    // InterchainTokenService
    address itsOwner = admin; // todo: separate owner
    address itsOperator = admin; // todo: separate operator
    string chainName_ = axelarId;
    string[] trustedChainNames = [ // declares supported remote chains
        ITS_HUB_CHAIN_NAME, // todo: use if possible, might require eth::TEL wrapper
        DEVNET_SEPOLIA_CHAIN_NAME
        // todo: move to fork test
        // TESTNET_CHAIN_NAME,
        // MAINNET_CHAIN_NAME
    ];
    string[] trustedAddresses = [ // ITS hubs on supported chains (arbitrary execution privileges)
        ITS_HUB_ROUTING_IDENTIFIER, // todo: use if possible, might require eth::TEL wrapper
        Strings.toString(uint256(uint160(DEVNET_SEPOLIA_ITS)))
        //todo: move to fork test
        // Strings.toString(uint256(uint160(TESTNET_SEPOLIA_ITS)))
        // Strings.toString(uint256(uint160(MAINNET_ITS)))
    ];
    bytes itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

    // InterchainTokenFactory
    address itfOwner = admin; // todo: separate owner

    // rwTEL config
    address consensusRegistry_ = 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1; // TN system contract
    address gateway_; // TN gateway will be deployed
    string symbol_ = "rwTEL";
    string name_ = "Recoverable Wrapped Telcoin";
    uint256 recoverableWindow_ = 604_800; // todo: confirm 1 week
    address governanceAddress_ = address(0xda0); // todo: multisig/council/DAO address in prod
    address baseERC20_; // wTEL
    uint16 maxToClean = type(uint16).max; // todo: revisit gas expectations; clear all relevant storage?
    address rwtelOwner = admin; //todo: upgradable via owner for testnet only, no owner for mainnet

    function setUp() public {
        mockTEL = new MockTEL();
        vm.etch(ethTEL, address(mockTEL).code);

        wTEL = new WTEL();

        // note: CREATE3 contract deployed via `create2`
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();

        // note: ITS contracts deployed via `CREATE3` depend on `sender` address for determinism
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
        bytes memory rwTELImplConstructorArgs =
            abi.encode(address(its), name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean);
        rwTELImpl = RWTEL(
            payable(create3Deploy(create3, type(RWTEL).creationCode, rwTELImplConstructorArgs, implSalts.rwtelImplSalt))
        );

        // todo: ERC1967Proxy vs InterchainProxy?
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

        // ITS sanity tests
        assertEq(interchainTokenImpl.interchainTokenService(), address(its));
        assertEq(itDeployer.implementationAddress(), address(interchainTokenImpl));
        assertEq(tokenManagerImpl.interchainTokenService(), address(its));
        assertEq(gasService.implementation(), address(gasServiceImpl));
        assertEq(gasService.gasCollector(), gasCollector);
        assertEq(gasService.contractId(), salts.gsSalt);
        assertEq(address(gatewayCaller.gateway()), address(gateway));
        assertEq(address(gatewayCaller.gasService()), address(gasService));
        // immutables set in bytecode can be checked on impl
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
        assertEq(its.tokenManagerImplementation(0), address(tokenManagerImpl));
        // assertEq(its.getExpressExecutor(commandId, sourceChain, sourceAddress,
        // payloadHash),address(expressExecutor));

        // //todo: RWTEL as InterchainToken asserts
        // assertEq(interchainToken.interchainTokenService(), address(its));
        // assertTrue(interchainToken.isMinter(address(its)));
        // assertEq(interchainToken.totalSupply(), totalSupply);
        // assertEq(interchainToken.balanceOf(address(rwTEL)), bal);
        // assertEq(interchainToken.nameHash(), nameHash);
        // assertEq(interchainToken.DOMAIN_SEPARATOR(), itDomainSeparator);

        // todo: update for protocol integration, genesis on rust side
        // rwTEL sanity tests
        assertEq(rwTEL.consensusRegistry(), consensusRegistry_);
        assertEq(address(rwTEL.interchainTokenService()), address(its));
        // assertEq(rwTEL.tokenManager(), rwtelTokenManager);
        assertEq(rwTEL.owner(), rwtelOwner);
        assertTrue(address(rwTEL).code.length > 0);
        // assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), );
        // assertEq(rwTEL.canonicalInterchainTokenId(), );
        assertEq(rwTEL.name(), name_);
        assertEq(rwTEL.symbol(), symbol_);
        assertEq(rwTEL.recoverableWindow(), recoverableWindow_);
        assertEq(rwTEL.governanceAddress(), governanceAddress_);
        assertEq(rwTEL.baseToken(), address(wTEL));
        assertEq(rwTEL.decimals(), wTEL.decimals());
    }

    /// @dev Test the flow for registering a token with ITS hub + deploying its manager
    function test_deploy_ethTokenManager() public {
        /// @notice In prod, these calls must be performed on Ethereum by multisig prior to TN genesis
        uint256 gasValue = 100; //todo gas
        vm.deal(deployerEOA, gasValue * 2);
        vm.startPrank(deployerEOA); //todo: this should be done by a multisig
        
        // Register RWTEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        its.registerTokenMetadata{ value: gasValue }(ethTEL, gasValue);

        bytes32 canonicalInterchainSalt = itFactory.canonicalInterchainTokenDeploySalt(ethTEL);
        bytes32 canonicalInterchainTokenId = itFactory.registerCanonicalInterchainToken(ethTEL);

        assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), canonicalInterchainSalt);
        assertEq(rwTEL.canonicalInterchainTokenId(), canonicalInterchainTokenId);

        console2.logString("ITS linked token deploy salt for rwTEL:");
        console2.logBytes32(canonicalInterchainSalt);
        console2.logString("ITS canonical interchain token ID for rwTEL:");
        console2.logBytes32(canonicalInterchainTokenId);

        /// @dev Ethereum relayer detects ContractCall event and forwards to GMP API for hub inclusion on Axelar Network
        /// @dev Once registered with ITS Hub, `msg.sender` can use same salt to register and `linkToken()` on more chains

        TokenManager ethTELTokenManager = TokenManager(address(its.deployedTokenManager(canonicalInterchainTokenId)));

        vm.stopPrank();

        // ITS asserts post registration && deployed ethTELTokenManager
        assertEq(address(its.deployedTokenManager(canonicalInterchainTokenId)), address(ethTELTokenManager));
        assertEq(its.tokenManagerAddress(canonicalInterchainTokenId), address(ethTELTokenManager));
        assertEq(its.registeredTokenAddress(canonicalInterchainTokenId), ethTEL);

        // ethTEL TokenManager asserts
        ITokenManagerType.TokenManagerType tmType = ITokenManagerType.TokenManagerType.LOCK_UNLOCK;
        bytes memory ethTMConstructorArgs = abi.encode(address(its), tmType, canonicalInterchainTokenId, abi.encode('', address(ethTEL)));
        address ethTokenManagerExpected = create3Address(create3, type(TokenManagerProxy).creationCode, ethTMConstructorArgs, deployerEOA, canonicalInterchainSalt);
        assertEq(address(ethTELTokenManager), ethTokenManagerExpected);
        assertEq(ethTELTokenManager.isOperator(address(0x0)), true);
        assertEq(ethTELTokenManager.isOperator(address(its)), true);
        assertEq(ethTELTokenManager.isFlowLimiter(address(its)), true);
        assertEq(ethTELTokenManager.flowLimit(), 0); // set by ITS
        assertEq(ethTELTokenManager.flowInAmount(), 0); // set by ITS
        assertEq(ethTELTokenManager.flowOutAmount(), 0); // set by ITS
        bytes memory ethTMSetupParams = abi.encode(bytes(''), ethTEL);
        assertEq(ethTELTokenManager.getTokenAddressFromParams(ethTMSetupParams), ethTEL);
    }



    // its.contractCallValue(); // todo: decimals handling?

    // function test_giveToken_TEL() public {
    //    tokenhandler.giveToken()
    // }
    // function test_takeToken_TEL() public {}
    //    tokenhandler.takeToken()
    // }

    //todo: ITS genesis deploy config
    //todo: rwTEL genesis deploy config 
    //todo: fuzz tests for rwTEL, TEL bridging
    //todo: fork tests for TEL bridging
    //todo: incorporate RWTEL contracts to TN protocol on rust side

    //todo: update readme, npm instructions
    //todo: ERC20 bridging tests
}

/// @dev Read by ITS for metadata registration
contract MockTEL is ERC20 {
    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    function name() public view virtual override returns (string memory) {
        return "Mock Telcoin";
    }

     function symbol() public view virtual override returns (string memory) {
        return "mockTEL";
     }
}