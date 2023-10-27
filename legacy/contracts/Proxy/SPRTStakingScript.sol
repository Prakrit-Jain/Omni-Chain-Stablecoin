// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import "../Interfaces/ISPRTStaking.sol";

contract SPRTStakingScript {
	ISPRTStaking immutable sprtStaking;

	constructor(address _SPRTStakingAddress) {
		sprtStaking = ISPRTStaking(_SPRTStakingAddress);
	}

	function stake(uint256 _SPRTamount) external {
		ISPRTStaking(sprtStaking).stake(_SPRTamount);
	}
}
