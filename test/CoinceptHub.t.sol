// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/coincept.sol";
import "../src/Interfaces/IClanker.sol";
import "../src/Interfaces/IPositionManager.sol";
import "../src/Interfaces/ILPLocker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract CoinceptTest is Test {
    Coincept public hub;
    address public clanker = 0x2A787b2362021cC3eEa3C24C4748a6cD5B687382;
    address public vault = 0x42A95190B4088C88Dd904d930c79deC1158bF09D;
    address public user;
    address public otherUser;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        user = vm.addr(1);
        otherUser = vm.addr(2);

        vm.deal(user, 10 ether);
        vm.deal(otherUser, 10 ether);

        hub = new Coincept(clanker, vault);
        console.log("setup done");
    }

    function getConfig()
        internal
        view
        returns (IClanker.DeploymentConfig memory)
    {
        return
            IClanker.DeploymentConfig({
                tokenConfig: IClanker.TokenConfig({
                    name: "TestToken",
                    symbol: "TTK",
                    salt: 0x0000000000000000000000000000000000000000000000000000000000000000,
                    image: "https://example.com/image.png",
                    metadata: "https://example.com/meta.json",
                    context: "Test token context",
                    originatingChainId: block.chainid
                }),
                vaultConfig: IClanker.VaultConfig({
                    vaultPercentage: 0,
                    vaultDuration: 0
                }),
                poolConfig: IClanker.PoolConfig({
                    pairedToken: 0x4200000000000000000000000000000000000006, // WETH mainnet
                    tickIfToken0IsNewToken: -207400
                }),
                initialBuyConfig: IClanker.InitialBuyConfig({
                    pairedTokenPoolFee: 10000,
                    pairedTokenSwapAmountOutMinimum: 0
                }),
                rewardsConfig: IClanker.RewardsConfig({
                    creatorReward: 60,
                    creatorAdmin: 0xEA380ddC224497dfFe5871737E12136d3968af15,
                    creatorRewardRecipient: 0xEA380ddC224497dfFe5871737E12136d3968af15,
                    interfaceAdmin: 0xEA380ddC224497dfFe5871737E12136d3968af15,
                    interfaceRewardRecipient: 0xEA380ddC224497dfFe5871737E12136d3968af15
                })
            });
    }

    function testDeploy() public {
        vm.startPrank(user);
        uint256 contestId = hub.createContest("Test Idea", 3 days, getConfig());
        console.log("Contest ID::::", contestId);
        vm.stopPrank();
    }

    function testFullFlow() public {
        vm.startPrank(user);

        // Deploy contest
        uint256 contestId = hub.createContest("Test Idea", 3 days, getConfig());
        console.log("Contest ID::::", contestId);
        (, , address voteToken, , ) = hub.getContestMetadata(contestId);

        assertTrue(voteToken != address(0), "Token not deployed");

        // Submit build
        hub.submitBuild(contestId, "ipfs://testbuild1");

        // Delegate voting power to user
        IVotes(voteToken).delegate(user);

        // Vote
        hub.vote(contestId, 0);

        // Fast-forward time
        vm.warp(block.timestamp + 4 days);

        // Pick winner
        hub.pickWinner(contestId);
        (, , , , address winner) = hub.getContestMetadata(contestId);
        assertEq(winner, user);

        vm.stopPrank();
    }
}
