/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Create3AddressFixed } from "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { InterchainTokenService } from "../../deployments/Deployments.sol";
import { ITSUtilsFork } from "../../deployments/utils/ITSUtilsFork.sol";

abstract contract ITSTestHelper is Test, ITSUtilsFork {
    //todo: inherit StorageDiffRecorder, add bytecode etching, storage writing, TEL seeding

    /// TODO: Until testnet is restarted with genesis precompiles, this function deploys ITS via create3
    /// @notice For devnet, a developer admin address serves all permissioned roles
    function _setUp_tnFork_devnetConfig_create3(uint256 tnFork, address admin, address canonicalTEL, address wtel) internal {
        vm.selectFork(tnFork);

        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        // ITS address must be derived w/ sender + salt pre-deploy, for TokenManager && InterchainToken constructors
        address expectedITS = create3.deployedAddress("", admin, salts.itsSalt);
        // must precalculate ITF proxy to avoid `ITS::constructor()` revert
        address expectedITF = create3.deployedAddress("", admin, salts.itfSalt);
        _setUpDevnetConfig(admin, canonicalTEL, wtel, expectedITS, expectedITF);

        vm.startPrank(admin);
        gatewayImpl = create3DeployAxelarAmplifierGatewayImpl();
        gateway = create3DeployAxelarAmplifierGateway(address(gatewayImpl));
        tokenManagerDeployer = create3DeployTokenManagerDeployer();
        interchainTokenImpl = create3DeployInterchainTokenImpl();
        itDeployer = create3DeployInterchainTokenDeployer(address(interchainTokenImpl));
        tokenManagerImpl = create3DeployTokenManagerImpl();
        tokenHandler = create3DeployTokenHandler();
        gasServiceImpl = create3DeployAxelarGasServiceImpl();
        gasService = create3DeployAxelarGasService(address(gasServiceImpl));
        gatewayCaller = create3DeployGatewayCaller(address(gateway), address(gasService));
        itsImpl = create3DeployITSImpl(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            address(tokenManagerImpl),
            address(tokenHandler),
            address(gatewayCaller)
        );
        its = create3DeployITS(address(itsImpl));
        itFactoryImpl = create3DeployITFImpl(address(its));
        itFactory = create3DeployITF(address(itFactoryImpl));
        rwTELImpl = create3DeployRWTELImpl(address(its));
        rwTEL = create3DeployRWTEL(address(rwTELImpl));

        rwtelOwner = admin;
        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);
        // mock-seed rwTEL with TEL total supply as genesis precompile
        uint256 nativeTELTotalSupply = 100_000_000_000e18;
        vm.deal(address(rwTEL), nativeTELTotalSupply);

        vm.stopPrank();

        assertEq(address(its), precalculatedITS);
        assertEq(address(itFactory), precalculatedITFactory);
    }

    
    function setUp_tnFork_devnetConfig_genesis(uint256 tnFork, address admin, address canonicalTEL, address wtel) internal {
        // todo: remove this line and uncomment section below after testnet restart with genesis precompiles
        _setUp_tnFork_devnetConfig_create3(tnFork, admin, canonicalTEL, wtel);

        // gatewayImpl = AxelarAmplifierGateway(deployments.its.AxelarAmplifierGatewayImpl);
        // gateway = AxelarAmplifierGateway(deployments.its.AxelarAmplifierGateway);
        // tokenManagerDeployer = TokenManagerDeployer(deployments.its.TokenManagerDeployer);
        // interchainTokenImpl = InterchainToken(deployments.its.InterchainTokenImpl);
        // itDeployer = InterchainTokenDeployer(deployments.its.InterchainTokenDeployer);
        // tokenManagerImpl = TokenManager(deployments.its.TokenManagerImpl);
        // tokenHandler = TokenHandler(deployments.its.TokenHandler);
        // gasServiceImpl = AxelarGasService(deployments.its.GasServiceImpl);
        // gasService = AxelarGasService(deployments.its.GasService);
        // gatewayCaller = GatewayCaller(deployments.its.GatewayCaller);
        // itsImpl = InterchainTokenService(deployments.its.InterchainTokenServiceImpl);
        // its = InterchainTokenService(deployments.its.InterchainTokenService);
        // itFactoryImpl = InterchainTokenFactory(deployments.its.InterchainTokenFactoryImpl);
        // itFactory = InterchainTokenFactory(deployments.its.InterchainTokenFactory);
        // rwTELImpl = RWTEL(deployments.rwTELImpl);
        // rwTEL = RWTEL(deployments.rwTEL);
    }

    /// @notice Redeclared event from `IAxelarGMPGateway` for asserts
    event ContractCall(
        address indexed sender,
        string destinationChain,
        string destinationContractAddress,
        bytes32 indexed payloadHash,
        bytes payload
    );
    
    /// @notice Redeclared event from `BaseAmplifierGateway` for asserts
    event MessageApproved(
        bytes32 indexed commandId,
        string sourceChain,
        string messageId,
        string sourceAddress,
        address indexed contractAddress,
        bytes32 indexed payloadHash
    );

    /// @notice Redeclared event from `BaseAmplifierGateway` for asserts
    event MessageExecuted(bytes32 indexed commandId);
}

contract HarnessCreate3FixedAddressForITS is Create3AddressFixed {
    function create3Address(bytes32 deploySalt) public view returns (address) {
        return _create3Address(deploySalt);
    }
}

/// @dev Read by ITS for metadata registration and used for tests
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

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
