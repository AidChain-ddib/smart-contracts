pragma solidity ^0.8.0;

// ============================================
// 1. PROJECT REGISTRY CONTRACT
// ============================================
contract ProjectRegistry {
    //to be changes later because certain data will be saved off-chain
    //and only the hash will be stored on-chain
    struct Project {
        uint256 id;
        address owner;
        string ipfsHash;          
        uint256 fundingGoal;       
        uint256 totalFunded;       
        uint256 deadline;          
        ProjectStatus status;
        uint256 createdAt;
        uint256 milestoneCount;
        mapping(uint256 => Milestone) milestones;
        mapping(address => uint256) donations; 
    }
    
    struct Milestone {
        uint256 id;
        string description;
        uint256 fundingPercentage; 
        string proofIPFSHash;       
        MilestoneStatus status;
        uint256 validationsRequired;
        uint256 currentValidations;
        mapping(address => bool) validators;
        uint256 submittedAt;
        uint256 validatedAt;
    }
    
    enum ProjectStatus {
        Active,
        Funded,
        Completed,
        Cancelled,
        Disputed
    }
    
    enum MilestoneStatus {
        Pending,
        Submitted,
        Validated,
        Rejected
    }
    
    mapping(uint256 => Project) public projects;
    mapping(address => uint256[]) public userProjects;
    mapping(address => uint256[]) public userDonations;
    mapping(address => uint256) public userReputation;
    
    uint256 public nextProjectId = 1;
    uint256 public constant MIN_FUNDING_GOAL = 0.01 ether;
    uint256 public constant MAX_PROJECT_DURATION = 365 days;
    uint256 public constant MIN_VALIDATIONS_REQUIRED = 3;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 1;
    
    address public platformWallet;
    
 
    event ProjectCreated(uint256 indexed projectId, address indexed owner, string ipfsHash, uint256 fundingGoal, uint256 deadline);
    event MilestoneAdded(uint256 indexed projectId, uint256 indexed milestoneId, string description, uint256 fundingPercentage);
    event FundsReceived(uint256 indexed projectId, address indexed donor, uint256 amount);
    event MilestoneSubmitted(uint256 indexed projectId, uint256 indexed milestoneId, string proofIPFSHash);
    event MilestoneValidated(uint256 indexed projectId, uint256 indexed milestoneId, address indexed validator);
    event FundsReleased(uint256 indexed projectId, uint256 indexed milestoneId, uint256 amount);
    event ProjectCancelled(uint256 indexed projectId, string reason);
    event RefundIssued(uint256 indexed projectId, address indexed donor, uint256 amount);
    
    constructor(address _platformWallet) {
        platformWallet = _platformWallet;
    }
    
   
    modifier onlyProjectOwner(uint256 projectId) {
        require(projects[projectId].owner == msg.sender, "Not project owner");
        _;
    }
    
    modifier projectExists(uint256 projectId) {
        require(projects[projectId].id != 0, "Project does not exist");
        _;
    }
    
    modifier projectActive(uint256 projectId) {
        require(projects[projectId].status == ProjectStatus.Active, "Project not active");
        require(block.timestamp < projects[projectId].deadline, "Project deadline passed");
        _;
    }
    

    function createProject(
        string memory _ipfsHash,
        uint256 _fundingGoal,
        uint256 _durationInDays,
        string[] memory _milestoneDescriptions,
        uint256[] memory _milestonePercentages
    ) external returns (uint256) {
        require(_fundingGoal >= MIN_FUNDING_GOAL, "Funding goal too low");
        require(_durationInDays <= MAX_PROJECT_DURATION / 1 days, "Duration too long");
        require(_milestoneDescriptions.length == _milestonePercentages.length, "Milestone arrays mismatch");
        require(_milestoneDescriptions.length > 0, "At least one milestone required");
     
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _milestonePercentages.length; i++) {
            totalPercentage += _milestonePercentages[i];
        }
        require(totalPercentage == 100, "Milestone percentages must sum to 100");
        
        uint256 projectId = nextProjectId++;
        uint256 deadline = block.timestamp + (_durationInDays * 1 days);
        
        Project storage newProject = projects[projectId];
        newProject.id = projectId;
        newProject.owner = msg.sender;
        newProject.ipfsHash = _ipfsHash;
        newProject.fundingGoal = _fundingGoal;
        newProject.deadline = deadline;
        newProject.status = ProjectStatus.Active;
        newProject.createdAt = block.timestamp;
        newProject.milestoneCount = _milestoneDescriptions.length;
        
   
        for (uint256 i = 0; i < _milestoneDescriptions.length; i++) {
            Milestone storage milestone = newProject.milestones[i];
            milestone.id = i;
            milestone.description = _milestoneDescriptions[i];
            milestone.fundingPercentage = _milestonePercentages[i];
            milestone.status = MilestoneStatus.Pending;
            milestone.validationsRequired = MIN_VALIDATIONS_REQUIRED;
            
            emit MilestoneAdded(projectId, i, _milestoneDescriptions[i], _milestonePercentages[i]);
        }
        
        userProjects[msg.sender].push(projectId);
        
        emit ProjectCreated(projectId, msg.sender, _ipfsHash, _fundingGoal, deadline);
        
        return projectId;
    }
    
    function donateToProject(uint256 projectId) 
        external 
        payable 
        projectExists(projectId) 
        projectActive(projectId) 
    {
        require(msg.value > 0, "Donation must be greater than 0");
        
        Project storage project = projects[projectId];
        project.totalFunded += msg.value;
        project.donations[msg.sender] += msg.value;
      
        userDonations[msg.sender].push(projectId);
        
    
        if (project.totalFunded >= project.fundingGoal) {
            project.status = ProjectStatus.Funded;
        }
        
        emit FundsReceived(projectId, msg.sender, msg.value);
    }
    
    function submitMilestoneProof(
        uint256 projectId,
        uint256 milestoneId,
        string memory proofIPFSHash
    ) external onlyProjectOwner(projectId) projectExists(projectId) {
        require(milestoneId < projects[projectId].milestoneCount, "Invalid milestone");
        
        Milestone storage milestone = projects[projectId].milestones[milestoneId];
        require(milestone.status == MilestoneStatus.Pending, "Milestone already submitted");
        
        milestone.proofIPFSHash = proofIPFSHash;
        milestone.status = MilestoneStatus.Submitted;
        milestone.submittedAt = block.timestamp;
        
        emit MilestoneSubmitted(projectId, milestoneId, proofIPFSHash);
    }
    
    function validateMilestone(uint256 projectId, uint256 milestoneId) 
        external 
        projectExists(projectId) 
    {
        require(milestoneId < projects[projectId].milestoneCount, "Invalid milestone");
        require(userReputation[msg.sender] >= 10, "Insufficient reputation to validate");
        require(msg.sender != projects[projectId].owner, "Project owner cannot validate own milestone");
        
        Milestone storage milestone = projects[projectId].milestones[milestoneId];
        require(milestone.status == MilestoneStatus.Submitted, "Milestone not ready for validation");
        require(!milestone.validators[msg.sender], "Already validated by this address");
        
        milestone.validators[msg.sender] = true;
        milestone.currentValidations++;
    
        userReputation[msg.sender] += 1;
        
     
        if (milestone.currentValidations >= milestone.validationsRequired) {
            milestone.status = MilestoneStatus.Validated;
            milestone.validatedAt = block.timestamp;
            _releaseMilestoneFunds(projectId, milestoneId);
        }
        
        emit MilestoneValidated(projectId, milestoneId, msg.sender);
    }
    
    function _releaseMilestoneFunds(uint256 projectId, uint256 milestoneId) internal {
        Project storage project = projects[projectId];
        Milestone storage milestone = project.milestones[milestoneId];
        
        uint256 releaseAmount = (project.totalFunded * milestone.fundingPercentage) / 100;
        uint256 platformFee = (releaseAmount * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 ownerAmount = releaseAmount - platformFee;
        
       
        (bool feeSuccess, ) = payable(platformWallet).call{value: platformFee}("");
        require(feeSuccess, "Platform fee transfer failed");
        
       
        (bool success, ) = payable(project.owner).call{value: ownerAmount}("");
        require(success, "Fund transfer failed");
        
        emit FundsReleased(projectId, milestoneId, ownerAmount);
    }
    
    function cancelProject(uint256 projectId, string memory reason) 
        external 
        onlyProjectOwner(projectId) 
        projectExists(projectId) 
    {
        require(projects[projectId].status == ProjectStatus.Active, "Project not active");
        
        projects[projectId].status = ProjectStatus.Cancelled;
        
        emit ProjectCancelled(projectId, reason);
    }
    
    function requestRefund(uint256 projectId) external projectExists(projectId) {
        Project storage project = projects[projectId];
        require(project.status == ProjectStatus.Cancelled || 
                (project.status == ProjectStatus.Active && block.timestamp > project.deadline), 
                "Refund not available");
        
        uint256 donationAmount = project.donations[msg.sender];
        require(donationAmount > 0, "No donation found");
        
        project.donations[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: donationAmount}("");
        require(success, "Refund transfer failed");
        
        emit RefundIssued(projectId, msg.sender, donationAmount);
    }
    
  
    function getProject(uint256 projectId) external view returns (
        address owner,
        string memory ipfsHash,
        uint256 fundingGoal,
        uint256 totalFunded,
        uint256 deadline,
        ProjectStatus status,
        uint256 createdAt,
        uint256 milestoneCount
    ) {
        Project storage project = projects[projectId];
        return (
            project.owner,
            project.ipfsHash,
            project.fundingGoal,
            project.totalFunded,
            project.deadline,
            project.status,
            project.createdAt,
            project.milestoneCount
        );
    }
    
    function getMilestone(uint256 projectId, uint256 milestoneId) external view returns (
        string memory description,
        uint256 fundingPercentage,
        string memory proofIPFSHash,
        MilestoneStatus status,
        uint256 validationsRequired,
        uint256 currentValidations,
        uint256 submittedAt,
        uint256 validatedAt
    ) {
        Milestone storage milestone = projects[projectId].milestones[milestoneId];
        return (
            milestone.description,
            milestone.fundingPercentage,
            milestone.proofIPFSHash,
            milestone.status,
            milestone.validationsRequired,
            milestone.currentValidations,
            milestone.submittedAt,
            milestone.validatedAt
        );
    }
    
    function getUserDonation(uint256 projectId, address user) external view returns (uint256) {
        return projects[projectId].donations[user];
    }
    
    function getUserProjects(address user) external view returns (uint256[] memory) {
        return userProjects[user];
    }
    
    function getUserDonations(address user) external view returns (uint256[] memory) {
        return userDonations[user];
    }
}

