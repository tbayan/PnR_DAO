// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PnRDAO is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // State variables
    Counters.Counter private _proposalIds;
    Counters.Counter private _dealIds;
    
    // Core contracts
    AuthenticationNFT public authNFT;
    PrivateInteractionNFT public privNFT;
    
    // Governance parameters
    uint256 public constant QUORUM_PERCENTAGE = 50;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant DISPUTE_PERIOD = 3 days;
    uint256 public constant MIN_REPUTATION = 50;
    
    // Enhanced member structure
    struct Member {
        address memberAddress;
        bytes32 identityCommitment;
        uint256 reputation;
        bool isActive;
        uint256 joinTimestamp;
        mapping(uint256 => bool) restrictedInteractions; // Token type restrictions
        uint256 warningCount;
        uint256 lastActivityTimestamp;
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
        PunishmentSeverity severity;
        mapping(address => bool) hasVoted;
        bytes32 evidenceRoot; // Merkle root for evidence
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
        uint256 interactionType;
        bytes32 privacyCommitment;
        uint256 collateralRequired;
    }
    
    enum ProposalType { REMOVE_MEMBER, RESTRICT_INTERACTIONS, REPUTATION_PENALTY, GENERAL_GOVERNANCE }
    enum DealStatus { ACTIVE, COMPLETED, DISPUTED, CANCELLED, EXPIRED }
    enum PunishmentSeverity { WARNING, RESTRICTION, REMOVAL, IDENTITY_REVEAL }
    
    // Mappings
    mapping(address => Member) public members;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => PrivateDeal) public privateDeals;
    mapping(address => bool) public verifiedIdentities;
    mapping(address => bytes32[]) public privacyCommitments;
    mapping(bytes32 => bool) public revealedCommitments;
    
    // Arrays
    address[] public memberList;
    
    // Events
    event MemberJoined(address indexed member, bytes32 identityCommitment);
    event MemberRemoved(address indexed member, string reason);
    event MemberRestricted(address indexed member, uint256 interactionType, string reason);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, address indexed target, ProposalType proposalType);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId, bool passed);
    event PrivateDealCreated(uint256 indexed dealId, address indexed buyer, address indexed seller, uint256 interactionType);
    event DealCompleted(uint256 indexed dealId);
    event DisputeInitiated(uint256 indexed dealId, address indexed initiator);
    event IdentityRevealed(address indexed member, string realIdentity, bytes32 commitment);
    event CommitmentForceOpened(address indexed member, bytes32 commitment, string revealedData);
    event BatchPunishmentExecuted(address[] members, uint256 punishmentType);
    
    constructor() {
        authNFT = new AuthenticationNFT(address(this));
        privNFT = new PrivateInteractionNFT(address(this));
    }
    

    function joinDAO(bytes32 identityCommitment, bytes32 privacyCommitment) external {
        require(!members[msg.sender].isActive, "Already a member");
        require(verifiedIdentities[msg.sender], "Identity not verified");
        require(identityCommitment != bytes32(0), "Invalid identity commitment");
        
        Member storage newMember = members[msg.sender];
        newMember.memberAddress = msg.sender;
        newMember.identityCommitment = identityCommitment;
        newMember.reputation = 100; // Starting reputation
        newMember.isActive = true;
        newMember.joinTimestamp = block.timestamp;
        newMember.warningCount = 0;
        newMember.lastActivityTimestamp = block.timestamp;
        
        memberList.push(msg.sender);
        authNFT.mintAuthenticationNFT(msg.sender);
        
        // Store privacy commitments
        privacyCommitments[msg.sender].push(privacyCommitment);
        
        emit MemberJoined(msg.sender, identityCommitment);
    }
    
    function simulateDKYC(address user) external onlyOwner {
        verifiedIdentities[user] = true;
    }
    
    function createProposal(
        address targetMember,
        string memory description,
        ProposalType proposalType,
        PunishmentSeverity severity,
        bytes32 evidenceRoot
    ) external {
        require(members[msg.sender].isActive, "Only active members can propose");
        require(members[targetMember].isActive, "Target is not active member");
        require(targetMember != msg.sender, "Cannot propose against self");
        require(members[msg.sender].reputation >= MIN_REPUTATION, "Insufficient reputation to propose");
        
        _proposalIds.increment();
        uint256 proposalId = _proposalIds.current();
        
        Proposal storage newProposal = proposals[proposalId];
        newProposal.proposalId = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.targetMember = targetMember;
        newProposal.description = description;
        newProposal.voteDeadline = block.timestamp + VOTING_PERIOD;
        newProposal.proposalType = proposalType;
        newProposal.severity = severity;
        newProposal.evidenceRoot = evidenceRoot;
        
        emit ProposalCreated(proposalId, msg.sender, targetMember, proposalType);
    }
    

    function vote(uint256 proposalId, bool support, bytes32[] calldata evidenceProof) external {
        require(members[msg.sender].isActive, "Only active members can vote");
        require(block.timestamp <= proposals[proposalId].voteDeadline, "Voting period ended");
        require(!proposals[proposalId].hasVoted[msg.sender], "Already voted");
        require(proposals[proposalId].proposer != address(0), "Proposal does not exist");
        
        // Verify evidence if provided
        if (evidenceProof.length > 0) {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, support));
            require(
                MerkleProof.verify(evidenceProof, proposals[proposalId].evidenceRoot, leaf),
                "Invalid evidence proof"
            );
        }
        
        proposals[proposalId].hasVoted[msg.sender] = true;
        
        if (support) {
            proposals[proposalId].yesVotes++;
        } else {
            proposals[proposalId].noVotes++;
        }
        
        // Update member activity
        members[msg.sender].lastActivityTimestamp = block.timestamp;
        
        emit VoteCast(proposalId, msg.sender, support);
    }
    

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.voteDeadline, "Voting still active");
        require(!proposal.executed, "Proposal already executed");
        
        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
        uint256 requiredQuorum = (memberList.length * QUORUM_PERCENTAGE) / 100;
        
        proposal.executed = true;
        
        bool passed = totalVotes >= requiredQuorum && proposal.yesVotes > proposal.noVotes;
        
        if (passed) {
            _executePunishment(proposal.targetMember, proposal.proposalType, proposal.severity, proposal.description);
        }
        
        emit ProposalExecuted(proposalId, passed);
    }
    

    function _executePunishment(
        address member,
        ProposalType proposalType,
        PunishmentSeverity severity,
        string memory reason
    ) internal {
        if (proposalType == ProposalType.REMOVE_MEMBER) {
            _removeMember(member, reason);
        } else if (proposalType == ProposalType.RESTRICT_INTERACTIONS) {
            _restrictMemberInteractions(member, severity, reason);
        } else if (proposalType == ProposalType.REPUTATION_PENALTY) {
            _penalizeReputation(member, severity);
        }
        
        if (severity == PunishmentSeverity.IDENTITY_REVEAL) {
            _forceIdentityReveal(member, reason);
        }
    }
    
 
    function _restrictMemberInteractions(address member, PunishmentSeverity severity, string memory reason) internal {
        Member storage targetMember = members[member];
        
        if (severity == PunishmentSeverity.WARNING) {
            targetMember.warningCount++;
        } else if (severity == PunishmentSeverity.RESTRICTION) {
            // Restrict high-risk interactions
            targetMember.restrictedInteractions[privNFT.HIGH_RISK_DEALS()] = true;
            targetMember.warningCount++;
        }
        
        emit MemberRestricted(member, uint256(severity), reason);
    }
    
 
    function _penalizeReputation(address member, PunishmentSeverity severity) internal {
        Member storage targetMember = members[member];
        
        if (severity == PunishmentSeverity.WARNING) {
            targetMember.reputation = targetMember.reputation > 10 ? targetMember.reputation - 10 : 0;
        } else if (severity == PunishmentSeverity.RESTRICTION) {
            targetMember.reputation = targetMember.reputation > 25 ? targetMember.reputation - 25 : 0;
        }
    }
    

    function _forceIdentityReveal(address member, string memory reason) internal {
        bytes32[] memory commitments = privacyCommitments[member];
        for (uint i = 0; i < commitments.length; i++) {
            revealedCommitments[commitments[i]] = true;
            emit CommitmentForceOpened(member, commitments[i], reason);
        }
    }
    

    function _removeMember(address member, string memory reason) internal {
        require(members[member].isActive, "Member not active");
        
        members[member].isActive = false;
        members[member].reputation = 0;
        
        // Burn authentication NFT
        authNFT.burnToken(member);
        
        // Burn all private interaction NFTs
        privNFT.burnAllTokens(member);
        
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
    

    function createPrivateDeal(
        address seller,
        string memory serviceDescription,
        uint256 deadline,
        uint256 interactionType,
        bytes32 privacyCommitment
    ) external payable {
        require(members[msg.sender].isActive, "Buyer must be active member");
        require(members[seller].isActive, "Seller must be active member");
        require(deadline > block.timestamp, "Deadline must be in future");
        require(msg.value > 0, "Payment required");
        require(!members[msg.sender].restrictedInteractions[interactionType], "Interaction type restricted");
        require(!members[seller].restrictedInteractions[interactionType], "Seller restricted from this interaction type");
        
        _dealIds.increment();
        uint256 dealId = _dealIds.current();
        
        uint256 collateralRequired = 0;
        if (interactionType == privNFT.HIGH_RISK_DEALS()) {
            collateralRequired = msg.value / 10; // 10% collateral for high-risk deals
            require(msg.value >= collateralRequired, "Insufficient collateral for high-risk deal");
        }
        
        privateDeals[dealId] = PrivateDeal({
            dealId: dealId,
            buyer: msg.sender,
            seller: seller,
            amount: msg.value,
            deadline: deadline,
            serviceDescription: serviceDescription,
            status: DealStatus.ACTIVE,
            disputeInitiator: address(0),
            interactionType: interactionType,
            privacyCommitment: privacyCommitment,
            collateralRequired: collateralRequired
        });
        
        // Mint private interaction NFTs with specific type
        privNFT.mintPrivateNFT(msg.sender, dealId, interactionType, 1);
        privNFT.mintPrivateNFT(seller, dealId, interactionType, 1);
        
        // Update member activity
        members[msg.sender].lastActivityTimestamp = block.timestamp;
        members[seller].lastActivityTimestamp = block.timestamp;
        
        emit PrivateDealCreated(dealId, msg.sender, seller, interactionType);
    }
    

    function completeDeal(uint256 dealId, bytes32[] calldata completionProof) external nonReentrant {
        PrivateDeal storage deal = privateDeals[dealId];
        require(deal.seller == msg.sender, "Only seller can complete");
        require(deal.status == DealStatus.ACTIVE, "Deal not active");
        require(block.timestamp <= deal.deadline, "Deal expired");
        
        deal.status = DealStatus.COMPLETED;
        
        // Transfer payment to seller
        payable(deal.seller).transfer(deal.amount - deal.collateralRequired);
        
        // Return collateral to buyer if applicable
        if (deal.collateralRequired > 0) {
            payable(deal.buyer).transfer(deal.collateralRequired);
        }
        
        // Update reputation
        members[deal.seller].reputation += 5;
        members[deal.buyer].reputation += 1;
        
        // Mint completion record
        privNFT.mintPrivateNFT(deal.seller, dealId, privNFT.COMPLETION_RECORDS(), 1);
        privNFT.mintPrivateNFT(deal.buyer, dealId, privNFT.COMPLETION_RECORDS(), 1);
        
        emit DealCompleted(dealId);
    }
    

    function initiateDealDispute(uint256 dealId, string memory reason) external {
        PrivateDeal storage deal = privateDeals[dealId];
        require(deal.buyer == msg.sender || deal.seller == msg.sender, "Not party to deal");
        require(deal.status == DealStatus.ACTIVE, "Deal not active");
        
        deal.status = DealStatus.DISPUTED;
        deal.disputeInitiator = msg.sender;
        
        // Mint dispute record (soulbound)
        privNFT.mintPrivateNFT(msg.sender, dealId, privNFT.DISPUTE_RECORDS(), 1);
        
        // Temporary reputation penalty pending resolution
        members[deal.buyer].reputation = members[deal.buyer].reputation > 2 ? members[deal.buyer].reputation - 2 : 0;
        members[deal.seller].reputation = members[deal.seller].reputation > 2 ? members[deal.seller].reputation - 2 : 0;
        
        emit DisputeInitiated(dealId, msg.sender);
    }
    
    function batchPunishMembers(
        address[] calldata members,
        uint256 punishmentType,
        string memory reason
    ) external onlyOwner {
        for (uint i = 0; i < members.length; i++) {
            if (punishmentType == 1) { // Reputation penalty
                _penalizeReputation(members[i], PunishmentSeverity.WARNING);
            } else if (punishmentType == 2) { // Restriction
                _restrictMemberInteractions(members[i], PunishmentSeverity.RESTRICTION, reason);
            }
        }
        
        emit BatchPunishmentExecuted(members, punishmentType);
    }
    

    function getMemberInfo(address member) external view returns (
        uint256 reputation,
        bool isActive,
        uint256 warningCount,
        bool hasHighRiskRestriction
    ) {
        Member storage memberData = members[member];
        return (
            memberData.reputation,
            memberData.isActive,
            memberData.warningCount,
            memberData.restrictedInteractions[privNFT.HIGH_RISK_DEALS()]
        );
    }
    

    function getDealInfo(uint256 dealId) external view returns (
        address buyer,
        address seller,
        uint256 amount,
        DealStatus status,
        uint256 interactionType,
        uint256 collateralRequired
    ) {
        PrivateDeal storage deal = privateDeals[dealId];
        return (
            deal.buyer,
            deal.seller,
            deal.amount,
            deal.status,
            deal.interactionType,
            deal.collateralRequired
        );
    }
    

    function emergencyIdentityReveal(address member, string memory realIdentity) external onlyOwner {
        require(!members[member].isActive, "Can only reveal removed members");
        emit IdentityRevealed(member, realIdentity, members[member].identityCommitment);
    }
    

    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }
}


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
    
    // Soulbound implementation - prevent all transfers
    function transferFrom(address, address, uint256) public pure override {
        revert("Soulbound: Transfer not allowed");
    }
    
    function safeTransferFrom(address, address, uint256) public pure override {
        revert("Soulbound: Transfer not allowed");
    }
    
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert("Soulbound: Transfer not allowed");
    }
    
    function approve(address, uint256) public pure override {
        revert("Soulbound: Approval not allowed");
    }
    
    function setApprovalForAll(address, bool) public pure override {
        revert("Soulbound: Approval not allowed");
    }
}


