// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "./Interfaces/IClanker.sol";
import "./Interfaces/IPositionManager.sol";
import "./Interfaces/ILPLocker.sol";
import "./Interfaces/IClankerVault.sol";

contract Coincept is ReentrancyGuard, Ownable {
    struct Build {
        address author;
        string buildLink;
        uint256 voteCount;
    }

    struct Contest {
        address creator;
        string ideaDescription;
        address voteToken;
        uint256 endTime;
        bool winnerDeclared;
        address winner;
        uint256 winningBuild;
        uint256 positionId;
        address contestToken;
        Build[] builds;
    }

    struct BuildInfo {
        uint256 contestId;
        uint256 buildIndex;
    }

    uint256 public contestCount;

    // Core storage
    mapping(uint256 => Contest) public contests;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Indexing for efficient queries
    mapping(address => uint256[]) public userContests; // contests created by user
    mapping(address => BuildInfo[]) public userBuilds; // builds submitted by user

    // External contracts
    address public clanker;
    address public vault;
    address public constant lpLocker =
        0x33e2Eda238edcF470309b8c6D228986A1204c8f9;
    address public constant positionManager =
        0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    event ContestCreated(
        uint256 indexed contestId,
        address indexed creator,
        address token,
        uint256 positionId,
        string idea
    );
    event BuildSubmitted(
        uint256 indexed contestId,
        uint256 indexed buildIndex,
        address author
    );
    event Voted(
        uint256 indexed contestId,
        uint256 indexed buildIndex,
        address voter,
        uint256 weight
    );
    event WinnerDeclared(
        uint256 indexed contestId,
        address winner,
        uint256 buildIndex
    );
    event RewardsClaimed(
        uint256 indexed contestId,
        address creator,
        address winner,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    );

    constructor(address _clanker, address _vault) Ownable(msg.sender) {
        clanker = _clanker;
        vault = _vault;
    }

    function createContest(
        string memory ideaDescription,
        uint256 votingDuration,
        IClanker.DeploymentConfig memory config
    ) external returns (uint256 contestId) {
        (address token, uint256 positionId) = IClanker(clanker).deployToken{
            value: 0
        }(config);

        contestId = contestCount++;

        Contest storage c = contests[contestId];
        c.creator = msg.sender;
        c.ideaDescription = ideaDescription;
        c.voteToken = token;
        c.endTime = block.timestamp + votingDuration;
        c.positionId = positionId;
        c.contestToken = token;

        userContests[msg.sender].push(contestId);

        emit ContestCreated(
            contestId,
            msg.sender,
            token,
            positionId,
            ideaDescription
        );
    }

    function submitBuild(uint256 contestId, string memory buildLink) external {
        require(block.timestamp < contests[contestId].endTime, "Voting ended");
        Contest storage c = contests[contestId];

        c.builds.push(Build(msg.sender, buildLink, 0));
        uint256 buildIndex = c.builds.length - 1;

        userBuilds[msg.sender].push(BuildInfo(contestId, buildIndex));

        emit BuildSubmitted(contestId, buildIndex, msg.sender);
    }

    function vote(uint256 contestId, uint256 buildIndex) external {
        Contest storage c = contests[contestId];
        require(block.timestamp < c.endTime, "Voting ended");
        require(!hasVoted[contestId][msg.sender], "Already voted");

        uint256 votingPower = IVotes(c.voteToken).getVotes(msg.sender);
        require(votingPower > 0, "No voting power");

        c.builds[buildIndex].voteCount += votingPower;
        hasVoted[contestId][msg.sender] = true;

        emit Voted(contestId, buildIndex, msg.sender, votingPower);
    }

    function pickWinner(uint256 contestId) public {
        Contest storage c = contests[contestId];
        require(block.timestamp >= c.endTime, "Voting still active");
        require(!c.winnerDeclared, "Winner already picked");

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

    function claimRewards(uint256 contestId) external nonReentrant {
        Contest storage c = contests[contestId];
        require(block.timestamp >= c.endTime, "Voting still active");

        if (!c.winnerDeclared) {
            pickWinner(contestId);
        }

        (uint256 amount0, uint256 amount1) = ILPLocker(lpLocker).collectRewards(
            c.positionId
        );

        (, , address token0, address token1, , , , , , , , ) = IPositionManager(
            positionManager
        ).positions(c.positionId);

        // --- Handle token0 rewards ---
        if (amount0 > 0) {
            uint256 toCreator0 = (amount0 * 10) / 100;
            uint256 toWinner0 = amount0 - toCreator0;

            require(
                IERC20(token0).transfer(c.creator, toCreator0),
                "token0: transfer to creator failed"
            );
            require(
                IERC20(token0).transfer(c.winner, toWinner0),
                "token0: transfer to winner failed"
            );
        }

        // --- Handle token1 rewards ---
        if (amount1 > 0) {
            uint256 toCreator1 = (amount1 * 10) / 100;
            uint256 toWinner1 = amount1 - toCreator1;

            require(
                IERC20(token1).transfer(c.creator, toCreator1),
                "token1: transfer to creator failed"
            );
            require(
                IERC20(token1).transfer(c.winner, toWinner1),
                "token1: transfer to winner failed"
            );
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

    function transferVaultAdminToWinner(uint256 contestId) external {
        Contest storage c = contests[contestId];

        require(c.winnerDeclared, "Winner not picked");

        // Transfer admin rights of voteToken in the global vault to the winner
        IClankerVault(vault).editAllocationAdmin(c.voteToken, c.winner);
    }

    // ---------------- admin Functions ----------------
    function updateClanker(address newClanker) external onlyOwner {
        require(newClanker != address(0), "Invalid address");
        clanker = newClanker;
    }

    function updateVault(address newVault) external onlyOwner {
        require(newVault != address(0), "Invalid address");
        vault = newVault;
    }
    // ---------------- View Functions ----------------

    function getContestsByUser(
        address user
    ) external view returns (uint256[] memory) {
        return userContests[user];
    }

    function getBuildsByUser(
        address user
    ) external view returns (BuildInfo[] memory) {
        return userBuilds[user];
    }

    function getDetailedBuildsByUser(
        address user
    ) external view returns (Build[] memory) {
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
    ) external view returns (Build[] memory) {
        return contests[contestId].builds;
    }

    function getContestMetadata(
        uint256 contestId
    )
        external
        view
        returns (
            address creator,
            string memory idea,
            address voteToken,
            uint256 endTime,
            address winner
        )
    {
        Contest storage c = contests[contestId];
        return (c.creator, c.ideaDescription, c.voteToken, c.endTime, c.winner);
    }

    function getBuildCount(uint256 contestId) external view returns (uint256) {
        return contests[contestId].builds.length;
    }
}
