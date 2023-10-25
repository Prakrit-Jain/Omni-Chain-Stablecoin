// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../GRVT/CommunityIssuance.sol";

contract CommunityIssuanceTester is CommunityIssuance {

	function getLastUpdateTokenDistribution() external view returns (uint256) {
		return _getLastUpdateTokenDistribution();
	}

	function unprotectedIssueGRVT() external returns (uint256) {
		return issueGRVT();
	}
}