// ============================================
// 2. DISPUTE RESOLUTION CONTRACT
// ============================================

contract DisputeResolution {
    
    struct Dispute {
        uint256 id;
        uint256 projectId;
        uint256 milestoneId;
        address reporter;
        string description;
        string evidenceIPFSHash;
        DisputeStatus status;
        uint256 createdAt;
        uint256 votingDeadline;
        uint256 yesVotes;
        uint256 noVotes;
        mapping(address => bool) hasVoted;
        mapping(address => VoteChoice) votes;
    }
    
    enum DisputeStatus {
        Active,
        Resolved,
        Rejected,
        Expired
    }
    
    enum VoteChoice {
        None,
        Yes,
        No
    }
    
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => uint256[]) public projectDisputes; 
    mapping(address => uint256) public userReputation;
    
    uint256 public nextDisputeId = 1;
    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public constant MIN_REPUTATION_TO_VOTE = 5;
    uint256 public constant MIN_VOTES_REQUIRED = 10;
    
    address public projectRegistryContract;
    
    event DisputeCreated(uint256 indexed disputeId, uint256 indexed projectId, uint256 indexed milestoneId, address reporter);
    event DisputeVoted(uint256 indexed disputeId, address indexed voter, VoteChoice choice);
    event DisputeResolved(uint256 indexed disputeId, DisputeStatus result);
    
    constructor(address _projectRegistryContract) {
        projectRegistryContract = _projectRegistryContract;
    }
    
    modifier onlyValidReputation() {
        require(userReputation[msg.sender] >= MIN_REPUTATION_TO_VOTE, "Insufficient reputation to vote");
        _;
    }
    
    modifier disputeExists(uint256 disputeId) {
        require(disputes[disputeId].id != 0, "Dispute does not exist");
        _;
    }
    
    modifier disputeActive(uint256 disputeId) {
        require(disputes[disputeId].status == DisputeStatus.Active, "Dispute not active");
        require(block.timestamp < disputes[disputeId].votingDeadline, "Voting period ended");
        _;
    }
    
    function createDispute(
        uint256 projectId,
        uint256 milestoneId,
        string memory description,
        string memory evidenceIPFSHash
    ) external returns (uint256) {
        require(bytes(description).length > 0, "Description required");
        require(bytes(evidenceIPFSHash).length > 0, "Evidence required");
        
        uint256 disputeId = nextDisputeId++;
        
        Dispute storage newDispute = disputes[disputeId];
        newDispute.id = disputeId;
        newDispute.projectId = projectId;
        newDispute.milestoneId = milestoneId;
        newDispute.reporter = msg.sender;
        newDispute.description = description;
        newDispute.evidenceIPFSHash = evidenceIPFSHash;
        newDispute.status = DisputeStatus.Active;
        newDispute.createdAt = block.timestamp;
        newDispute.votingDeadline = block.timestamp + VOTING_DURATION;
        
        projectDisputes[projectId].push(disputeId);
        
        emit DisputeCreated(disputeId, projectId, milestoneId, msg.sender);
        
        return disputeId;
    }
    
    function voteOnDispute(uint256 disputeId, VoteChoice choice) 
        external 
        onlyValidReputation 
        disputeExists(disputeId) 
        disputeActive(disputeId) 
    {
        require(choice == VoteChoice.Yes || choice == VoteChoice.No, "Invalid vote choice");
        
        Dispute storage dispute = disputes[disputeId];
        require(!dispute.hasVoted[msg.sender], "Already voted on this dispute");
        
        dispute.hasVoted[msg.sender] = true;
        dispute.votes[msg.sender] = choice;
        
        if (choice == VoteChoice.Yes) {
            dispute.yesVotes++;
        } else {
            dispute.noVotes++;
        }
        
       
        userReputation[msg.sender] += 1;
        
        emit DisputeVoted(disputeId, msg.sender, choice);
        
        
        if (dispute.yesVotes + dispute.noVotes >= MIN_VOTES_REQUIRED) {
            _resolveDispute(disputeId);
        }
    }
    
    function resolveExpiredDispute(uint256 disputeId) external disputeExists(disputeId) {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.status == DisputeStatus.Active, "Dispute not active");
        require(block.timestamp >= dispute.votingDeadline, "Voting period not ended");
        
        _resolveDispute(disputeId);
    }
    
    function _resolveDispute(uint256 disputeId) internal {
        Dispute storage dispute = disputes[disputeId];
        
        if (dispute.yesVotes + dispute.noVotes < MIN_VOTES_REQUIRED && 
            block.timestamp < dispute.votingDeadline) {
            return;
        }
        
        if (dispute.yesVotes + dispute.noVotes < MIN_VOTES_REQUIRED) {
            dispute.status = DisputeStatus.Expired;
        } else if (dispute.yesVotes > dispute.noVotes) {
            dispute.status = DisputeStatus.Resolved;
        } else {
            dispute.status = DisputeStatus.Rejected;
        }
        
        emit DisputeResolved(disputeId, dispute.status);
    }
    
    function getDispute(uint256 disputeId) external view returns (
        uint256 projectId,
        uint256 milestoneId,
        address reporter,
        string memory description,
        string memory evidenceIPFSHash,
        DisputeStatus status,
        uint256 createdAt,
        uint256 votingDeadline,
        uint256 yesVotes,
        uint256 noVotes
    ) {
        Dispute storage dispute = disputes[disputeId];
        return (
            dispute.projectId,
            dispute.milestoneId,
            dispute.reporter,
            dispute.description,
            dispute.evidenceIPFSHash,
            dispute.status,
            dispute.createdAt,
            dispute.votingDeadline,
            dispute.yesVotes,
            dispute.noVotes
        );
    }
    
    function getProjectDisputes(uint256 projectId) external view returns (uint256[] memory) {
        return projectDisputes[projectId];
    }
    
    function hasUserVoted(uint256 disputeId, address user) external view returns (bool) {
        return disputes[disputeId].hasVoted[user];
    }
    
    function getUserVote(uint256 disputeId, address user) external view returns (VoteChoice) {
        return disputes[disputeId].votes[user];
    }
}

