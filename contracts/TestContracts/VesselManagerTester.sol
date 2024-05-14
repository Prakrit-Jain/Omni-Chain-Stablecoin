// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import "../VesselManager.sol";

/* Tester contract inherits from VesselManager, and provides external functions 
for testing the parent's internal functions. */

contract VesselManagerTester is VesselManager {
	function computeICR(uint256 _coll, uint256 _debt, uint256 _price) external pure returns (uint256) {
		return GravitaMath._computeCR(_coll, _debt, _price);
	}

	function getCollGasCompensation(address _asset, uint256 _coll) external view returns (uint256) {
		return _getCollGasCompensation(_asset, _coll);
	}

	function getDebtTokenGasCompensation(address _asset) external view returns (uint256) {
		return IAdminContract(adminContract).getDebtTokenGasCompensation(_asset);
	}

	function getCompositeDebt(address _asset, uint256 _debt) external view returns (uint256) {
		return _getCompositeDebt(_asset, _debt);
	}

	function unprotectedDecayBaseRateFromBorrowing(address _asset) external returns (uint256) {
		baseRate[_asset] = _calcDecayedBaseRate(_asset);
		assert(baseRate[_asset] >= 0 && baseRate[_asset] <= DECIMAL_PRECISION);

		_updateLastFeeOpTime(_asset);
		return baseRate[_asset];
	}

	function minutesPassedSinceLastFeeOp(address _asset) external view returns (uint256) {
		return _minutesPassedSinceLastFeeOp(_asset);
	}

	function setLastFeeOpTimeToNow(address _asset) external {
		lastFeeOperationTime[_asset] = block.timestamp;
	}

	function setBaseRate(address _asset, uint256 _baseRate) external {
		baseRate[_asset] = _baseRate;
	}

	function callGetRedemptionFee(address _asset, uint256 _ETHDrawn) external view returns (uint256) {
		return getRedemptionFee(_asset, _ETHDrawn);
	}

	function getActualDebtFromComposite(address _asset, uint256 _debtVal) external view returns (uint256) {
		return _getNetDebt(_asset, _debtVal);
	}

	function callInternalRemoveVesselOwner(address _asset, address _vesselOwner) external {
		uint256 vesselOwnersArrayLength = VesselOwners[_asset].length;
		_removeVesselOwner(_asset, _vesselOwner, vesselOwnersArrayLength);
	}
	
	// calculates the borrower's vessel debt accrued over time and the pending rewards
	function getDebtAndPendingReward(address _asset, address _borrower) external view returns(uint256 debtAccrued, uint256 pendingReward) {
		pendingReward = getPendingDebtTokenReward(_asset, _borrower);
		Vessel storage vessel = Vessels[_borrower][_asset];
		uint256 debt = vessel.debt;
		uint256 newDebt;
		// Accrued vessel interest for correct liquidation values. This assumes the index to be updated.
        uint256 vesselInterestIndex = vessel.activeInterestIndex;
        if (vesselInterestIndex > 0) {
            (uint256 currentIndex, ) = _calculateInterestIndex(_asset);
            newDebt = (debt * currentIndex) / vesselInterestIndex;
        }
		debtAccrued = newDebt - debt;
	}
}
