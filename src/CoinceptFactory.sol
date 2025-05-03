// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Coincept.sol";
import "./Interfaces/IClanker.sol";

contract CoinceptFactory {
    IClanker public clanker;

    event TokenAndContestDeployed(
        address indexed token,
        address indexed contest,
        uint256 indexed positionId,
        address creator,
        string idea
    );

    // Track token → Coincept (contest) contract
    mapping(address => address) public tokenToContest;

    // Track contest → token
    mapping(address => address) public contestToToken;

    // Track user → list of idea contracts they created
    mapping(address => address[]) public userIdeas;

    // Track contest address → idea description
    mapping(address => string) public contestIdea;

    struct IdeaInfo {
        address contest;
        address token;
        string idea;
        address creator;
        address winner;
        string winningBuildLink;
        address author;
        uint256 voteCount;
        string ideaDescription;
    }

    constructor(address _clanker) {
        clanker = IClanker(_clanker);
    }

    function deployTokenWithContest(
        uint256 votingPeriod,
        IClanker.DeploymentConfig memory dc,
        string calldata _ideaDescription
    ) external returns (address token, address contest, uint256) {
        (address tokenAddress, uint256 positionId) = clanker.deployToken(dc);

        Coincept idea = new Coincept(
            tokenAddress,
            votingPeriod,
            _ideaDescription,
            address(clanker),
            positionId
        );

        // Track mappings
        tokenToContest[tokenAddress] = address(idea);
        contestToToken[address(idea)] = tokenAddress;
        userIdeas[msg.sender].push(address(idea));
        contestIdea[address(idea)] = _ideaDescription;

        emit TokenAndContestDeployed(
            tokenAddress,
            address(idea),
            positionId,
            msg.sender,
            _ideaDescription
        );
        return (tokenAddress, address(idea), positionId);
    }

    /// @notice Get all contests (ideas) created by a user
    function getIdeasByUser(
        address user
    ) external view returns (address[] memory) {
        return userIdeas[user];
    }

    /// @notice Get full idea metadata for a given contest contract
    function getIdeaDetails(
        address contestAddress
    )
        external
        view
        returns (address token, string memory idea, address creator)
    {
        token = contestToToken[contestAddress];
        idea = contestIdea[contestAddress];
        // Attempt to extract creator from the Coincept contract directly
        creator = Coincept(contestAddress).creator();
    }

    function getFullIdeasByUser(
        address user
    ) external view returns (IdeaInfo[] memory) {
        address[] memory contests = userIdeas[user];
        IdeaInfo[] memory ideas = new IdeaInfo[](contests.length);

        for (uint256 i = 0; i < contests.length; i++) {
            address contest = contests[i];
            address token = contestToToken[contest];
            string memory idea = contestIdea[contest];
            address creator = Coincept(contest).creator();
            address winner = Coincept(contest).winner();
            string memory IdeaDesc = Coincept(contest).ideaDescription();
            address buildAuthor = address(0);
            uint256 vCount = 0;

            string memory winningBuildLink = "";
            if (winner != address(0)) {
                try
                    Coincept(contest).builds(Coincept(contest).winningBuild())
                returns (
                    address author,
                    string memory buildLink,
                    uint256 voteCount
                ) {
                    winningBuildLink = buildLink;
                    buildAuthor = author;
                    vCount = voteCount;
                } catch {
                    // Fallback in case it fails
                    winningBuildLink = "Error fetching build";
                }
            }

            ideas[i] = IdeaInfo({
                contest: contest,
                token: token,
                idea: idea,
                creator: creator,
                winner: winner,
                winningBuildLink: winningBuildLink,
                author: buildAuthor,
                voteCount: vCount,
                ideaDescription: IdeaDesc
            });
        }

        return ideas;
    }
}
