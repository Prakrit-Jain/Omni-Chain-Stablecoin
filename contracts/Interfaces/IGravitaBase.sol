// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./IAdminContract.sol";

interface IGravitaBase {
	struct Colls {
		// tokens and amounts should be the same length
		address[] tokens;
		uint256[] amounts;
	}

	struct InterestState {
		uint256 interestRate;
		uint256 activeInterestIndex;
    	uint256 lastActiveIndexUpdate;
		uint256 interestPayable;
	}
}
