pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "../RocketBase.sol";
import "../../interface/token/RocketTokenRPLInterface.sol";
import "../../interface/rewards/RocketRewardsPoolInterface.sol";
import "../../interface/settings/RocketDAOSettingsInterface.sol";
import "../../interface/RocketVaultInterface.sol";
import "../../interface/RocketVaultWithdrawerInterface.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";


// Holds RPL generated by the network for claiming from stakers (node operators etc)

contract RocketRewardsPool is RocketBase, RocketRewardsPoolInterface {

    // Libs
    using SafeMath for uint;

    // The names of contracts that can claim
    mapping(string => bool) claimingContracts;

    // Events
    event RPLTokensClaimed(address indexed claimingContract, address indexed claimingAddress, uint256 amount, uint256 time);  
    
    // Modifiers

    /**
    * @dev Throws if called by any sender that doesn't match a Rocket Pool claim contract
    */
    modifier onlyClaimContract() {
        // Will also throw if not a registered network contract or an old upgraded one
        RocketDAOSettingsInterface daoSettings = RocketDAOSettingsInterface(getContractAddress('rocketDAOSettings'));
        // They need a set claim amount > 0 to make a claim
        require(daoSettings.getRewardsClaimerPerc(getContractName(msg.sender)) > 0, "Not a valid rewards claiming contact");
        _;
    }


    // Construct
    constructor(address _rocketStorageAddress) RocketBase(_rocketStorageAddress) public {
        // Version
        version = 1;
        // Set the claim interval start block as the deployment block
        setUintS("rewards.pool.claim.interval.block.start", block.number);
    }

    /**
    * Get the starting block for this claim interval
    * @return uint256 Starting block for this claim interval
    */
    function getClaimIntervalBlockStart() override public view returns(uint256) {
        return getUintS("rewards.pool.claim.interval.block.start");
    }

    /**
    * Get how many blocks in a claim interval
    * @return uint256 Number of blocks in a claim interval
    */
    function getClaimIntervalBlocks() override public view returns(uint256) {
        // Get from the DAO settings
        RocketDAOSettingsInterface daoSettings = RocketDAOSettingsInterface(getContractAddress('rocketDAOSettings'));
        return daoSettings.getRewardsClaimIntervalBlocks();
    }

    /**
    * Get the last block a claim was made
    * @return uint256 Last block a claim was made
    */
    function getClaimBlockLastMade() override public view returns(uint256) {
        return getUintS("rewards.pool.claim.interval.block.last");
    }


    /**
    * Compute intervals since last claim period
    * @return uint256 Time intervals since last update
    */
    function getClaimIntervalsPassed() override public view returns(uint256) {
        // Calculate now if inflation has begun
        return block.number.sub(getClaimIntervalBlockStart()).div(getClaimIntervalBlocks());
    }

    /**
    * The current claim amount for this interval
    * @return uint256 The current claim amount for this interval for the claiming contract
    */
    function getClaimIntervalContractPerc(address _claimingContract) override public view returns(uint256) {
        // Get the dao settings contract instance
        RocketDAOSettingsInterface daoSettings = RocketDAOSettingsInterface(getContractAddress('rocketDAOSettings'));
        return getClaimIntervalsPassed() > 0 ? daoSettings.getRewardsClaimerPerc(getContractName(_claimingContract)) : getUint(keccak256(abi.encodePacked("rewards.pool.claim.interval.contract.perc", _claimingContract)));
    }

    /**
    * Has this user claimed from this claiming contract successfully before?
    * @return bool Returns true if they have made a claim beofer
    */
    function getClaimedBefore(address _claimingContract, address _claimerAddress) override public view returns(bool) {
        // Check per contract
        return getBool(keccak256(abi.encodePacked("rewards.pool.claim.contract.successful", _claimingContract, _claimerAddress)));
    }

    /**
    * Can this user do a successful claim now?
    * @return bool Returns true if this user can do a claim for this interval
    
    function getClaimIntervalPossible(address _claimingContract, address _claimerAddress) override public view returns(bool) {
        // First check to see if this user has claimed before, if not they need to wait until the next interval
        //if(!getClaimedBefore())
        // Check per contract
        return getBool(keccak256(abi.encodePacked("rewards.pool.claim.contract.successful", _claimingContract, _claimerAddress)));
    }*/

    /**
    * Have they claimed already during this interval? 
    * @return bool Returns true if they can claim during this interval
    */
    function getClaimIntervalHasClaimed(uint256 _claimIntervalStartBlock, address _claimingContract, address _claimerAddress) override public view returns(bool) {
        // Check per contract
        return getBool(keccak256(abi.encodePacked("rewards.pool.claim.interval.claimer.address", _claimIntervalStartBlock, _claimingContract, _claimerAddress)));
    }

    /**
    * Get the approx amount of rewards available for this claim interval
    * @return uint256 Rewards amount for current claim interval
    */
    function getClaimIntervalRewardsTotal() override public view returns(uint256) {
        // Get the RPL contract instance
        RocketTokenRPLInterface rplContract = RocketTokenRPLInterface(getContractAddress('rocketTokenRPL'));
        // Get the vault contract instance
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress('rocketVault'));
        // Rewards amount
        uint256 rewardsTotal = 0;
        // Is this the first claim of this interval? If so, calculate expected inflation RPL + any RPL already in the pool
        if(getClaimIntervalsPassed() > 0) {
            // Get the balance of tokens that will be transferred to the vault for this contract when the first claim is made
            // Also account for any RPL tokens already in the vault for the rewards pool
            rewardsTotal = rplContract.inflationCalculate().add(rocketVault.balanceOfToken('rocketRewardsPool', getContractAddress('rocketTokenRPL')));
        }else{
            // Claims have already been made, lets retrieve rewards total stored on first claim of this interval
            rewardsTotal = getUintS("rewards.pool.claim.interval.total");
        }
        // Done
        return rewardsTotal;
    }
    
    // How much this claimer is entitled to claim, returns 0 if they have already claimed or the claimer contract perc is 0
    function getClaimAmount(address _claimContract, address _claimerAddress, uint256 _claimerAmountPerc) override public view returns (uint256) { 
        // Our base calc
        uint256 calcBase = 1 ether; 
        // Get the amount allocated to this claim contract
        uint256 claimContractPerc = getClaimIntervalContractPerc(_claimContract);
        // How much rewards are available for this claim interval?
        uint256 claimIntervalRewardsTotal = getClaimIntervalRewardsTotal();
        // How much this claiming contract is entitled too in perc
        uint256 contractClaimTotal = 0;
        // How much of the above that this claimer will receive
        uint256 claimerTotal = 0;
        // Are we good to proceed?
        if(claimContractPerc > 0 && _claimerAmountPerc > 0 && _claimerAmountPerc <= 1 ether && claimIntervalRewardsTotal > 0 && !getClaimIntervalHasClaimed(getClaimIntervalBlockStart(), _claimContract, _claimerAddress)) {
            // Calculate how much rewards this claimer will receive based on their claiming perc
            contractClaimTotal = claimContractPerc.mul(claimIntervalRewardsTotal).div(calcBase);
            // Now calculate how much this claimer would receive 
            claimerTotal = _claimerAmountPerc.mul(contractClaimTotal).div(calcBase);
        }
        // Done
        return claimerTotal;
    }

    // A claiming contract claiming for a user and the amount of rewards they need
    function claim(address _claimerAddress, uint256 _claimerAmount) override external onlyClaimContract {
        // First initial checks
        require(_claimerAmount > 0 && _claimerAmount <= 1 ether, "Claimer must claim more than zero and less than 100%");
        require(_claimerAddress != address(0x0), "Claimer address is not valid");
        // Cannot claim more than once per interval per claiming contract
        require(!getClaimIntervalHasClaimed(getClaimIntervalBlockStart(), msg.sender, _claimerAddress), "Address has already claimed during this claiming interval");
        // Have they claimed before? If not they must wait one whole interval before they can claim

        // RPL contract address
        address rplContractAddress = getContractAddress('rocketTokenRPL');
        // Get the dao settings contract instance
        RocketDAOSettingsInterface daoSettings = RocketDAOSettingsInterface(getContractAddress('rocketDAOSettings'));
        // RPL contract instance
        RocketTokenRPLInterface rplContract = RocketTokenRPLInterface(rplContractAddress);
        // Get the vault contract instance
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress('rocketVault'));
        // Get the start of the last claim interval
        uint256 claimIntervalBlockStart = getClaimIntervalBlockStart();
        // Is this the first claim of this interval? If so, set the rewards total for this interval
        if(getClaimIntervalsPassed() > 0) {
            // Get the amount allocated to this claim contract
            uint256 claimContractPerc = daoSettings.getRewardsClaimerPerc(getContractName(msg.sender));
            // Make sure this is ok
            require(claimContractPerc > 0 && claimContractPerc <= 1 ether, "Claiming contract cannot claim more than 100%");
            // Check if any inflation intervals have passed and only mint if needed to the vault before we record the total RPL available for this interval
            if(rplContract.getInlfationIntervalsPassed() > 0) rplContract.inflationMintTokens();
            // Get how many tokens are in the reward pool to be available for this claim period
            setUintS("rewards.pool.claim.interval.total", rocketVault.balanceOfToken('rocketRewardsPool', rplContractAddress));
            // Set this as the start of the next claim interval
            setUintS("rewards.pool.claim.interval.block.start", claimIntervalBlockStart.add(getClaimIntervalBlocks().mul(getClaimIntervalsPassed())));
            // Set the current claim amount perc for this contract for this claim interval (if the claim amount is changed, it will kick in on the next interval)
            setUint(keccak256(abi.encodePacked("rewards.pool.claim.interval.contract.perc", msg.sender)), claimContractPerc);
        }
        // How much are they claiming?
        uint256 claimerAddressTokens = getClaimAmount(msg.sender, _claimerAddress, _claimerAmount);
        // Send the tokens to the claiming address now
        require(claimerAddressTokens > 0, "Claiming address is not entitled to any tokens");
        // Send tokens now
        rocketVault.withdrawToken(rplContractAddress, claimerAddressTokens);
        // Store the claiming record for this interval and claiming contract
        setBool(keccak256(abi.encodePacked("rewards.pool.claim.interval.claimer.address", getClaimIntervalBlockStart(), msg.sender, _claimerAddress)), true);
        // Also store it as having made a claim before
        setBool(keccak256(abi.encodePacked("rewards.pool.claim.contract.successful", msg.sender, _claimerAddress)), true);
        // Store the last block a claim was made
        setUintS("rewards.pool.claim.interval.block.last", block.number);
        // Log it
        emit RPLTokensClaimed(msg.sender, _claimerAddress, claimerAddressTokens, now);
    }

}
