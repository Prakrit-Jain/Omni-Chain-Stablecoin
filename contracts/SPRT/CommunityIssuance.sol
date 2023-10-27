// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../Dependencies/BaseMath.sol";
import "../Dependencies/GravitaMath.sol";

import "../Interfaces/ICommunityIssuance.sol";
import "../Interfaces/IStabilityPool.sol";

contract CommunityIssuance is ICommunityIssuance, OwnableUpgradeable, BaseMath {
	using SafeERC20Upgradeable for IERC20Upgradeable;

	string public constant NAME = "CommunityIssuance";

	uint256 public constant DISTRIBUTION_DURATION = 7 days / 60;
	uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

	uint256 public totalSPRTIssued;
	uint256 public lastUpdateTime;
	uint256 public SPRTSupplyCap;
	uint256 public sprtDistribution;

	IStabilityPool public stabilityPool;

	address public staking;
	address public adminContract;
	bool public isSetupInitialized;

	// mapping to maintain the accounting of SPRT holdings, similar to `balanceOf` of
	// SPRT token.
	mapping(address => uint256) public sprtHoldings;

	modifier isController() {
		require(msg.sender == owner() || msg.sender == adminContract, "Invalid Permission");
		_;
	}

	modifier isStabilityPool(address _pool) {
		require(address(stabilityPool) == _pool, "CommunityIssuance: caller is not SP");
		_;
	}

	modifier onlyStabilityPool() {
		require(address(stabilityPool) == msg.sender, "CommunityIssuance: caller is not SP");
		_;
	}

	modifier onlyStaking() {
		require(staking == msg.sender, "CommunityIssuance: caller is not SPRTStaking");
		_;
	}

	// --- Initializer ---

	function initialize() public initializer {
		__Ownable_init();
	}

	// --- Functions ---
	function setAddresses(
		address stakingAddress,
		address _stabilityPoolAddress,
		address _adminContract
	) external onlyOwner {
		require(!isSetupInitialized, "Setup is already initialized");
		staking = stakingAddress;
		adminContract = _adminContract;
		stabilityPool = IStabilityPool(_stabilityPoolAddress);
		isSetupInitialized = true;
	}

	function setAdminContract(address _admin) external onlyOwner {
		require(_admin != address(0));
		adminContract = _admin;
	}

	function addFundToStabilityPool(uint256 _assignedSupply) external override isController {
		_addFundToStabilityPoolFrom(_assignedSupply, msg.sender);
	}

	function removeFundFromStabilityPool(uint256 _fundToRemove) external onlyOwner {
		uint256 newCap = SPRTSupplyCap - _fundToRemove;
		require(totalSPRTIssued <= newCap, "CommunityIssuance: Stability Pool doesn't have enough supply.");

		SPRTSupplyCap -= _fundToRemove;

		sprtHoldings[address(this)] -= _fundToRemove;
		sprtHoldings[msg.sender] += _fundToRemove;
	}

	function addFundToStabilityPoolFrom(uint256 _assignedSupply, address _spender) external override isController {
		_addFundToStabilityPoolFrom(_assignedSupply, _spender);
	}

	function _addFundToStabilityPoolFrom(uint256 _assignedSupply, address _spender) internal {
		if (lastUpdateTime == 0) {
			lastUpdateTime = block.timestamp;
		}

		SPRTSupplyCap += _assignedSupply;
		sprtHoldings[_spender] -= _assignedSupply;
		sprtHoldings[address(this)] += _assignedSupply;
	}

	function issueSPRT() public override onlyStabilityPool returns (uint256) {
		uint256 maxPoolSupply = SPRTSupplyCap;

		if (totalSPRTIssued >= maxPoolSupply) return 0;

		uint256 issuance = _getLastUpdateTokenDistribution();
		uint256 totalIssuance = issuance + totalSPRTIssued;

		if (totalIssuance > maxPoolSupply) {
			issuance = maxPoolSupply - totalSPRTIssued;
			totalIssuance = maxPoolSupply;
		}

		lastUpdateTime = block.timestamp;
		totalSPRTIssued = totalIssuance;
		emit TotalSPRTIssuedUpdated(totalIssuance);

		return issuance;
	}

	function _getLastUpdateTokenDistribution() internal view returns (uint256) {
		require(lastUpdateTime != 0, "Stability pool hasn't been assigned");
		uint256 timePassed = (block.timestamp - lastUpdateTime) / SECONDS_IN_ONE_MINUTE;
		uint256 totalDistribuedSinceBeginning = sprtDistribution * timePassed;

		return totalDistribuedSinceBeginning;
	}

	function sendSPRT(address _account, uint256 _SPRTamount) external override onlyStabilityPool {
		uint256 balanceSPRT = sprtHoldings[address(this)];
		uint256 safeAmount = balanceSPRT >= _SPRTamount ? _SPRTamount : balanceSPRT;

		if (safeAmount == 0) {
			return;
		}

		sprtHoldings[address(this)] -= safeAmount;
		sprtHoldings[_account] += safeAmount;
	}

	// called by staking contract to update the transfers of sprt
	function transferSPRT(address _from, address _to, uint256 _amount) external onlyStaking {
		require(_from != address(0), "CommunityIssuance: SPRT Transfer from Zero Address.");
		require(_to != address(0), "CommunityIssuance: SPRT Transfer to Zero Address.");

		uint256 fromHoldings = sprtHoldings[_from];
		require(fromHoldings >= _amount, "CommunityIssuance: transfer amount exceeds");
		unchecked {
			sprtHoldings[_from] = fromHoldings - _amount;
			sprtHoldings[_to] += _amount;
		}
		emit SPRTTransferred(_from, _to, _amount);
	}

	function setWeeklySprtDistribution(uint256 _weeklyReward) external isController {
		sprtDistribution = _weeklyReward / DISTRIBUTION_DURATION;
	}
}
