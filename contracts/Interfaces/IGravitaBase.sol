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
		// variable interest rate kept by the protocol
		uint256 interestRate;
		// Global activeInterestIndex, It represents the current index value for the entire protocol.
		// It might increase as time goes on and as interest accrues.
		uint256 activeInterestIndex;
		// Last time at which active index was updated
    	uint256 lastActiveIndexUpdate;
		// Compounded Interest accrued that is to be paid to Fee Collector
		uint256 interestPayable;
	}
}
