// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./external/IMarket.sol";
import "./external/ISynthetixCore.sol";


import "lib/forge-std/src/interfaces/IERC20.sol";
import "lib/chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";



contract NumberGuessingGame is VRFV2WrapperConsumerBase, IMarket {

    //Variable Declarations
    ISynthetixCore public synthetix;
    IERC20 public linkToken;
    uint128 public marketId;

    uint public prize;
    uint256 public ticktCost;
    uint256 public feePercent;

    uint256 private currentDrawRound;
    bool private isDrawing; 

    mapping(uint256 => mapping(uint256 => address[])) ticketBuckets;
    mapping(uint256 => uint256) requestIdToRound;

    //Events 
        error InsufficientLiquidity(uint256 guessNumber, uint256 maxParticipants);


    // Constructor

    constructor(
        ISynthetixCore _synthetix,
        address link,
        address vrf,
        uint256 _prize,
        uint256 _ticketCost,
        uint256 _feePercent
    ) VRFV2WrapperConsumerBase(link, vrf) {
        synthetix = _synthetix;
        linkToken = IERC20(link);
        prize = _prize;
        ticketCost = _ticketCost;
        feePercent = _feePercent;
    }

    function registerMarket() external {
        if (marketId == 0) {
            marketId = synthetix.registerMarket(address(this));
            emit MarketRegistered(marketId);
        }
    }

    function buy(address benficary, unit guessNumber) {

        address[] storage bucketParticipants = ticketBuckets[currentDrawRound][guessNumber % _bucketCount()];

        uint maxParticipants = getMaxBucketParticipants();

        if (bucketParticipants.length >= maxParticipants) {
            revert InsufficientLiquidity(guessNumber, maxParticipants);
        }
    }


    function getMaxBucketparticipants() public view returns (uint256) {
        return synthetix.getWithdrawableMarketUsd(marketId) / prize;
    }

    error DrawAlreadyInProgress();
    
    function startDraw(uint256 maxLinkCost) external {
        if (isDrawing) {

            revert DrawAlreadyInProgress();

        }

        linkToken.transferFrom(msg.sender, address(this), maxLinkCost);

        uint256 requestId = requestRandomness (
            500000,
            0,
            1
        );

        requestIdToRound[requestId] = currentDrawRound++;

        isDrawing = true;

    }
        function finishDraw(uint256 round, uint256 winningNumber) internal {
        address[] storage winners = ticketBuckets[round][winningNumber % _bucketCount()];

        // if we dont have sufficient deposits, withdraw stablecoins from LPs
        IERC20 usdToken = IERC20(synthetix.getUsdToken());
        uint currentBalance = usdToken.balanceOf(address(this));
        if (currentBalance < prize * winners.length) {
            synthetix.withdrawMarketUsd(
                marketId,
                address(this),
                prize * winners.length - currentBalance
            );

            currentBalance = prize * winners.length;
        }

        // now send the deposits
        for (uint i = 0;i < winners.length;i++) {
            usdToken.transfer(winners[i], prize);
        }

        // update what our balance should be
        currentBalance -= prize * winners.length;

        // send anything remaining to the deposit
        if (currentBalance > 0) {
            synthetix.depositMarketUsd(marketId, address(this), currentBalance);
        }

        // allow for the next draw to start and unlock funds
        isDrawing = false;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override virtual {
        finishDraw(requestIdToRound[requestId], randomWords[0]);
    }

    function _bucketCount() internal view returns (uint256) {
        uint256 baseBuckets = prize / ticketCost;
        return baseBuckets + baseBuckets * feePercent;
    }

    // Functions
    function name(unit128 _marketId) external override view returns (string memory n) {
        if (_marketId == marketId) {
            n = string(abi.encodedPacked("Market ", bytes32(uint256(_marketId))));
        }
    }


    function reportedDebt(uint128) external override pure returns (uint256) {
        
        // This function allows a market to share the amount of unrealized debt created by the snythetic market
        // For example, a sport market would return totalSupply * tokenPrice;
        
        return 0;


    }

    function minimumCredit(uint128 _marketId) external override view returns (uint256) {
        // This controls the minimum amount of $$$ sent its way through liquidity pools


        
        return 0;
    }
        function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165) returns (bool) {
        return
            interfaceId == type(IMarket).interfaceId ||
            interfaceId == this.supportsInterface.selector;
    }
    
}