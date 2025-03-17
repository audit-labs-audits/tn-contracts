// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
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
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { Proxy } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradable/Proxy.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";

contract InterchainTokenServiceTest is Test {
    // TN contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    // Axelar ITS contracts
    Create3Deployer deployer;
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    // InterchainToken interchainToken; // InterchainProxy //todo use deployer?
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

    // shared axelar constructor params
    address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
    address deployerEOA = admin; //todo necessary?
    address precalculatedITSAddr;
    address precalculatedITF;

    // AxelarAmplifierGateway
    string axelarId = "telcoin-network"; // used as `chainName_` for ITS
    string routerAddress = "router";
    uint256 telChainId = 0x7e1;
    bytes32 domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
    uint256 previousSignersRetention = 16;
    uint256 minimumRotationDelay = 86_400; // default rotation delay is `1 day == 86400 seconds`
    uint128 weight = 1; // todo: handle additional signers
    address singleSigner = admin; // todo: increase signers
    uint128 threshold = 1; // todo: increase threshold
    bytes32 nonce = bytes32(0x0);
    // memory: weightedSignersArray = [WeightedSigners([WeightedSigner(singleSigner, weight)], threshold, nonce)];
    address gatewayOperator = admin; // todo: separate operator
    bytes gatewaySetupParams; // = abi.encode(gatewayOperator, weightedSignersArray);
    address gatewayOwner = admin; // todo: separate owner

    // AxelarGasService
    address gasCollector = address(0xc011ec106);
    address gsOwner = admin;
    bytes gsSetupParams = ""; // unused

    // InterchainTokenService
    address itsOwner = admin; // todo: separate owner
    address itsOperator = admin; // todo: separate operator
    string chainName_ = axelarId;
    string[] trustedChainNames = [axelarId];
    string[] trustedAddresses = [Strings.toString(uint256(uint160(admin)))];
    bytes itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

    // rwTEL config
    address consensusRegistry_; // currently points to TN
    address gateway_; // currently points to TN
    string symbol_ = "rwTEL";
    string name_ = "Recoverable Wrapped Telcoin";
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;
    address rwtelOwner;

    //todo: move these to Deployments.sol
    bytes32 c2dSalt = keccak256("create3-deployer");
    bytes32 gatewayImplSalt = keccak256("axelar-amplifier-gateway");
    bytes32 gatewaySalt = keccak256("axelar-amplifier-gateway-proxy");
    bytes32 tmdSalt = keccak256("token-manager-deployer");
    bytes32 itdSalt = keccak256("interchain-token-deployer");
    bytes32 tmImplSalt = keccak256("token-manager-impl");
    bytes32 tmSalt = keccak256("token-manager");
    bytes32 thSalt = keccak256("token-handler");
    bytes32 agsSalt = keccak256("axelar-gas-service");
    bytes32 gcSalt = keccak256("gateway-caller");
    bytes32 itsImplSalt = keccak256("interchain-token-service");
    bytes32 itsSalt = keccak256("interchain-token-service");
    bytes32 itfImplSalt = keccak256("interchain-token-factory");
    bytes32 itfSalt = keccak256("interchain-token-factory");
    bytes32 rwtelSalt = keccak256("rwtel");

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin; // used for all CREATE3 deployments
        wTEL = new WTEL();

        // note: CREATE3 contract deployed via `create2`
        deployer = new Create3Deployer{ salt: c2dSalt }();
        // deploy ITS contracts via `CREATE3` for predictability & stability
        (gatewayImpl, gateway) = deployAxelarAmplifierGateway(deployer, gatewayImplSalt, gatewaySalt);
        tokenManagerDeployer = TokenManagerDeployer(deploySingleton(deployer, type(TokenManagerDeployer).creationCode, '', tmdSalt));
        // ITS address has no code yet but must be precalculated for constructor args. bytecode & sender irrelevant
        // address create3Intermediary = deployer.deployedAddress(bytecode, sender, salt); //todo

        // must precalculate to avoid TokenManager::`constructor()` revert
        precalculatedITSAddr = deployer.deployedAddress("", deployerEOA, itsSalt);
        bytes memory tmConstructorArgs = abi.encode(precalculatedITSAddr);
        tokenManagerImpl = TokenManager(
            deploySingleton(deployer, type(TokenManager).creationCode, tmConstructorArgs, tmImplSalt);
        );

        //todo: deploy a tokenManager for rwTEL -- should this call go through ITS vs tdDeployer contract? adds
        // permissioning?
        // tokenManager = tokenManagerDeployer.deployTokenManager(tokenId, implementationType, params);

        bytes memory itImplConstructorArgs = abi.encode(precalculatedITSAddr);
        interchainTokenImpl = InterchainToken(deploySingleton(deployer, type(InterchainToken).creationCode, itImplConstructorArgs, itImplSalt));
        bytes memory itdConstructorArgs = abi.encode(address(interchainTokenImpl));
        itDeployer = InterchainTokenDeployer(
            deploySingleton(deployer, type(InterchainTokenDeployer).creationCode, itdConstructorArgs, itdSalt)
        );

        //todo: deploy interchainToken via deployer or via ITS?

        //todo convert to create3
        gasServiceImpl = new AxelarGasService(gasCollector); // todo: why does this emit address(0x1)?
        // gsSetupParams =  todo
        gasService = AxelarGasService(address(new Proxy(address(gasServiceImpl), gsOwner, gsSetupParams)));

        bytes memory gcConstructorArgs = abi.encode(address(gateway), address(gasService));
        gatewayCaller = deploySingleton(deployer, type(GatewayCaller).creationCode, gcConstructorArgs, gcSalt);
        tokenHandler = deploySingleton(deployer, type(TokenHandler).creationCode, '', thSalt);

        // must precalculate to avoid `ITS::constructor()` revert
        precalculatedITF = deployer.deployedAddress("", address(deployerEOA), itfImplSalt);

        //todo: use create3
        itsImpl = new InterchainTokenService(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            precalculatedITF,//address(itFactory), todo
            axelarId,
            address(tokenManagerImpl),
            address(tokenHandler),
            address(gatewayCaller)
        );

        // itsSetupParams = todo

        its = InterchainTokenService(
            deployer.deploy(
                bytes.concat(type(InterchainProxy).creationCode, abi.encode(itsOwner, itsSetupParams)),
                itsSalt
            )
        );

        // its = InterchainTokenService(address(new InterchainProxy(address(itsImpl), itsOwner, itsSetupParams)));

        assertEq(precalculatedITSAddr, address(its));

        // itFactoryImpl = new InterchainTokenFactory(address(its));

        recoverableWindow_ = 604_800; // 1 week
        governanceAddress_ = address(this); // multisig/council/DAO address in prod
        baseERC20_ = address(wTEL);
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage

        // deploy impl + proxy and initialize
        rwTELImpl = new RWTEL{ salt: rwtelSalt }(
            address(its), name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean
        );
        rwTEL = RWTEL(payable(address(new ERC1967Proxy{ salt: rwtelSalt }(address(rwTELImpl), ""))));
        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);
    }

    function deploySingleton(
        Create3Deployer create3,
        bytes memory contractCreationCode,
        bytes memory constructorArgs,
        bytes32 salt
    ) public returns (address deployment) {
        bytes memory contractInitCode = bytes.concat(
            contractCreationCode,
            constructorArgs
        );
        return create3.deploy(contractInitCode, salt);
    }

    function deployAxelarAmplifierGateway(
        Create3Deployer create3,
        bytes32 implSalt,
        bytes32 proxySalt
    )
        public
        returns (AxelarAmplifierGateway, AxelarAmplifierGateway)
    {
        // construct contract init code for gateway impl
        bytes memory gatewayImplInitcode = bytes.concat(
            type(AxelarAmplifierGateway).creationCode,
            abi.encode(previousSignersRetention, domainSeparator, minimumRotationDelay)
        );

        gatewayImpl = AxelarAmplifierGateway(create3.deploy(gatewayImplInitcode, gatewayImplSalt));

        // must be done in memory since structs can't be written to storage in Solidity
        WeightedSigner[] memory signerArray = new WeightedSigner[](1);
        signerArray[0] = WeightedSigner(singleSigner, weight);
        WeightedSigners memory weightedSigners = WeightedSigners(signerArray, threshold, nonce);
        WeightedSigners[] memory weightedSignersArray = new WeightedSigners[](1);
        weightedSignersArray[0] = weightedSigners;
        // construct contract init code for gateway proxy
        gatewaySetupParams = abi.encode(gatewayOperator, weightedSignersArray);
        bytes memory gatewayProxyInitcode = bytes.concat(
            type(AxelarAmplifierGatewayProxy).creationCode,
            abi.encode(address(gatewayImpl), gatewayOwner, gatewaySetupParams)
        );

        gateway = AxelarAmplifierGateway(create3.deploy(gatewayProxyInitcode, proxySalt));

        return (gatewayImpl, gateway);
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // ITS sanity tests

        // rwTEL sanity tests
        assertEq(rwTEL.consensusRegistry(), deployments.ConsensusRegistry);
        assertEq(address(rwTEL.interchainTokenService()), deployments.InterchainTokenService);
        assertEq(rwTEL.owner(), rwtelOwner);
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

    // todo: move to separate file

    // for fork tests
    Deployments deployments;

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    // todo: using duplicate gateway until Axelar registers TEL to canonical gateway
    IAxelarGateway sepoliaGateway;
    IERC20 sepoliaTel;
    AxelarAmplifierGateway tnGateway;
    WTEL tnWTEL;
    RWTEL tnRWTEL;

    address user;
    string sourceChain;
    string sourceAddress;
    string destChain;
    string destAddress;
    string symbol;
    uint256 amount;
    bytes extCallData;
    bytes payload;
    bytes32 payloadHash;
    string messageId;
    Message[] messages;

    function setUpForkConfig() internal {
        // todo: currently replica; change to canonical Axelar sepolia gateway
        sepoliaGateway = IAxelarGateway(0xB906fC799C9E51f1231f37B867eEd1d9C5a6D472);
        sepoliaTel = IERC20(deployments.sepoliaTEL);
        tnGateway = AxelarAmplifierGateway(deployments.AxelarAmplifierGateway);
        tnWTEL = WTEL(payable(deployments.wTEL));
        tnRWTEL = RWTEL(payable(deployments.rwTEL));

        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
        symbol = "TEL";
        amount = 100; // 1 tel

        //todo: deploy ITS contracts for fork testing
    }

    function test_bridgeSimulationSepoliaToTN() public {
        //todo
    }
}
