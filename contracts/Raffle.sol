// Raffle

//Enter the lottery (paying some amount)
// Pick a randon winner (verifiably random)
// Winner to be selected evevry X minutes -> completely automated 

// Chainlink Oracle -> Randomness, Automated Execution (Chain Keeper)


// we are building comsuming contract to use subscription contract(randomness features)

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

//The documentation that lead us to know how to do each part
//https://docs.chain.link/vrf/v2/subscription/examples/get-a-random-number

error Raffle__NotEnoughETHEntered();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);


/**@title A sample Raffle Contract
* @author monz 
* @notice This contract is for creating an untamperable  decentralized smart contract 
* @dev This implement Chainlink VRF v2 and Chainlink keeper 
 */
contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface{

    /* Type declarations */
    enum RaffleState{
        OPEN,CALCULATING
    } 
    /*state variable */
    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS =3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;


    // Lottery variable
    address private s_recentWinner;
    RaffleState private s_raffleState; // to pending, open , close, calculating 
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    /*event */
    event RaffleEnter(address indexed player);
    event RequestRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    constructor(address vrfCoordinatorV2 /*contract */, uint256 entranceFee, bytes32 gasLane, uint64 subscriptionId, uint32 callbackGasLimit, uint256 interval) VRFConsumerBaseV2(vrfCoordinatorV2){
        i_entranceFee = entranceFee;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane= gasLane;
        i_subscriptionId= subscriptionId;
        i_callbackGasLimit= callbackGasLimit;
        s_raffleState= RaffleState.OPEN;
        s_lastTimeStamp= block.timestamp;
        i_interval = interval;



    }
    /*Function */
    function enterRaffle() public payable{
        // require (msg.value > i_entranceFee, "not enough ETH")
        if (msg.value<i_entranceFee){revert Raffle__NotEnoughETHEntered();} // the first step is to enterRaffle
        if (s_raffleState!= RaffleState.OPEN){
            revert Raffle__NotOpen();
        }
        s_players.push(payable(msg.sender));
        // Emit an event when we update a dynamic array or mapping
        // Named events with the function name reverse
        emit RaffleEnter(msg.sender);
    }
    /**
    * @dev This is the function that the chainlink keeper nodes call
    * they look for the upkeepNeeded to return true
    * following should be true in order to return true
    * 1. Our time interval should have passed
    * 2. The lottery should have at least 1 player, and have some ETH
    * 3. Our subscription is funded with Link 
    * 4. The lottery should be in an open state
     */

     // checkUpkeep is the function that makes that make sure if we gonna call perform function in the next step.
     // checkUpkeep can receive a data from on chain and excecute off-chian by using @param checkData.
     // after finished execution, it will return as performData
    function checkUpkeep(bytes memory /*checkData use as ""*/) public override returns(bool upkeepNeeded, bytes memory /*performData */){ // making sure that everything is correct
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);  // block.timestamp  - s_lastTimeStamp equal to the between the contract is called and checkUpkeep function is called.
        bool hasPlayers = (s_players.length >0);
        bool hasBalance = address(this).balance>0;
        upkeepNeeded =(isOpen && timePassed && hasPlayers && hasBalance);
        // block.timestamp -last blocktimestamp
    }
    // the function that is run on chain
    function performUpkeep(bytes calldata /*performData */) external override{
        // Request the random number 
        // Once we get it, do something with it
        // 2 transaction process
        (bool upkeepNeeded, ) = checkUpkeep("");
        if(!upkeepNeeded){ // if everything from check up keep is not correct, it will send an error below
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState= RaffleState.CALCULATING; // let it know that Raffle state change to calculating instead of start
        uint256 requestId= i_vrfCoordinator.requestRandomWords( // requestId and the information that we need to request
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestRaffleWinner(requestId);
    }
    function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {   // it needs to be overrided because there is a virtual function in ComsumerBaseV2 file
        uint256 indexOfWinner = randomWords[0] % s_players.length; // randomWords is the number
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN; //reset
        s_players = new address payable[](0); //reset
        s_lastTimeStamp=block.timestamp;
        (bool success, )= recentWinner.call{value: address(this).balance}(""); // value: address(this).balance is all of money in this contract
        // require(success)
        if(!success){
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
        
    } 


    /*view / Pure functions */
    // every variable that need the user know
    function getEntranceFee() public view returns(uint256){
        return i_entranceFee;
    }
    function getPlayer(uint256 index) public view returns(address){
        return s_players[index];
    }
    function getRecentWinner() public view returns(address){
        return s_recentWinner;
    }
    function getRaffleState() public view returns(RaffleState){
        return s_raffleState;
    }

    function getNumWords() public pure returns(uint256){//a function that doesn’t read or modify the variables of the state is called a pure function
        return NUM_WORDS;
    }
    function getNumberOfPlayers() public view returns(uint256){
        return s_players.length;
    }
    function getLatestTimeStamp() public view returns(uint256){
        return s_lastTimeStamp;

    }
    function getResponseConfirmations() public pure returns(uint256){
        return REQUEST_CONFIRMATIONS;
    }
    function getInterval() public view returns(uint256){
        return i_interval;
    }
}