// ============================================
// 3. REPUTATION SYSTEM CONTRACT
// ============================================

contract ReputationSystem {
    
    struct UserProfile {
        uint256 totalReputation;
        uint256 projectsCreated;
        uint256 projectsCompleted;
        uint256 validationsPerformed;
        uint256 successfulValidations;
        uint256 totalDonated;
        uint256 totalFunded;
        bool isVerified;
    }
    
    mapping(address => UserProfile) public userProfiles;
    mapping(address => mapping(string => bool)) public userBadges;
    
    address public projectRegistryContract;
    address public disputeResolutionContract;
    
    string[] public availableBadges = [
        "Early Adopter",
        "Generous Donor",
        "Trusted Validator",
        "Successful Creator",
        "Community Leader"
    ];
    
    event ReputationUpdated(address indexed user, uint256 newReputation);
    event BadgeAwarded(address indexed user, string badge);
    event UserVerified(address indexed user);
    
    constructor(address _projectRegistryContract, address _disputeResolutionContract) {
        projectRegistryContract = _projectRegistryContract;
        disputeResolutionContract = _disputeResolutionContract;
    }
    
    modifier onlyAuthorizedContract() {
        require(msg.sender == projectRegistryContract || 
                msg.sender == disputeResolutionContract, 
                "Not authorized");
        _;
    }
    
    function updateReputation(address user, uint256 amount, string memory action) 
        external 
        onlyAuthorizedContract 
    {
        UserProfile storage profile = userProfiles[user];
        profile.totalReputation += amount;
        
        // Update specific metrics based on action
        if (keccak256(bytes(action)) == keccak256(bytes("project_created"))) {
            profile.projectsCreated++;
        } else if (keccak256(bytes(action)) == keccak256(bytes("project_completed"))) {
            profile.projectsCompleted++;
        } else if (keccak256(bytes(action)) == keccak256(bytes("validation_performed"))) {
            profile.validationsPerformed++;
        } else if (keccak256(bytes(action)) == keccak256(bytes("successful_validation"))) {
            profile.successfulValidations++;
        }
        
        _checkAndAwardBadges(user);
        
        emit ReputationUpdated(user, profile.totalReputation);
    }
    
    function updateDonationStats(address user, uint256 amount) external onlyAuthorizedContract {
        userProfiles[user].totalDonated += amount;
        _checkAndAwardBadges(user);
    }
    
    function updateFundingStats(address user, uint256 amount) external onlyAuthorizedContract {
        userProfiles[user].totalFunded += amount;
        _checkAndAwardBadges(user);
    }

}