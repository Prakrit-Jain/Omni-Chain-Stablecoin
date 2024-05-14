// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./BaseMath.sol";
import "./GravitaMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IGravitaBase.sol";
import "../Interfaces/IAdminContract.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Addresses.sol";

/*
 * Base contract for VesselManager, BorrowerOperations and StabilityPool. Contains global system constants and
 * common functions.
 */
abstract contract GravitaBase is IGravitaBase, BaseMath, OwnableUpgradeable, Addresses {

	uint256 constant INTEREST_PRECISION = 1e27;

	// assetInterestRate[Collateral address]
	mapping(address => InterestState) public interestStateMappingPerAsset;

	// --- Gas compensation functions ---

	// Returns the composite debt (drawn debt + gas compensation) of a vessel, for the purpose of ICR calculation
	function _getCompositeDebt(address _asset, uint256 _debt) internal view returns (uint256) {
		return _debt + IAdminContract(adminContract).getDebtTokenGasCompensation(_asset);
	}

	function _getNetDebt(address _asset, uint256 _debt) internal view returns (uint256) {
		return _debt - IAdminContract(adminContract).getDebtTokenGasCompensation(_asset);
	}

	// Return the amount of ETH to be drawn from a vessel's collateral and sent as gas compensation.
	function _getCollGasCompensation(address _asset, uint256 _entireColl) internal view returns (uint256) {
		return _entireColl / IAdminContract(adminContract).getPercentDivisor(_asset);
	}

	function getEntireSystemColl(address _asset) public view returns (uint256 entireSystemColl) {
		uint256 activeColl = IActivePool(activePool).getAssetBalance(_asset);
		uint256 liquidatedColl = IDefaultPool(defaultPool).getAssetBalance(_asset);
		return activeColl + liquidatedColl;
	}

	function getEntireSystemDebt(address _asset) public view returns (uint256 entireSystemDebt) {
		uint256 activeDebt = IActivePool(activePool).getDebtTokenBalance(_asset);
		(, uint256 interestFactor) = _calculateInterestIndex(_asset);
        if (interestFactor > 0) {
            uint256 activeInterests = MathUpgradeable.mulDiv(activeDebt, interestFactor, INTEREST_PRECISION);
            activeDebt += activeInterests;
        }
		uint256 closedDebt = IDefaultPool(defaultPool).getDebtTokenBalance(_asset);
		return activeDebt + closedDebt;
	}

	// calculates the total active debt for a given asset
	function getTotalActiveDebt(address _asset) public view returns (uint256) {
        uint256 currentActiveDebt = IActivePool(activePool).getDebtTokenBalance(_asset);
        (, uint256 interestFactor) = _calculateInterestIndex(_asset);
        if (interestFactor > 0) {
            uint256 activeInterests = MathUpgradeable.mulDiv(currentActiveDebt, interestFactor, INTEREST_PRECISION);
            currentActiveDebt += activeInterests;
        }
        return currentActiveDebt;
    }

	function _getTCR(address _asset, uint256 _price) internal view returns (uint256 TCR) {
		uint256 entireSystemColl = getEntireSystemColl(_asset);
		uint256 entireSystemDebt = getEntireSystemDebt(_asset);
		TCR = GravitaMath._computeCR(entireSystemColl, entireSystemDebt, _price);
	}

	function _checkRecoveryMode(address _asset, uint256 _price) internal view returns (bool) {
		uint256 TCR = _getTCR(_asset, _price);
		return TCR < IAdminContract(adminContract).getCcr(_asset);
	}

	function _requireUserAcceptsFee(uint256 _fee, uint256 _amount, uint256 _maxFeePercentage) internal view {
		uint256 feePercentage = (_fee * IAdminContract(adminContract).DECIMAL_PRECISION()) / _amount;
		require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
	}

	//Interests

	// This function must be called any time the debt or the interest changes
    function _accrueActiveInterests(address _asset) internal returns (uint256) {
        (uint256 currentInterestIndex, uint256 interestFactor) = _calculateInterestIndex(_asset);
        if (interestFactor > 0) {
			InterestState storage params = interestStateMappingPerAsset[_asset];
			uint256 activeDebt = IActivePool(activePool).getDebtTokenBalance(_asset);
            uint256 activeInterests = MathUpgradeable.mulDiv(activeDebt, interestFactor, INTEREST_PRECISION);
			IActivePool(activePool).increaseDebt(_asset, activeInterests);
            params.interestPayable += activeInterests;
            params.activeInterestIndex = currentInterestIndex;
            params.lastActiveIndexUpdate = block.timestamp;
        }
        return currentInterestIndex;
    }

	// activeInterestIndex(c,n) = activeInterestIndex(c,n-1) * ( 1 + r*t )
	// activeInterestIndex(c,n) represents the Interest Rate Index for collateral 
	// type c at time n	
	// r represents the per-second interest rate 
	// t represents the time period since the last index update
    function _calculateInterestIndex(address _asset) internal view returns (uint256 currentInterestIndex, uint256 interestFactor) {
		InterestState memory params = interestStateMappingPerAsset[_asset];
        uint256 lastIndexUpdateCached = params.lastActiveIndexUpdate;
        // Short circuit if we updated in the current block
        if (lastIndexUpdateCached == block.timestamp) return (params.activeInterestIndex, 0);
        uint256 currentInterest = params.interestRate;
        currentInterestIndex = params.activeInterestIndex; // we need to return this if it's already up to date
        if (currentInterest > 0) {
            /*
             * Calculate the interest accumulated and the new index:
             * We compound the index and increase the debt accordingly
             */
            uint256 deltaT = block.timestamp - lastIndexUpdateCached;
            interestFactor = deltaT * currentInterest;
            currentInterestIndex += MathUpgradeable.mulDiv(currentInterestIndex, interestFactor, INTEREST_PRECISION);
        }
    }
}
