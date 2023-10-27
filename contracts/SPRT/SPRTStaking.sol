// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../Dependencies/BaseMath.sol";
import "../Dependencies/GravitaMath.sol";
import "../Dependencies/SafetyTransfer.sol";

import "../Interfaces/IDeposit.sol";
import "../Interfaces/ISPRTStaking.sol";
import "../Interfaces/ICommunityIssuance.sol";

contract SPRTStaking is ISPRTStaking, PausableUpgradeable, OwnableUpgradeable, BaseMath, ReentrancyGuardUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;

	// --- Data ---
	string public constant NAME = "SPRTStaking";
	address constant ETH_REF_ADDRESS = address(0);

	mapping(address => uint256) public stakes;
	uint256 public totalSPRTStaked;

	mapping(address => uint256) public F_ASSETS; // Running sum of asset fees per-SPRT-staked
	uint256 public F_DEBT_TOKENS; // Running sum of debt token fees per-SPRT-staked

	// User snapshots of F_ASSETS and F_DEBT_TOKENS, taken at the point at which their latest deposit was made
	mapping(address => Snapshot) public snapshots;

	struct Snapshot {
		mapping(address => uint256) F_ASSETS_Snapshot;
		uint256 F_DEBT_TOKENS_Snapshot;
	}

	address[] ASSET_TYPE;
	mapping(address => bool) isAssetTracked;
	mapping(address => uint256) public sentToTreasuryTracker;

	address public debtTokenAddress;
	address public feeCollectorAddress;
	address public treasuryAddress;
	address public vesselManagerAddress;
	address public communityIssuance;

	bool public isSetupInitialized;

	// --- Initializer ---

	function initialize() public initializer {
		__Ownable_init();
		__ReentrancyGuard_init();
		__Pausable_init();
		_pause();
	}

	// --- Functions ---
	function setAddresses(
		address _debtTokenAddress,
		address _feeCollectorAddress,
		address _treasuryAddress,
		address _vesselManagerAddress,
		address _communityIssuanceAddress
	) external onlyOwner {
		require(!isSetupInitialized, "Setup is already initialized");

		debtTokenAddress = _debtTokenAddress;
		feeCollectorAddress = _feeCollectorAddress;
		treasuryAddress = _treasuryAddress;
		vesselManagerAddress = _vesselManagerAddress;
		communityIssuance = _communityIssuanceAddress;

		isAssetTracked[ETH_REF_ADDRESS] = true;
		ASSET_TYPE.push(ETH_REF_ADDRESS);
		isSetupInitialized = true;
	}

	// If caller has a pre-existing stake, send any accumulated asset and debtToken gains to them.
	function stake(uint256 _SPRTamount) external override nonReentrant whenNotPaused {
		require(_SPRTamount > 0);

		uint256 currentStake = stakes[msg.sender];

		uint256 assetLength = ASSET_TYPE.length;
		uint256 assetGain;
		address asset;

		for (uint256 i = 0; i < assetLength; i++) {
			asset = ASSET_TYPE[i];

			if (currentStake != 0) {
				assetGain = _getPendingAssetGain(asset, msg.sender);

				if (i == 0) {
					uint256 debtTokenGain = _getPendingDebtTokenGain(msg.sender);
					IERC20Upgradeable(debtTokenAddress).safeTransfer(msg.sender, debtTokenGain);
					emit StakingGainsDebtTokensWithdrawn(msg.sender, debtTokenGain);
				}

				_sendAssetGainToUser(asset, assetGain);
				emit StakingGainsAssetWithdrawn(msg.sender, asset, assetGain);
			}

			_updateUserSnapshots(asset, msg.sender);
		}

		uint256 newStake = currentStake + _SPRTamount;

		// Increase user’s stake and total SPRT staked
		stakes[msg.sender] = newStake;
		totalSPRTStaked = totalSPRTStaked + _SPRTamount;
		emit TotalSPRTStakedUpdated(totalSPRTStaked);

		//Tranfers the holdings of SPRT from the user to this contract
		ICommunityIssuance(communityIssuance).transferSPRT(msg.sender, address(this), _SPRTamount);

		emit StakeChanged(msg.sender, newStake);
	}

	// Unstake the SPRT and send the it back to the caller, along with their accumulated gains.
	// If requested amount > stake, send their entire stake.
	function unstake(uint256 _SPRTamount) external override nonReentrant {
		uint256 currentStake = stakes[msg.sender];
		_requireUserHasStake(currentStake);

		uint256 assetLength = ASSET_TYPE.length;
		uint256 assetGain;
		address asset;

		for (uint256 i = 0; i < assetLength; i++) {
			asset = ASSET_TYPE[i];

			// Grab any accumulated asset and debtToken gains from the current stake
			assetGain = _getPendingAssetGain(asset, msg.sender);

			if (i == 0) {
				uint256 debtTokenGain = _getPendingDebtTokenGain(msg.sender);
				IERC20Upgradeable(debtTokenAddress).safeTransfer(msg.sender, debtTokenGain);
				emit StakingGainsDebtTokensWithdrawn(msg.sender, debtTokenGain);
			}

			_updateUserSnapshots(asset, msg.sender);
			emit StakingGainsAssetWithdrawn(msg.sender, asset, assetGain);
			_sendAssetGainToUser(asset, assetGain);
		}

		if (_SPRTamount > 0) {
			uint256 SPRTToWithdraw = GravitaMath._min(_SPRTamount, currentStake);
			uint256 newStake = currentStake - SPRTToWithdraw;

			// Decrease user's stake and total SPRT staked
			stakes[msg.sender] = newStake;
			totalSPRTStaked = totalSPRTStaked - SPRTToWithdraw;
			emit TotalSPRTStakedUpdated(totalSPRTStaked);

			// Transfers the unstaked SPRT holdings to user
			ICommunityIssuance(communityIssuance).transferSPRT(address(this), msg.sender, SPRTToWithdraw);
			emit StakeChanged(msg.sender, newStake);
		}
	}

	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}

	// --- Reward-per-unit-staked increase functions. Called by Gravita core contracts ---

	function increaseFee_Asset(address _asset, uint256 _assetFee) external override callerIsVesselManager {
		if (paused()) {
			sendToTreasury(_asset, _assetFee);
			return;
		}

		if (!isAssetTracked[_asset]) {
			isAssetTracked[_asset] = true;
			ASSET_TYPE.push(_asset);
		}

		uint256 assetFeePerSPRTStaked;

		if (totalSPRTStaked > 0) {
			assetFeePerSPRTStaked = (_assetFee * DECIMAL_PRECISION) / totalSPRTStaked;
		}

		F_ASSETS[_asset] = F_ASSETS[_asset] + assetFeePerSPRTStaked;
		emit Fee_AssetUpdated(_asset, F_ASSETS[_asset]);
	}

	function increaseFee_DebtToken(uint256 _debtTokenFee) external override callerIsFeeCollector {
		if (paused()) {
			sendToTreasury(debtTokenAddress, _debtTokenFee);
			return;
		}

		uint256 feePerSPRTStaked;
		if (totalSPRTStaked > 0) {
			feePerSPRTStaked = (_debtTokenFee * DECIMAL_PRECISION) / totalSPRTStaked;
		}

		F_DEBT_TOKENS = F_DEBT_TOKENS + feePerSPRTStaked;
		emit Fee_DebtTokenUpdated(F_DEBT_TOKENS);
	}

	function sendToTreasury(address _asset, uint256 _amount) internal {
		_sendAsset(treasuryAddress, _asset, _amount);
		sentToTreasuryTracker[_asset] += _amount;
		emit SentToTreasury(_asset, _amount);
	}

	// --- Pending reward functions ---

	function getPendingAssetGain(address _asset, address _user) external view override returns (uint256) {
		return _getPendingAssetGain(_asset, _user);
	}

	function _getPendingAssetGain(address _asset, address _user) internal view returns (uint256) {
		uint256 F_ASSET_Snapshot = snapshots[_user].F_ASSETS_Snapshot[_asset];
		uint256 AssetGain = (stakes[_user] * (F_ASSETS[_asset] - F_ASSET_Snapshot)) / DECIMAL_PRECISION;
		return AssetGain;
	}

	function getPendingDebtTokenGain(address _user) external view override returns (uint256) {
		return _getPendingDebtTokenGain(_user);
	}

	function _getPendingDebtTokenGain(address _user) internal view returns (uint256) {
		uint256 debtTokenSnapshot = snapshots[_user].F_DEBT_TOKENS_Snapshot;
		return (stakes[_user] * (F_DEBT_TOKENS - debtTokenSnapshot)) / DECIMAL_PRECISION;
	}

	// --- Internal helper functions ---

	function _updateUserSnapshots(address _asset, address _user) internal {
		snapshots[_user].F_ASSETS_Snapshot[_asset] = F_ASSETS[_asset];
		snapshots[_user].F_DEBT_TOKENS_Snapshot = F_DEBT_TOKENS;
		emit StakerSnapshotsUpdated(_user, F_ASSETS[_asset], F_DEBT_TOKENS);
	}

	function _sendAssetGainToUser(address _asset, uint256 _assetGain) internal {
		_assetGain = SafetyTransfer.decimalsCorrection(_asset, _assetGain);
		_sendAsset(msg.sender, _asset, _assetGain);
		emit AssetSent(_asset, msg.sender, _assetGain);
	}

	function _sendAsset(address _sendTo, address _asset, uint256 _amount) internal {
		IERC20Upgradeable(_asset).safeTransfer(_sendTo, _amount);
	}

	// --- 'require' functions ---

	modifier callerIsVesselManager() {
		require(msg.sender == vesselManagerAddress, "SPRTStaking: caller is not VesselManager");
		_;
	}

	modifier callerIsFeeCollector() {
		require(msg.sender == feeCollectorAddress, "SPRTStaking: caller is not FeeCollector");
		_;
	}

	function _requireUserHasStake(uint256 currentStake) internal pure {
		require(currentStake > 0, "SPRTStaking: User must have a non-zero stake");
	}
}
