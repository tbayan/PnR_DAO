// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title PnRDAO - Punishment not Reward Decentralized Autonomous Organization
 * @dev Implementation of PnR governance model using dual NFT architecture
 * @notice This contract implements the theoretical framework presented in Chapter 5
 */
contract PnRDAO is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // State variables
    Counters.Counter private _proposalIds;
    Counters.Counter private _dealIds;
    
    // Core contracts
    AuthenticationNFT public authNFT;
    PrivateInteractionNFT public privNFT;
    
    // Governance parameters
    uint256 public constant QUORUM_PERCENTAGE = 50; // 50% quorum requirement
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant DISPUTE_PERIOD = 3 days;
    
    // Structs
    struct Member {
        address memberAddress;
        bytes32 identityCommitment; // Commitment to real identity
        uint256 reputation;
        bool isActive;
        uint256 joinTimestamp;
    }
    
    struct Proposal {
        uint256 proposalId;
        address proposer;
        address targetMember;
        string description;
        uint256 voteDeadline;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        ProposalType proposalType;
        mapping(address => bool) hasVoted;
    }
    
    struct PrivateDeal {
        uint256 dealId;
        address buyer;
        address seller;
        uint256 amount;
        uint256 deadline;
        string serviceDescription;
        DealStatus status;
        address disputeInitiator;
    }
    
    enum ProposalType { REMOVE_MEMBER, GENERAL_GOVERNANCE }
    enum DealStatus { ACTIVE, COMPLETED, DISPUTED, CANCELLED }
    
    // Mappings
    mapping(address => Member) public members;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => PrivateDeal) public privateDeals;
    mapping(address => bool) public verifiedIdentities; // Simulates DKYC results
    
    // Arrays
    address[] public memberList;
    
    // Events
    event MemberJoined(address indexed member, bytes32 identityCommitment);
    event MemberRemoved(address indexed member, string reason);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, address indexed target);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId, bool passed);
    event PrivateDealCreated(uint256 indexed dealId, address indexed buyer, address indexed seller);
    event DealCompleted(uint256 indexed dealId);
    event DisputeInitiated(uint256 indexed dealId, address indexed initiator);
    event IdentityRevealed(address indexed member, string realIdentity);
    
    constructor() {
        authNFT = new AuthenticationNFT(address(this));
        privNFT = new PrivateInteractionNFT(address(this));
    }
    
    /**
     * @dev Join DAO after identity verification (simulated DKYC)
     * @param identityCommitment Cryptographic commitment to real identity
     */
    function joinDAO(bytes32 identityCommitment) external {
        require(!members[msg.sender].isActive, "Already a member");
        require(verifiedIdentities[msg.sender], "Identity not verified");
        
        members[msg.sender] = Member({
            memberAddress: msg.sender,
            identityCommitment: identityCommitment,
            reputation: 100, // Starting reputation
            isActive: true,
            joinTimestamp: block.timestamp
        });
        
        memberList.push(msg.sender);
        authNFT.mintAuthenticationNFT(msg.sender);
        
        emit MemberJoined(msg.sender, identityCommitment);
    }
    
    /**
     * @dev Simulate DKYC verification for demonstration
     * @param user Address to verify
     */
    function simulateDKYC(address user) external onlyOwner {
        verifiedIdentities[user] = true;
    }
    
    /**
     * @dev Create proposal to remove member (core PnR mechanism)
     * @param targetMember Address of member to remove
     * @param description Reason for removal
     */
    function createRemovalProposal(address targetMember, string memory description) external {
        require(members[msg.sender].isActive, "Only active members can propose");
        require(members[targetMember].isActive, "Target is not active member");
        require(targetMember != msg.sender, "Cannot propose self-removal");
        
        _proposalIds.increment();
        uint256 proposalId = _proposalIds.current();
        
        Proposal storage newProposal = proposals[proposalId];
        newProposal.proposalId = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.targetMember = targetMember;
        newProposal.description = description;
        newProposal.voteDeadline = block.timestamp + VOTING_PERIOD;
        newProposal.proposalType = ProposalType.REMOVE_MEMBER;
        
        emit ProposalCreated(proposalId, msg.sender, targetMember);
    }
    
    /**
     * @dev Cast vote on removal proposal
     * @param proposalId ID of proposal to vote on
     * @param support True for yes, false for no
     */
    function vote(uint256 proposalId, bool support) external {
        require(members[msg.sender].isActive, "Only active members can vote");
        require(block.timestamp <= proposals[proposalId].voteDeadline, "Voting period ended");
        require(!proposals[proposalId].hasVoted[msg.sender], "Already voted");
        require(proposals[proposalId].proposer != address(0), "Proposal does not exist");
        
        proposals[proposalId].hasVoted[msg.sender] = true;
        
        if (support) {
            proposals[proposalId].yesVotes++;
        } else {
            proposals[proposalId].noVotes++;
        }
        
        emit VoteCast(proposalId, msg.sender, support);
    }
    
    /**
     * @dev Execute removal proposal if conditions met
     * @param proposalId ID of proposal to execute
     */
    function executeRemovalProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.voteDeadline, "Voting still active");
        require(!proposal.executed, "Proposal already executed");
        
        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
        uint256 requiredQuorum = (memberList.length * QUORUM_PERCENTAGE) / 100;
        
        proposal.executed = true;
        
        bool passed = totalVotes >= requiredQuorum && proposal.yesVotes > proposal.noVotes;
        
        if (passed) {
            _removeMember(proposal.targetMember, proposal.description);
        }
        
        emit ProposalExecuted(proposalId, passed);
    }
    
    /**
     * @dev Internal function to remove member (punishment mechanism)
     * @param member Address of member to remove
     * @param reason Reason for removal
     */
    function _removeMember(address member, string memory reason) internal {
        require(members[member].isActive, "Member not active");
        
        members[member].isActive = false;
        members[member].reputation = 0;
        
        // Burn authentication NFT (soulbound characteristic)
        authNFT.burnToken(member);
        
        // Remove from member list
        for (uint i = 0; i < memberList.length; i++) {
            if (memberList[i] == member) {
                memberList[i] = memberList[memberList.length - 1];
                memberList.pop();
                break;
            }
        }
        
        emit MemberRemoved(member, reason);
    }
    
    /**
     * @dev Create private deal between members
     * @param seller Address of service provider
     * @param serviceDescription Description of service
     * @param deadline Service completion deadline
     */
    function createPrivateDeal(
        address seller,
        string memory serviceDescription,
        uint256 deadline
    ) external payable {
        require(members[msg.sender].isActive, "Buyer must be active member");
        require(members[seller].isActive, "Seller must be active member");
        require(deadline > block.timestamp, "Deadline must be in future");
        require(msg.value > 0, "Payment required");
        
        _dealIds.increment();
        uint256 dealId = _dealIds.current();
        
        privateDeals[dealId] = PrivateDeal({
            dealId: dealId,
            buyer: msg.sender,
            seller: seller,
            amount: msg.value,
            deadline: deadline,
            serviceDescription: serviceDescription,
            status: DealStatus.ACTIVE,
            disputeInitiator: address(0)
        });
        
        // Mint private interaction NFTs for both parties
        privNFT.mintPrivateNFT(msg.sender, dealId);
        privNFT.mintPrivateNFT(seller, dealId);
        
        emit PrivateDealCreated(dealId, msg.sender, seller);
    }
    
    /**
     * @dev Complete private deal (seller confirms completion)
     * @param dealId ID of deal to complete
     */
    function completeDeal(uint256 dealId) external nonReentrant {
        PrivateDeal storage deal = privateDeals[dealId];
        require(deal.seller == msg.sender, "Only seller can complete");
        require(deal.status == DealStatus.ACTIVE, "Deal not active");
        require(block.timestamp <= deal.deadline, "Deal expired");
        
        deal.status = DealStatus.COMPLETED;
        
        // Transfer payment to seller
        payable(deal.seller).transfer(deal.amount);
        
        // Update reputation
        members[deal.seller].reputation += 5;
        
        emit DealCompleted(dealId);
    }
    
    /**
     * @dev Initiate dispute for private deal
     * @param dealId ID of deal to dispute
     */
    function initiateDealDispute(uint256 dealId) external {
        PrivateDeal storage deal = privateDeals[dealId];
        require(deal.buyer == msg.sender || deal.seller == msg.sender, "Not party to deal");
        require(deal.status == DealStatus.ACTIVE, "Deal not active");
        
        deal.status = DealStatus.DISPUTED;
        deal.disputeInitiator = msg.sender;
        
        // Reduce reputation of both parties pending resolution
        members[deal.buyer].reputation -= 2;
        members[deal.seller].reputation -= 2;
        
        emit DisputeInitiated(dealId, msg.sender);
    }
    
    /**
     * @dev Get member count for quorum calculations
     */
    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }
    
    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 proposalId) external view returns (
        address proposer,
        address targetMember,
        string memory description,
        uint256 voteDeadline,
        uint256 yesVotes,
        uint256 noVotes,
        bool executed
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.proposer,
            proposal.targetMember,
            proposal.description,
            proposal.voteDeadline,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.executed
        );
    }
    
    /**
     * @dev Emergency identity reveal (extreme punishment)
     * @param member Address of member whose identity to reveal
     * @param realIdentity Real identity to reveal
     */
    function revealIdentity(address member, string memory realIdentity) external onlyOwner {
        require(!members[member].isActive, "Can only reveal removed members");
        emit IdentityRevealed(member, realIdentity);
    }
}

