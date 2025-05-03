// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "./Interfaces/IClanker.sol";
import "./Interfaces/IPositionManager.sol";
import "./Interfaces/ILPLocker.sol";

contract Coincept {
    struct Build {
        address author;
        string buildLink;
        uint256 voteCount;
    }

    IVotes public voteToken;
    uint256 public endTime;
    bool public winnerDeclared;
    bool public rewardClaimed;

    address public winner;
    uint256 public winningBuild;
    address public creator;

    string public ideaDescription;
    Build[] public builds;

    mapping(address => bool) public hasVoted;

    // External dependencies
    address public clankerContract;
    uint256 public positionId;
    address constant lpLocker = 0x33e2Eda238edcF470309b8c6D228986A1204c8f9;
    address constant positionManager =
        0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    constructor(
        address _token,
        uint256 _duration,
        string memory _ideaDescription,
        address _clanker,
        uint256 _positionId
    ) {
        voteToken = IVotes(_token);
        endTime = block.timestamp + _duration;
        creator = msg.sender;
        ideaDescription = _ideaDescription;
        clankerContract = _clanker;
        positionId = _positionId;
    }

    function submitBuild(string memory buildLink) external {
        require(block.timestamp < endTime, "Voting has ended");
        builds.push(Build(msg.sender, buildLink, 0));
    }

    function vote(uint256 buildIndex) external {
        require(block.timestamp < endTime, "Voting has ended");
        require(!hasVoted[msg.sender], "Already voted");

        uint256 votingPower = voteToken.getVotes(msg.sender);
        require(votingPower > 0, "No voting power");

        builds[buildIndex].voteCount += votingPower;
        hasVoted[msg.sender] = true;
    }

    function pickWinner() public {
        require(block.timestamp >= endTime, "Voting still active");
        require(!winnerDeclared, "Winner already picked");

        uint256 highestVotes = 0;
        for (uint256 i = 0; i < builds.length; i++) {
            if (builds[i].voteCount > highestVotes) {
                highestVotes = builds[i].voteCount;
                winner = builds[i].author;
                winningBuild = i;
            }
        }

        winnerDeclared = true;
    }

    function claimRewards() external {
        require(block.timestamp >= endTime, "Voting still active");
        require(!rewardClaimed, "Already claimed");

        if (!winnerDeclared) {
            pickWinner();
        }

        // Collect rewards from LP locker
        (uint256 amount0, uint256 amount1) = ILPLocker(lpLocker).collectRewards(
            positionId
        );

        // Get the token address (token0 or token1 should match voteToken)
        (, , address token0, address token1, , , , , , , , ) = IPositionManager(
            positionManager
        ).positions(positionId);

        address rewardToken;
        uint256 amount;
        if (token0 == address(voteToken)) {
            rewardToken = token0;
            amount = amount0;
        } else if (token1 == address(voteToken)) {
            rewardToken = token1;
            amount = amount1;
        } else {
            revert("Reward token not found in position");
        }

        require(amount > 0, "No rewards to claim");

        // Split: 10% to idea poster, 90% to winning builder
        uint256 toCreator = (amount * 10) / 100;
        uint256 toBuilder = amount - toCreator;

        IERC20(rewardToken).transfer(creator, toCreator);
        IERC20(rewardToken).transfer(winner, toBuilder);

        rewardClaimed = true;
    }

    function getBuildCount() external view returns (uint256) {
        return builds.length;
    }
}
