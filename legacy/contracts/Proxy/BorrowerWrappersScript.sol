// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import "../Dependencies/GravitaMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/IVesselManager.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ISPRTStaking.sol";
import "./BorrowerOperationsScript.sol";
import "./ETHTransferScript.sol";
import "./SPRTStakingScript.sol";

contract BorrowerWrappersScript is BorrowerOperationsScript, ETHTransferScript, SPRTStakingScript {
	struct Local_var {
		address _asset;
		uint256 _maxFee;
		address _upperHint;
		address _lowerHint;
		uint256 netVUSDAmount;
	}

	string public constant NAME = "BorrowerWrappersScript";

	IVesselManager immutable vesselManager;
	IStabilityPool immutable stabilityPool;
	IPriceFeed immutable priceFeed;
	IERC20 immutable debtToken;
	IERC20 immutable sprtToken;

	constructor(
		address _borrowerOperationsAddress,
		address _vesselManagerAddress,
		address _SPRTStakingAddress
	) BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress)) SPRTStakingScript(_SPRTStakingAddress) {
		IVesselManager vesselManagerCached = IVesselManager(_vesselManagerAddress);
		vesselManager = vesselManagerCached;

		IStabilityPool stabilityPoolCached = vesselManagerCached.stabilityPool();
		stabilityPool = stabilityPoolCached;

		IPriceFeed priceFeedCached = vesselManagerCached.adminContract().priceFeed();
		priceFeed = priceFeedCached;

		address debtTokenCached = address(vesselManagerCached.debtToken());
		debtToken = IERC20(debtTokenCached);

		address sprtTokenCached = address(ISPRTStaking(_SPRTStakingAddress).sprtToken());
		sprtToken = IERC20(sprtTokenCached);

		// ISPRTStaking sprtStakingCached = vesselManagerCached.sprtStaking();
		// require(
		// 	_SPRTStakingAddress == address(sprtStakingCached),
		// 	"BorrowerWrappersScript: Wrong SPRTStaking address"
		// );
	}

	function claimCollateralAndOpenVessel(
		address _asset,
		uint256 _VUSDAmount,
		address _upperHint,
		address _lowerHint
	) external payable {
		uint256 balanceBefore = address(this).balance;

		// Claim collateral
		borrowerOperations.claimCollateral(_asset);

		uint256 balanceAfter = address(this).balance;

		// already checked in CollSurplusPool
		assert(balanceAfter > balanceBefore);

		uint256 totalCollateral = balanceAfter - balanceBefore + msg.value;

		// Open vessel with obtained collateral, plus collateral sent by user
		borrowerOperations.openVessel(_asset, totalCollateral, _VUSDAmount, _upperHint, _lowerHint);
	}

	function claimSPRewardsAndRecycle(address _asset, uint256 _maxFee, address _upperHint, address _lowerHint) external {
		Local_var memory vars = Local_var(_asset, _maxFee, _upperHint, _lowerHint, 0);
		uint256 collBalanceBefore = address(this).balance;
		uint256 SPRTBalanceBefore = sprtToken.balanceOf(address(this));

		// Claim rewards
		IStabilityPool(stabilityPool).withdrawFromSP(0);

		uint256 collBalanceAfter = address(this).balance;
		uint256 SPRTBalanceAfter = sprtToken.balanceOf(address(this));
		uint256 claimedCollateral = collBalanceAfter - collBalanceBefore;

		// Add claimed ETH to vessel, get more VUSD and stake it into the Stability Pool
		if (claimedCollateral > 0) {
			_requireUserHasVessel(vars._asset, address(this));
			vars.netVUSDAmount = _getNetVUSDAmount(vars._asset, claimedCollateral);
			borrowerOperations.adjustVessel(
				vars._asset,
				claimedCollateral,
				0,
				vars.netVUSDAmount,
				true,
				vars._upperHint,
				vars._lowerHint
			);
			// Provide withdrawn VUSD to Stability Pool
			if (vars.netVUSDAmount > 0) {
				IStabilityPool(stabilityPool).provideToSP(vars.netVUSDAmount);
			}
		}

		// Stake claimed SPRT
		uint256 claimedSPRT = SPRTBalanceAfter - SPRTBalanceBefore;
		if (claimedSPRT > 0) {
			ISPRTStaking(sprtStaking).stake(claimedSPRT);
		}
	}

	function claimStakingGainsAndRecycle(
		address _asset,
		uint256 _maxFee,
		address _upperHint,
		address _lowerHint
	) external {
		Local_var memory vars = Local_var(_asset, _maxFee, _upperHint, _lowerHint, 0);

		uint256 collBalanceBefore = address(this).balance;
		uint256 VUSDBalanceBefore = IDebtToken(debtToken).balanceOf(address(this));
		uint256 SPRTBalanceBefore = sprtToken.balanceOf(address(this));

		// Claim gains
		ISPRTStaking(sprtStaking).unstake(0);

		uint256 gainedCollateral = address(this).balance - collBalanceBefore; // stack too deep issues :'(
		uint256 gainedVUSD = IDebtToken(debtToken).balanceOf(address(this)) - VUSDBalanceBefore;

		// Top up vessel and get more VUSD, keeping ICR constant
		if (gainedCollateral > 0) {
			_requireUserHasVessel(vars._asset, address(this));
			vars.netVUSDAmount = _getNetVUSDAmount(vars._asset, gainedCollateral);
			borrowerOperations.adjustVessel(
				vars._asset,
				gainedCollateral,
				0,
				vars.netVUSDAmount,
				true,
				vars._upperHint,
				vars._lowerHint
			);
		}

		uint256 totalVUSD = gainedVUSD + vars.netVUSDAmount;
		if (totalVUSD > 0) {
			IStabilityPool(stabilityPool).provideToSP(totalVUSD);

			// Providing to Stability Pool also triggers SPRT claim, so stake it if any
			uint256 SPRTBalanceAfter = sprtToken.balanceOf(address(this));
			uint256 claimedSPRT = SPRTBalanceAfter - SPRTBalanceBefore;
			if (claimedSPRT > 0) {
				ISPRTStaking(sprtStaking).stake(claimedSPRT);
			}
		}
	}

	function _getNetVUSDAmount(address _asset, uint256 _collateral) internal returns (uint256) {
		uint256 price = IPriceFeed(priceFeed).fetchPrice(_asset);
		uint256 ICR = IVesselManager(vesselManager).getCurrentICR(_asset, address(this), price);

		uint256 VUSDAmount = (_collateral * price) / ICR;
		uint256 borrowingRate = IVesselManager(vesselManager).adminContract().getBorrowingFee(_asset);
		uint256 netDebt = (VUSDAmount * GravitaMath.DECIMAL_PRECISION) / (GravitaMath.DECIMAL_PRECISION + borrowingRate);

		return netDebt;
	}

	function _requireUserHasVessel(address _asset, address _depositor) internal view {
		require(
			IVesselManager(vesselManager).getVesselStatus(_asset, _depositor) == 1,
			"BorrowerWrappersScript: caller must have an active vessel"
		);
	}
}
