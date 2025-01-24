    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockPlugin } from "./TANIssuanceHistoryTest.t.sol";
import "../../src/issuance/TANIssuanceHistory.sol";
import "../../src/interfaces/ISimplePlugin.sol";

contract TANIssuanceIntegrationTest is Test {
    MockTel public tel;
    MockStakingModule public stakingModule;
    ISimplePlugin public plugin;
    MockAmirX public amirX;
    TANIssuanceHistory public tanIssuanceHistory;

    // Addresses for testing
    address public owner = address(0x123);
    address public defiAgg = address(0x456);
    address public executor = address(0x789);
    address public user = address(0xabc);
    address public referrer = address(0xdef);

    function setUp() public {
        // Deploy mocks
        tel = new MockTel("mockTEL", "TEL");
        stakingModule = new MockStakingModule();
        plugin = ISimplePlugin(address(new MockPlugin()));
        // the mock amirX is owned by the executor address for simplicity
        amirX = new MockAmirX(IERC20(address(tel)), executor, defiAgg);

        // (unprotected) mint tokens to `defiAgg` and give unlimited approval to `amirX`
        tel.mint(defiAgg, 1_000_000);
        vm.prank(defiAgg);
        tel.approve(address(amirX), 1_000_000);

        // Deploy the TANIssuanceHistory contract
        tanIssuanceHistory = new TANIssuanceHistory(plugin, owner);
    }

    function testIntegrationTANIssuanceHistory() public {
        // first stake for incentive eligibility
        vm.prank(user);
        stakingModule.stake(100);

        // perform swap, initiating user fee transfer
        uint256 amount = 10;
        MockAmirX.DefiSwap memory defi =
            MockAmirX.DefiSwap(address(0x0), address(0x0), plugin, IERC20(address(0x0)), referrer, amount, "", "");

        vm.prank(executor);
        amirX.defiSwap(user, defi);

        /// @dev calculator analyzes resulting user fee transfer event, checks stake eligibility
        /// and then calculates rewards for distribution

        uint256 stakedByUser = stakingModule.stakedByAt(user, block.number);
        uint256 prevRewards = tanIssuanceHistory.cumulativeRewardsAtBlock(user, block.number);
        uint256 userReward = stakedByUser - prevRewards;
        address[] memory rewardees = new address[](1);
        rewardees[0] = user;
        uint256[] memory rewards = new uint256[](1);
        rewards[0] = userReward;

        /// @dev Calculator performs pro-rata calculation but in this case there is just 1 user
        vm.prank(owner);
        tanIssuanceHistory.increaseClaimableByBatch(rewardees, rewards, block.number);

        assertEq(tanIssuanceHistory.lastSettlementBlock(), block.number);
        assertEq(tanIssuanceHistory.cumulativeRewards(user), userReward);
    }
}

/// @dev Mock contracts for TANIssuanceHistory integration testing. Do NOT use any in production

/// @notice This contract is deployed onchain for testing as no testing AmirX existed
contract MockAmirX is Ownable {
    struct DefiSwap {
        // Address for fee deposit
        address defiSafe;
        // Address of the swap aggregator or router
        address aggregator;
        // Plugin for handling referral fees
        ISimplePlugin plugin;
        // Token collected as fees
        IERC20 feeToken;
        // Address to receive referral fees
        address referrer;
        // Amount of referral fee
        uint256 referralFee;
        // Data for wallet interaction, if any
        bytes walletData;
        // Data for performing the swap, if any
        bytes swapData;
    }

    event Transfer(address from, address to, uint256 value);

    IERC20 public immutable tel;

    address public immutable defiAggIntermediary;

    constructor(IERC20 tel_, address owner_, address defiAggIntermediary_) Ownable(owner_) {
        tel = tel_;
        defiAggIntermediary = defiAggIntermediary_;
    }

    function defiSwap(address, DefiSwap memory defi) external payable onlyOwner {
        /// @notice the `DefiSwap.referralFee` actually refers to a separate referral program than this one
        /// but it is used here for simplicity
        tel.transferFrom(defiAggIntermediary, address(this), defi.referralFee);
    }
}

/// @notice This contract did not need to be deployed for testing as one already exists
contract MockTel is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    /// @notice Unprotected for simplicity
    function mint(address to, uint256 value) public {
        _mint(to, value);
    }
}

/// @notice This contract did not need to be deployed for testing as one already exists
contract MockStakingModule {
    event StakeChanged(address account, uint256 oldStake, uint256 newStake);

    mapping(address => uint256) _stakes;

    function stake(uint256 amount) external {
        uint256 oldStake = _stakes[msg.sender];
        uint256 newStake = _stakes[msg.sender] += amount;

        emit StakeChanged(msg.sender, oldStake, newStake);
    }

    function stakedByAt(address account, uint256 blockNumber) public view returns (uint256) {
        // ignore actual block number checkpoints
        require(blockNumber <= block.number, "Future lookup");

        return _stakes[account];
    }
}