/**
 * @title AuthenticationNFT - Soulbound authentication tokens
 * @dev Non-transferable NFTs representing DAO membership
 */
contract AuthenticationNFT is ERC721, ERC721Burnable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    
    address public daoContract;
    mapping(address => uint256) public memberTokens;
    
    constructor(address _daoContract) ERC721("PnR Authentication", "AUTH") {
        daoContract = _daoContract;
    }
    
    modifier onlyDAO() {
        require(msg.sender == daoContract, "Only DAO can call");
        _;
    }
    
    function mintAuthenticationNFT(address to) external onlyDAO {
        require(memberTokens[to] == 0, "Member already has token");
        
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        
        _safeMint(to, tokenId);
        memberTokens[to] = tokenId;
    }
    
    function burnToken(address member) external onlyDAO {
        uint256 tokenId = memberTokens[member];
        require(tokenId != 0, "No token to burn");
        
        _burn(tokenId);
        memberTokens[member] = 0;
    }
    
    // Override transfer functions to make soulbound
    function transferFrom(address, address, uint256) public pure override {
        revert("Soulbound: Transfer not allowed");
    }
    
    function safeTransferFrom(address, address, uint256) public pure override {
        revert("Soulbound: Transfer not allowed");
    }
    
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert("Soulbound: Transfer not allowed");
    }
}

/**
 * @title PrivateInteractionNFT - NFTs for private deals
 * @dev Represents participation in private transactions
 */
contract PrivateInteractionNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    
    address public daoContract;
    mapping(uint256 => uint256) public dealTokens; // dealId => tokenId
    
    constructor(address _daoContract) ERC721("PnR Private Interaction", "PRIV") {
        daoContract = _daoContract;
    }
    
    modifier onlyDAO() {
        require(msg.sender == daoContract, "Only DAO can call");
        _;
    }
    
    function mintPrivateNFT(address to, uint256 dealId) external onlyDAO {
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        
        _safeMint(to, tokenId);
        dealTokens[dealId] = tokenId;
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        // In production, this would return metadata including deal information
        return string(abi.encodePacked(
            "data:application/json;base64,",
            "eyJuYW1lIjoiUHJpdmF0ZSBEZWFsIE5GVCIsImRlc2NyaXB0aW9uIjoiUmVwcmVzZW50cyBwYXJ0aWNpcGF0aW9uIGluIGEgcHJpdmF0ZSBkZWFsIn0="
        ));
    }
}