contract PrivateInteractionNFT is ERC1155, Ownable {
    using Counters for Counters.Counter;
    
    address public daoContract;
    
    // Token type constants
    uint256 public constant SERVICE_DEALS = 1;
    uint256 public constant HIGH_RISK_DEALS = 2;
    uint256 public constant DISPUTE_RECORDS = 3;
    uint256 public constant COMPLETION_RECORDS = 4;
    uint256 public constant REPUTATION_TOKENS = 5;
    
    // Token type properties
    mapping(uint256 => bool) public soulboundTokens;
    mapping(uint256 => string) public tokenTypeNames;
    mapping(uint256 => mapping(address => uint256)) public dealTokens;
    
    constructor(address _daoContract) ERC1155("https://api.pnrdao.com/token/{id}.json") {
        daoContract = _daoContract;
        
        // Set token type properties
        soulboundTokens[DISPUTE_RECORDS] = true;
        soulboundTokens[COMPLETION_RECORDS] = true;
        
        tokenTypeNames[SERVICE_DEALS] = "Service Deal";
        tokenTypeNames[HIGH_RISK_DEALS] = "High Risk Deal";
        tokenTypeNames[DISPUTE_RECORDS] = "Dispute Record";
        tokenTypeNames[COMPLETION_RECORDS] = "Completion Record";
        tokenTypeNames[REPUTATION_TOKENS] = "Reputation Token";
    }
    
    modifier onlyDAO() {
        require(msg.sender == daoContract, "Only DAO can call");
        _;
    }
    
    function mintPrivateNFT(
        address to,
        uint256 dealId,
        uint256 tokenType,
        uint256 amount
    ) external onlyDAO {
        _mint(to, tokenType, amount, "");
        dealTokens[tokenType][to] = dealId;
    }
    
    function burnAllTokens(address member) external onlyDAO {
        // Burn all token types for the member
        for (uint256 tokenType = 1; tokenType <= 5; tokenType++) {
            uint256 balance = balanceOf(member, tokenType);
            if (balance > 0) {
                _burn(member, tokenType, balance);
            }
        }
    }
    
    function burnSpecificTokens(
        address member,
        uint256 tokenType,
        uint256 amount
    ) external onlyDAO {
        require(balanceOf(member, tokenType) >= amount, "Insufficient balance to burn");
        _burn(member, tokenType, amount);
    }
    
    function setTokenSoulbound(uint256 tokenType, bool soulbound) external onlyDAO {
        soulboundTokens[tokenType] = soulbound;
    }
    
    function uri(uint256 tokenType) public view override returns (string memory) {
        return string(
            abi.encodePacked(
                "https://api.pnrdao.com/token/",
                Strings.toString(tokenType),
                ".json"
            )
        );
    }
    
    // Enhanced transfer restrictions for soulbound tokens
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(!soulboundTokens[id], "Soulbound: Transfer not allowed");
        super.safeTransferFrom(from, to, id, amount, data);
    }
    
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        for (uint i = 0; i < ids.length; i++) {
            require(!soulboundTokens[ids[i]], "Soulbound: Transfer not allowed");
        }
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }
    
    function setApprovalForAll(address operator, bool approved) public override {
        // Prevent approval for soulbound tokens
        super.setApprovalForAll(operator, approved);
    }
}