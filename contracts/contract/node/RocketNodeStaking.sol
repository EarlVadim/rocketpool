pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../RocketBase.sol";
import "../../interface/node/RocketNodeStakingInterface.sol";
import "../../interface/RocketVaultInterface.sol";

// Handles node deposits and minipool creation

contract RocketNodeStaking is RocketBase, RocketNodeStakingInterface {

    // Libs
    using SafeMath for uint;

    // Construct
    constructor(address _rocketStorageAddress) RocketBase(_rocketStorageAddress) public {
        version = 1;
    }

    // Get/set the total RPL stake amount
    function getTotalRPLStake() override public view returns (uint256) {
        return getUint(keccak256(abi.encodePacked("rpl.staked.total")));
    }
    function setTotalRPLStake(uint256 _amount) private {
        setUint(keccak256(abi.encodePacked("rpl.staked.total")), _amount);
    }

    // Get/set a node's RPL stake amount
    function getNodeRPLStake(address _nodeAddress) override public view returns (uint256) {
        return getUint(keccak256(abi.encodePacked("rpl.staked.node", _nodeAddress)));
    }
    function setNodeRPLStake(address _nodeAddress, uint256 _amount) private {
        setUint(keccak256(abi.encodePacked("rpl.staked.node", _nodeAddress)), _amount);
    }

    // Accept an RPL stake
    // Only accepts calls from registered nodes
    function stakeRPL(uint256 _amount) override external payable onlyLatestContract("rocketNodeStaking", address(this)) onlyRegisteredNode(msg.sender) {
        // Load contracts
        address rplTokenAddress = getContractAddress("rocketTokenRPL");
        address rocketVaultAddress = getContractAddress("rocketVault");
        IERC20 rplToken = IERC20(rplTokenAddress);
        RocketVaultInterface rocketVault = RocketVaultInterface(rocketVaultAddress);
        // Transfer RPL tokens
        require(rplToken.transferFrom(msg.sender, address(this), _amount), "Could not transfer RPL to staking contract");
        // Deposit RPL tokens to vault
        require(rplToken.approve(rocketVaultAddress, _amount), "Could not approve vault RPL deposit");
        rocketVault.depositToken("rocketNodeStaking", rplTokenAddress, _amount);
        // Update RPL stake amounts
        increaseTotalRPLStake(_amount);
        increaseNodeRPLStake(msg.sender, _amount);
    }

    // Increase/decrease the total RPL stake amount
    function increaseTotalRPLStake(uint256 _amount) private {
        setTotalRPLStake(getTotalRPLStake().add(_amount));
    }
    function decreaseTotalRPLStake(uint256 _amount) private {
        setTotalRPLStake(getTotalRPLStake().sub(_amount));
    } 

    // Increase/decrease a node's RPL stake amount
    function increaseNodeRPLStake(address _nodeAddress, uint256 _amount) private {
        setNodeRPLStake(_nodeAddress, getNodeRPLStake(_nodeAddress).add(_amount));
    }
    function decreaseNodeRPLStake(address _nodeAddress, uint256 _amount) private {
        setNodeRPLStake(_nodeAddress, getNodeRPLStake(_nodeAddress).sub(_amount));
    } 

}