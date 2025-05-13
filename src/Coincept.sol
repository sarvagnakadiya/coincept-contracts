// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

import "./Interfaces/ICoincept.sol";

contract Coincept is ICoincept, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public contestCount;
    mapping(address => bool) public admins;
    mapping(uint256 => Contest) public contests;
    mapping(uint256 => mapping(address => uint256)) public votedBuildIndex;
    mapping(uint256 => mapping(address => uint256)) public votingPowerUsed;
    mapping(address => uint256[]) public userContests;
    mapping(address => BuildInfo[]) public userBuilds;
    address public clanker;
    address public vault;
    address public constant lpLocker =
        0x33e2Eda238edcF470309b8c6D228986A1204c8f9;
    address public constant positionManager =
        0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    constructor(address clanker_, address vault_) Ownable(msg.sender) {
        clanker = clanker_;
        vault = vault_;
    }

    function createContest(
        string memory ideaDescription,
        uint256 votingStartTime,
        uint256 votingDuration,
        address creator,
        string memory castHash,
        IClanker.DeploymentConfig memory config
    ) external override returns (uint256 contestId) {
        if (!admins[msg.sender]) revert Unauthorized();
        if (votingStartTime < block.timestamp) revert InvalidStartTime();
        (address token, uint256 positionId) = IClanker(clanker).deployToken{
            value: 0
        }(config);

        contestId = contestCount++;

        Contest storage c = contests[contestId];
        c.creator = creator;
        c.ideaDescription = ideaDescription;
        c.voteToken = token;
        c.votingStartTime = votingStartTime;
        c.votingEndTime = votingStartTime + votingDuration;
        c.positionId = positionId;
        c.castHash = castHash;

        userContests[creator].push(contestId);

        emit ContestCreated(
            contestId,
            creator,
            token,
            positionId,
            ideaDescription
        );
    }

    function submitBuild(
        uint256 contestId,
        string memory buildLink
    ) external override {
        if (block.timestamp >= contests[contestId].votingEndTime)
            revert VotingEnded();
        Contest storage c = contests[contestId];

        c.builds.push(Build(msg.sender, buildLink, 0));
        uint256 buildIndex = c.builds.length - 1;

        userBuilds[msg.sender].push(BuildInfo(contestId, buildIndex));

        emit BuildSubmitted(contestId, buildIndex, msg.sender);
    }

    function vote(uint256 contestId, uint256 buildIndex) external override {
        Contest storage c = contests[contestId];
        if (block.timestamp >= c.votingEndTime) revert VotingEnded();
        if (block.timestamp < c.votingStartTime) revert VotingNotStarted();

        uint256 votingPower = IVotes(c.voteToken).getVotes(msg.sender);
        if (votingPower == 0) revert NoVotingPower();

        // Get previous voting info
        uint256 previousBuildIndex = votedBuildIndex[contestId][msg.sender];
        uint256 previousVotingPower = votingPowerUsed[contestId][msg.sender];

        // If user has voted before, subtract their previous votes
        if (previousVotingPower > 0) {
            c.builds[previousBuildIndex].voteCount -= previousVotingPower;
        }

        // Add new votes
        c.builds[buildIndex].voteCount += votingPower;
        votedBuildIndex[contestId][msg.sender] = buildIndex;
        votingPowerUsed[contestId][msg.sender] = votingPower;

        emit Voted(contestId, buildIndex, msg.sender, votingPower);
    }

    function pickWinner(uint256 contestId) public override {
        Contest storage c = contests[contestId];
        if (block.timestamp < c.votingEndTime) revert VotingEnded();
        if (c.winnerDeclared) revert WinnerAlreadyPicked();

        uint256 maxVotes = 0;
        uint256 winningIndex = 0;

        for (uint256 i = 0; i < c.builds.length; i++) {
            uint256 votes = c.builds[i].voteCount;
            if (votes > maxVotes) {
                maxVotes = votes;
                winningIndex = i;
            }
        }

        c.winner = c.builds[winningIndex].author;
        c.winningBuild = winningIndex;
        c.winnerDeclared = true;

        emit WinnerDeclared(contestId, c.winner, winningIndex);
    }

    function claimRewards(uint256 contestId) external override nonReentrant {
        Contest storage c = contests[contestId];
        if (block.timestamp < c.votingEndTime) revert VotingEnded();

        if (!c.winnerDeclared) {
            pickWinner(contestId);
        }

        (, , address token0, address token1, , , , , , , , ) = IPositionManager(
            positionManager
        ).positions(c.positionId);

        // Snapshot balances before claiming
        uint256 bal0Before = IERC20(token0).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1).balanceOf(address(this));

        // Collect rewards — no return value
        ILPLocker(lpLocker).collectRewards(c.positionId);

        // Snapshot balances after
        uint256 bal0After = IERC20(token0).balanceOf(address(this));
        uint256 bal1After = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = bal0After - bal0Before;
        uint256 amount1 = bal1After - bal1Before;

        // --- Handle token0 ---
        if (amount0 > 0) {
            uint256 toCreator0 = (amount0 * 10) / 100;
            uint256 toWinner0 = amount0 - toCreator0;

            IERC20(token0).safeTransfer(c.creator, toCreator0);
            IERC20(token0).safeTransfer(c.winner, toWinner0);
        }

        // --- Handle token1 ---
        if (amount1 > 0) {
            uint256 toCreator1 = (amount1 * 10) / 100;
            uint256 toWinner1 = amount1 - toCreator1;

            IERC20(token1).safeTransfer(c.creator, toCreator1);
            IERC20(token1).safeTransfer(c.winner, toWinner1);
        }

        emit RewardsClaimed(
            contestId,
            c.creator,
            c.winner,
            token0,
            amount0,
            token1,
            amount1
        );
    }

    function transferVaultAdminToWinner(uint256 contestId) external override {
        Contest storage c = contests[contestId];

        if (!c.winnerDeclared) revert WinnerAlreadyPicked();

        // Transfer admin rights of voteToken in the global vault to the winner
        IClankerVault(vault).editAllocationAdmin(c.voteToken, c.winner);
    }

    // ---------------- admin Functions ----------------

    function setAdmin(address admin, bool isAdmin) external override onlyOwner {
        admins[admin] = isAdmin;
        emit SetAdmin(admin, isAdmin);
    }

    function updateClanker(address newClanker) external override onlyOwner {
        if (newClanker == address(0)) revert InvalidAddress();
        clanker = newClanker;
    }

    function updateVault(address newVault) external override onlyOwner {
        if (newVault == address(0)) revert InvalidAddress();
        vault = newVault;
    }

    function withdrawERC20(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyOwner {
        if (token == address(0)) revert InvalidTokenAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }

    // ---------------- View Functions ----------------

    function getContestsByUser(
        address user
    ) external view override returns (uint256[] memory) {
        return userContests[user];
    }

    function getBuildsByUser(
        address user
    ) external view override returns (BuildInfo[] memory) {
        return userBuilds[user];
    }

    function getDetailedBuildsByUser(
        address user
    ) external view override returns (Build[] memory) {
        BuildInfo[] memory infoArr = userBuilds[user];
        Build[] memory result = new Build[](infoArr.length);

        for (uint256 i = 0; i < infoArr.length; i++) {
            BuildInfo memory info = infoArr[i];
            result[i] = contests[info.contestId].builds[info.buildIndex];
        }

        return result;
    }

    function getBuilds(
        uint256 contestId
    ) external view override returns (Build[] memory) {
        return contests[contestId].builds;
    }

    function getContestMetadata(
        uint256 contestId
    ) external view override returns (Contest memory) {
        return contests[contestId];
    }

    function getBuildCount(
        uint256 contestId
    ) external view override returns (uint256) {
        return contests[contestId].builds.length;
    }

    function getVotingInfo(
        uint256 contestId,
        address voter
    ) external view override returns (uint256 buildIndex, uint256 votingPower) {
        buildIndex = votedBuildIndex[contestId][voter];
        votingPower = votingPowerUsed[contestId][voter];
    }
}
