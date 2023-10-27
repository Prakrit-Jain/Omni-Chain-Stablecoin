// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface ICommunityIssuance {
	// --- Events ---

	event TotalSPRTIssuedUpdated(uint256 _totalSPRTIssued);

	event SPRTTransferred(address indexed _from, address indexed _to, uint256 _amount);

	// --- Functions ---

	function issueSPRT() external returns (uint256);

	function sendSPRT(address _account, uint256 _SPRTamount) external;

	function transferSPRT(address _from, address _to, uint256 _amount) external;

	function addFundToStabilityPool(uint256 _assignedSupply) external;

	function addFundToStabilityPoolFrom(uint256 _assignedSupply, address _spender) external;

	function setWeeklySprtDistribution(uint256 _weeklyReward) external;
}
