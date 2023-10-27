// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../SPRT/CommunityIssuance.sol";

contract CommunityIssuanceTester is CommunityIssuance {

	function unprotectedAddSPRTHoldings(address _account, uint256 _supply) external {
		sprtHoldings[_account] += _supply;
	}

	function getLastUpdateTokenDistribution() external view returns (uint256) {
		return _getLastUpdateTokenDistribution();
	}

	function unprotectedIssueSPRT() external returns (uint256) {
		return issueSPRT();
	}
}
