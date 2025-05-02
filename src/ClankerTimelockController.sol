// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title ClankerTimelockController
 * @dev Timelock controller specific for Clanker governance
 */
contract ClankerTimelockController is TimelockController {
    /**
     * @dev Constructor for ClankerTimelockController
     * @param minDelay The minimum delay for operations
     * @param proposers List of addresses that can propose
     * @param executors List of addresses that can execute
     * @param admin Admin address (can be zero address for more decentralization)
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
