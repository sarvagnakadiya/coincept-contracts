// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MyGovernor.sol";

contract GovernanceFactory {
    address payable public immutable timelock;

    event GovernorCreated(address indexed token, address indexed governor);
    event ProposalCreated(address indexed governor, uint256 proposalId);

    constructor(address payable _timelock) {
        timelock = _timelock;
    }

    function createGovernor(
        address token,
        string memory proposalDescription,
        uint256 quorumFraction
    ) external returns (address governorAddress) {
        // token must implement IVotes (ERC20Votes)
        MyGovernor governor = new MyGovernor(
            IVotes(token),
            TimelockController(timelock)
        );

        // Create initial proposal to set quorum fraction
        address[] memory targets = new address[](1);
        targets[0] = address(governor);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        // Encode the function call to updateQuorumNumerator(uint256)
        calldatas[0] = abi.encodeWithSignature(
            "updateQuorumNumerator(uint256)",
            quorumFraction
        );

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            proposalDescription
        );

        emit GovernorCreated(token, address(governor));
        emit ProposalCreated(address(governor), proposalId);
        return address(governor);
    }
}
