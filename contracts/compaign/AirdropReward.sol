// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from  "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Pausable.sol";

interface IMintERC20 {
    function mint(address to, uint256 amount) external;
}

contract AirdropReward is OwnableUpgradeable, Pausable, ReentrancyGuard {
    event UpdateMerkleRoot(uint256 indexed rewardId, uint256 indexed epoch, uint256 epochEnd, bytes32 oldRoot, bytes32 newRoot, uint256 timestamp, string merklePath);
    event UpdateReward(uint256 indexed rewardId, uint256 indexed epoch, uint256 acquireMethod, uint256 indexed amount, uint256 balance, uint256 totalDistributed, uint256 timestamp);
    event ClaimReward(uint256 indexed rewardId, uint256 indexed epoch, address indexed recipient, uint256 amount, uint256 timestamp, uint256 totalClaimed);
    event Transfer(uint256 indexed rewardId, uint256 indexed epoch, uint256 indexed amount, address recipient, uint256 timestamp);

    struct ClaimInfo {
        uint256 amount;
        uint256 timestamp;
    }

    struct RewardInfo {
        uint256 epoch;
        uint256 epochEnd;
        uint256 acquireMethod;
        bytes32 merkleRoot;
        string merklePath;
        uint256 totalDistributed;
        uint256 remainDistributed;
        uint256 balanceUpdatedAt;
        uint256 rootUpdatedAt;
        address token;
        address mintToken;
    }

    // admin address which can propose adding a new merkle root
    address public proposalAuthority;

    address public rewardSponsor;

    address public multisigWallet;
   
    mapping(uint256 => mapping(uint256 => RewardInfo)) public rewardInfos;
    // mapping(uint256 => mapping(address => ClaimInfo)) public claims;
    mapping(address => mapping(uint256 => mapping (uint256 => ClaimInfo))) public claims;
    mapping(uint256 => uint256) public lastEpochs;


    modifier onlyValidAddress(address addr) {
        require(addr != address(0), "Illegal address");
        _;
    }

    constructor(address _multisigWallet) {
        multisigWallet = _multisigWallet;
    }

    function initialize(address _proposalAuthority, address _rewardSponsor) onlyValidAddress(_proposalAuthority) onlyValidAddress(_rewardSponsor) external virtual initializer {
        proposalAuthority = _proposalAuthority;
        rewardSponsor = _rewardSponsor;

        // Initialize OZ contracts
        __Ownable_init_unchained(msg.sender);
    }

    function setProposalAuthority(address _account) onlyValidAddress(_account) public onlyOwner {
        proposalAuthority = _account;
    }

    function setRewardSponsor(address _account) onlyValidAddress(_account) public onlyOwner {
        rewardSponsor = _account;
    }

    function setMultisigWallet(address _account) onlyValidAddress(_account) public onlyOwner {
        multisigWallet = _account;
    }
 
    function receiveTokenReward(uint256 rewardId, uint256 epoch, address from, address tokenAddress, uint256 amount) external {
        require(msg.sender == rewardSponsor, "Thank you for your support, but you are not Sponsor");
        require(from != address(0), "From address cannot be zero");
        require(amount > 0, "Rewards must be greater than 0");
        
        uint256 acquireMethod = 1;
        _receiveReward(rewardId, epoch, acquireMethod, from, tokenAddress, address(0), amount);
    }

    function receiveMintTokenReward(uint256 rewardId, uint256 epoch, address mintTokenAddress, uint256 amount) external {
        require(msg.sender == rewardSponsor, "Thank you for your support, but you are not Sponsor");
        require(amount > 0, "Rewards must be greater than 0");

        uint256 acquireMethod = 2;
        _receiveReward(rewardId, epoch, acquireMethod, address(0), address(0), mintTokenAddress, amount);
    }

    function receiveReward(uint256 rewardId, uint256 epoch) payable external {
        require(msg.sender == rewardSponsor, "Thank you for your support, but you are not Sponsor");
        require(msg.value > 0, "Rewards must be greater than 0");
        
        uint256 acquireMethod = 3;
        _receiveReward(rewardId, epoch, acquireMethod, address(0), address(0), address(0), msg.value);
    }

    function _receiveReward(uint256 rewardId, uint256 epoch, uint256 acquireMethod, address from, address tokenAddress, address mintTokenAddress, uint256 amount) internal {
        require(acquireMethod == 1 || acquireMethod == 2 || acquireMethod == 3, "Invalid acquire method");
        
        RewardInfo storage rewardInfo = rewardInfos[rewardId][epoch];
        if (acquireMethod == 1) {
            require(tokenAddress != address(0), "Token address cannot be zero");
            IERC20 token = IERC20(tokenAddress);
            require(token.transferFrom(from, address(this), amount), "Token transfer failed");
        } else if (acquireMethod == 2) {
            require(mintTokenAddress != address(0), "Mint token address cannot be zero");
        } else if (acquireMethod == 3) {
            require(msg.value == amount, "Incorrect amount");
        }
      
        rewardInfo.epoch = epoch;
        rewardInfo.acquireMethod = acquireMethod;
        rewardInfo.totalDistributed += amount;
        rewardInfo.remainDistributed += amount;
        rewardInfo.balanceUpdatedAt = block.timestamp;
        rewardInfo.token = tokenAddress;
        rewardInfo.mintToken = mintTokenAddress;
        
        emit UpdateReward(rewardId, epoch, acquireMethod, amount, address(this).balance, rewardInfos[rewardId][epoch].totalDistributed, block.timestamp);
    }

    function getLastEpochReward(uint256 rewardId) public view returns (RewardInfo memory) {
        uint256 lastEpoch = lastEpochs[rewardId];
        return rewardInfos[rewardId][lastEpoch];
    }

    function getRewardForEpoch(uint256 rewardId, uint256 epoch) public view returns (uint256 claimed, uint256 totalClaimed) {
        claimed = claims[msg.sender][rewardId][epoch].amount;
        totalClaimed = claims[msg.sender][rewardId][0].amount;
        return (claimed, totalClaimed);
    }

    function _verify(uint256 rewardId, uint256 epoch, address addr, uint256 amount, bytes32[] calldata proof) view internal {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));
        require(MerkleProof.verify(proof, rewardInfos[rewardId][epoch].merkleRoot, leaf), "Invalid proof");
    }

    function claimReward(uint256 rewardId, uint256 epoch, uint256 amount, bytes32[] calldata proof) external whenNotPaused nonReentrant {
        _verify(rewardId, epoch, msg.sender, amount, proof);

        ClaimInfo storage userClaim = claims[msg.sender][rewardId][epoch];
        require(userClaim.amount < amount, "You have already claimed your reward");

        RewardInfo storage rewardInfo = rewardInfos[rewardId][epoch];
        require(rewardInfo.remainDistributed >= amount, "Insufficient remaining rewards");
        require(rewardInfo.epoch <= block.timestamp, "The claim period has not started yet");
        require(rewardInfo.epochEnd == 0 || rewardInfo.epochEnd >= block.timestamp, "You have exceeded the claim time"); 

        userClaim.amount += amount;
        userClaim.timestamp = block.timestamp;
        claims[msg.sender][rewardId][0].amount += amount;
        claims[msg.sender][rewardId][0].timestamp = block.timestamp;

        if (rewardInfo.acquireMethod == 1) {
            IERC20 token = IERC20(rewardInfo.token);
            require(token.transfer(msg.sender, amount), "Token transfer failed");
        } else if (rewardInfo.acquireMethod == 2) {
            IMintERC20 mintToken = IMintERC20(rewardInfo.mintToken);
            mintToken.mint(msg.sender, amount);
        } else if (rewardInfo.acquireMethod == 3) {
            payable(msg.sender).transfer(amount);
        }
        rewardInfo.remainDistributed -= amount;
        
        emit ClaimReward(rewardId, epoch, msg.sender, amount, block.timestamp, claims[msg.sender][rewardId][0].amount);
    }

    function proposerMerkleRoot(uint256 rewardId, uint256 epoch, uint256 epochEnd, bytes32 _merkleRoot, string calldata _merklePath) public {
        require(msg.sender == proposalAuthority, "Caller is not the proposer");
        require(_merkleRoot != 0x00, "Illegal root");
        require(epochEnd == 0 || epochEnd > epoch, "Epoch end must be greater than epoch"); 
        require(rewardInfos[rewardId][epoch].totalDistributed > 0, "The reward has not been distributed");

        bytes32 oldRoot = rewardInfos[rewardId][epoch].merkleRoot;
        rewardInfos[rewardId][epoch].epoch = epoch;
        rewardInfos[rewardId][epoch].epochEnd = epochEnd;
        rewardInfos[rewardId][epoch].merkleRoot = _merkleRoot;
        rewardInfos[rewardId][epoch].merklePath = _merklePath;
        rewardInfos[rewardId][epoch].rootUpdatedAt = block.timestamp;
        emit UpdateMerkleRoot(rewardId, epoch, epochEnd, oldRoot, _merkleRoot, block.timestamp, _merklePath);
        
        uint256 lastEpoch = lastEpochs[rewardId];
        RewardInfo storage lastReward = rewardInfos[rewardId][lastEpoch];
        if (epoch > lastEpoch) {
             // transfer remaining rewards
            if (lastReward.remainDistributed > 0) {
                if (lastReward.acquireMethod == 1) {
                    IERC20 token = IERC20(lastReward.token);
                    require(token.transfer(multisigWallet, lastReward.remainDistributed), "Token transfer failed");
                    emit Transfer(rewardId, lastReward.epoch, lastReward.remainDistributed, multisigWallet, block.timestamp);
                } else if (lastReward.acquireMethod == 3) {
                    payable(multisigWallet).transfer(lastReward.remainDistributed);
                    emit Transfer(rewardId, lastReward.epoch, lastReward.remainDistributed, multisigWallet, block.timestamp);
                }
                lastReward.remainDistributed = 0;
            }
            // last epoch
            lastEpochs[rewardId] = epoch;
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}