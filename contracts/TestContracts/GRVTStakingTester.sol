// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import "../SPRT/SPRTStaking.sol";

contract SPRTStakingTester is SPRTStaking {
	function requireCallerIsVesselManager() external view callerIsVesselManager {}
}
