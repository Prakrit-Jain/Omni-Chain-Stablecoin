// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../FeeCollector.sol";

contract FeeCollectorTester is FeeCollector {

	bool public __routeToSPRTStaking;

	function calcNewDuration(
		uint256 remainingAmount,
		uint256 remainingTimeToLive,
		uint256 addedAmount
	) external pure returns (uint256) {
		return _calcNewDuration(remainingAmount, remainingTimeToLive, addedAmount);
	}

	function setRouteToSPRTStaking(bool ___routeToSPRTStaking) external onlyOwner {
		__routeToSPRTStaking = ___routeToSPRTStaking;
	}

	function _routeToSPRTStaking() internal view override returns (bool) {
		return __routeToSPRTStaking;
	}
}
