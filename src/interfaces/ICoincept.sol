// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "./IClanker.sol";
import "./IPositionManager.sol";
import "./ILPLocker.sol";
import "./IClankerVault.sol";

interface ICoincept {
    // Custom errors
    error Unauthorized();
    error InvalidStartTime();
    error VotingEnded();
    error VotingNotStarted();
    error NoVotingPower();
    error WinnerAlreadyPicked();
    error InvalidAddress();
    error InvalidTokenAddress();

    struct Build {
        address author;
        string buildLink;
        uint256 voteCount;
    }

    struct Contest {
        address creator;
        string ideaDescription;
        address voteToken;
        uint256 votingStartTime;
        uint256 votingEndTime;
        bool winnerDeclared;
        address winner;
        uint256 winningBuild;
        uint256 positionId;
        string castHash;
        Build[] builds;
    }

    struct BuildInfo {
        uint256 contestId;
        uint256 buildIndex;
    }

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
    event SetAdmin(address admin, bool isAdmin);

    // State variables

    // Functions
    function createContest(
        string memory ideaDescription,
        uint256 votingStartTime,
        uint256 votingDuration,
        address creator,
        string memory castHash,
        IClanker.DeploymentConfig memory config
    ) external returns (uint256 contestId);

    function submitBuild(uint256 contestId, string memory buildLink) external;
    function vote(uint256 contestId, uint256 buildIndex) external;
    function pickWinner(uint256 contestId) external;
    function claimRewards(uint256 contestId) external;
    function transferVaultAdminToWinner(uint256 contestId) external;

    // Admin functions
    function setAdmin(address admin, bool isAdmin) external;
    function updateClanker(address newClanker) external;
    function updateVault(address newVault) external;
    function withdrawERC20(
        address token,
        uint256 amount,
        address recipient
    ) external;

    // View functions
    function getContestsByUser(
        address user
    ) external view returns (uint256[] memory);
    function getBuildsByUser(
        address user
    ) external view returns (BuildInfo[] memory);
    function getDetailedBuildsByUser(
        address user
    ) external view returns (Build[] memory);
    function getBuilds(
        uint256 contestId
    ) external view returns (Build[] memory);
    function getContestMetadata(
        uint256 contestId
    ) external view returns (Contest memory);
    function getBuildCount(uint256 contestId) external view returns (uint256);
    function getVotingInfo(
        uint256 contestId,
        address voter
    ) external view returns (uint256 buildIndex, uint256 votingPower);
}
