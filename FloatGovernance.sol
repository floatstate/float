// SPDX-License-Identifier: CC-BY-NC-ND-4.0

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Project, Proposal, Investment, GovernanceLibrary} from "../contracts/GovernanceLibrary.sol";

/* Proposal statuses
    0 - Funding
    1 - Voting
    2 - Developing
    3 - Completed voting
    4 - Completed (reputations update)
    5 - Voting after completed
    6 - Canceled
*/

interface IFloatToken {
    function totalSupply() external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function mintGovernance(address account, uint256 value) external;
}

interface IFloatLaws {
    function getDiscount() external view returns (uint8);
    function getProposalMinVotingTime() external view  returns (uint256);
    function getProposalMaxVotingTime() external view  returns (uint256);
    function getProposalMaxDevelopmentTime() external view  returns (uint256);
    function getTokenPrice() external view returns (uint256);
}


contract FloatGovernance is Initializable, UUPSUpgradeable {
    mapping(address => uint256) public pendingWithdrawals;
    uint32 public projectId;
    uint32 public proposalId;
    uint32 public investmentId;
    mapping(uint32 => Project) public projects;
    mapping(uint32 => Proposal) public proposals;
    mapping(uint32 => Investment) public investments;
    mapping(address => mapping(uint32 => mapping(uint8 => Voted))) public proposalVotes;
    mapping(address => uint256) public weights;
    mapping(address => uint32[]) public userVotes;
    IFloatToken floatToken;
    IFloatLaws floatLaws;
    address public floatLawsAddress;
    uint256 public frozenBalance;
    bool _contractsInitialized;
    address _owner;

    struct Voted {
        bool isVoted;
        int256 amount;
        uint256 start;
    }

    struct UserVotes {
        uint256 unsigned;
        int256 signed;
    }

    event NewProject(
        string text, 
        address user, 
        string hash, 
        uint32 id, 
        uint timestamp
    );

    event EditProject(
        string text, 
        address user, 
        string hash, 
        uint32 id, 
        uint timestamp
    );

    event NewProposal(
        string text, 
        address user, 
        string hash, 
        uint256 price, 
        uint8 prepay, 
        uint32 projectId, 
        uint32 proposalId, 
        uint256 ts,
        bool emissionProposal
    );

    event EditProposal(
        string text, 
        address user, 
        string hash, 
        uint256 price, 
        uint8 prepay, 
        uint32 projectId, 
        uint32 proposalId, 
        uint256 ts
    );

    event CancelProposal(uint32 id);

    event NewInvestment(
        uint256 value,
        uint256 date,
        uint32 proposalId,
        uint32 projectId,
        address user,
        uint32 id
    );

    event CancelInvestment(uint32 id);
    event ProposalStartVoting(uint32 project, uint32 proposal, uint8 status, uint256 ts);
    event ProposalStopVoting(uint32 project, uint32 proposal, uint8 status);
    event ProposalCastVote(uint32 proposal, int256 votes, uint256 weight, address user, uint256 ts);
    event Received(uint256 value, address indexed sender, uint256 ts);
    event Withdrawal(address user, uint256 amount);

    function initialize() public initializer {
        _owner = msg.sender;
    }

    receive() external payable {
        emit Received(msg.value, msg.sender, block.timestamp);
    }

    function newProject(
        string memory text, 
        string memory hash
    ) 
        public 
        virtual 
        returns (uint32) 
    {
        projectId++;
        GovernanceLibrary.newProject(
            text, 
            hash,
            projectId,
            projects,
            msg.sender
        );
        emit NewProject(text, msg.sender, hash, projectId, block.timestamp);
        return projectId;
    }

    function editProject(
        string memory text, 
        string memory hash,
        uint32 id
    ) 
        public 
        virtual 
    {
        GovernanceLibrary.editProject(
            text, 
            hash,
            id,
            projects,
            msg.sender
        );
        emit EditProject(text, msg.sender, hash, id, block.timestamp);
    }

    function newProposal(
        string memory text, 
        string memory hash,
        uint256 proposalPrice,
        uint8 prepay,
        uint32 proposalProjectId, 
        bool emissionProposal
    ) 
        public 
        virtual 
        returns (uint32) 
    {
        if (!emissionProposal) {
            require(proposalPrice <= address(this).balance - frozenBalance);
        }
        proposalId++;
        GovernanceLibrary.newProposal(
            text, 
            hash,
            proposalPrice,
            prepay,
            proposalProjectId, 
            emissionProposal,
            proposalId,
            proposals,
            msg.sender
        );
        emit NewProposal(
            text, 
            msg.sender, 
            hash, 
            proposalPrice, 
            prepay, 
            proposalProjectId, 
            proposalId, 
            block.timestamp,
            emissionProposal
        );
        return proposalId;
    }

    function editProposal(
        string memory text, 
        string memory hash,
        uint256 proposalPrice,
        uint8 prepay,
        uint32 proposalProjectId,
        uint32 id
    ) 
        public 
        virtual 
    {
        if (!proposals[id].emissionProposal) {
            require(proposalPrice <= address(this).balance - frozenBalance);
            proposals[id].collected = proposalPrice;
        }
        GovernanceLibrary.editProposal(
            text, 
            hash,
            proposalPrice,
            prepay,
            id,
            proposals,
            msg.sender
        );
        emit EditProposal(
            text, 
            msg.sender, 
            hash, 
            proposalPrice, 
            prepay, 
            proposalProjectId, 
            id, 
            block.timestamp
        );
    }

    function cancelProposal(uint32 id) public virtual {
        GovernanceLibrary.cancelProposal(
            id, 
            proposals,
            msg.sender,
            floatLaws.getProposalMaxVotingTime()
        );
        emit CancelProposal(id);
    }

    function invest(
        uint32 project, 
        uint32 proposal
    ) 
        public 
        virtual 
        payable 
        returns (uint32)
    {
        investmentId++;
        GovernanceLibrary.invest(
            project, 
            proposal,
            investmentId,
            proposals,
            investments,
            msg.sender,
            msg.value
        );
        frozenBalance += msg.value;
        emit NewInvestment(msg.value, block.timestamp, proposal, project, msg.sender, investmentId);
        return investmentId;
    }

    function cancelInvestment(
        uint32 id
    ) 
        public 
        virtual 
    {
        GovernanceLibrary.cancelInvestment(
            id,
            proposals,
            investments,
            pendingWithdrawals,
            msg.sender
        );
        emit CancelInvestment(id);
    }

    function proposalStartVoting(
        uint32 proposal, 
        uint32 project, 
        uint8 status
    ) 
        public 
        virtual 
    {
        GovernanceLibrary.proposalStartVoting(
            proposal,
            status,
            proposals,
            msg.sender
        );
        emit ProposalStartVoting(project, proposal, status, block.timestamp);
    }

    function proposalStopVoting(
        uint32 proposal, 
        uint32 project
    ) 
        public 
        virtual 
    {
        bool success = GovernanceLibrary.proposalStopVoting(
            proposal, 
            proposals,
            floatLaws.getProposalMinVotingTime(),
            frozenBalance,
            floatLaws.getTokenPrice(),
            pendingWithdrawals,
            msg.sender
        );
        if (!proposals[proposal].emissionProposal && success) {
            frozenBalance += proposals[proposal].collected;
        }
        emit ProposalStopVoting(project, proposal, proposals[proposal].status);
    }

    function projectCompletedStopVoting(
        uint32 proposal, 
        uint32 project
    ) 
        public
        virtual
    {

        uint256 frozen = GovernanceLibrary.projectCompletedStopVoting(
            proposal, 
            proposals,
            floatLaws.getProposalMinVotingTime(),
            floatLaws.getTokenPrice(),
            pendingWithdrawals,
            msg.sender,
            floatLaws.getProposalMaxVotingTime(),
            floatLaws.getProposalMaxDevelopmentTime()
        );

        if (frozen > 0) {
            frozenBalance -= frozen;
        }
        emit ProposalStopVoting(project, proposal, proposals[proposal].status);
    }

    function proposalCastVote(
        uint32 proposal, 
        int256 votes
    ) 
        public
        virtual
    {
        uint256 uintVotes;
        if (votes >= 0) {
            uintVotes = uint(votes);
        }
        else uintVotes = uint(-1 * votes);
        require(uintVotes <= floatToken.getPastVotes(msg.sender, proposals[proposal].startVoting - 1) - getProposalVotes(proposal, msg.sender, proposals[proposal].status));
        updateReputation(msg.sender);
        proposals[proposal].voteBalance += votes * int256(weights[msg.sender]) / 100000;
        if (!proposalVotes[msg.sender][proposal][proposals[proposal].status].isVoted) {
            if (proposals[proposal].status == 1) {
                userVotes[msg.sender].push(proposal);
                proposalVotes[msg.sender][proposal][1].start = proposals[proposal].startVoting;
            }
            proposalVotes[msg.sender][proposal][proposals[proposal].status].isVoted = true;
        }
        proposalVotes[msg.sender][proposal][proposals[proposal].status].amount += votes;
        emit ProposalCastVote(proposal, votes, weights[msg.sender], msg.sender, block.timestamp);
    }

    function getInvestmentTokens(uint32 proposal, uint32 investment) public virtual {
        require(proposals[proposal].status >= 2);
        require(investments[investment].user == msg.sender);
        floatToken.mintGovernance(
            msg.sender, 
            investments[investment].value / ((100 - floatLaws.getDiscount()) * (floatLaws.getTokenPrice() * 1000000000 / 100))
        );
        delete investments[investment];
    }

    function updateReputation(address user) public virtual {
        uint len = userVotes[user].length;
        for (uint i = 0; i < len; i++ ) {
            if (proposals[userVotes[user][i]].status == 4) {
                uint _proposalVotes = getProposalVotes(userVotes[user][i], user, 1);
                uint startVotes = floatToken.getPastVotes(
                    user, 
                    proposalVotes[user][userVotes[user][i]][1].start - 1
                );
                uint proposalPrice = proposals[userVotes[user][i]].price;
                uint totalSupplyETH = floatToken.totalSupply() * floatLaws.getTokenPrice() * 1000000000;
                int sign;
                if (proposals[userVotes[user][i]].voteBalance >= 0){
                    if (proposalVotes[user][userVotes[user][i]][1].amount >= 0) 
                        sign = 1;
                    else 
                        sign = -1;
                } else {
                    if (proposalVotes[user][userVotes[user][i]][1].amount < 0) 
                        sign = 1;
                    else 
                        sign = -1;
                }
                uint diff = (100000 * _proposalVotes * proposalPrice) / (startVotes * totalSupplyETH);
                if (diff > weights[user]) 
                    diff = weights[user];
                if (sign > 0) 
                    weights[user] += diff;
                else 
                    weights[user] -= diff;
                delete userVotes[user][i];
            }
        }
        if (weights[user] < 100000) 
            weights[user] = 100000;
    }
    
    function cleanUserVotes(address user) public {
        uint32[] memory newVotes = new uint32[](userVotes[user].length);
        uint16 c;
        for (uint i = 0; i < userVotes[user].length; i++ ) {
            if (userVotes[user][i] > 0) {
                newVotes[c] = userVotes[user][i];
                c++;
            }
        }
        userVotes[user] = newVotes;
        uint length = userVotes[user].length;
        for(uint16 ii = c; ii < length; ii++){
            userVotes[user].pop();
        }
    }

    function floatTokenInit(address addrToken, address addrLaws) public {
        require(!_contractsInitialized && msg.sender == _owner);
        floatToken = IFloatToken(addrToken);
        floatLaws = IFloatLaws(addrLaws);
        floatLawsAddress = addrLaws;
        _contractsInitialized = true;
    }

    function withdraw() public {
        uint amount = pendingWithdrawals[msg.sender];
        frozenBalance -= amount;
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    function getProposalVotes(
        uint32 proposal, 
        address user, 
        uint8 status
    ) 
        public 
        view  
        returns (uint256)
    {
        if (proposalVotes[user][proposal][status].amount >= 0) {
            return uint(proposalVotes[user][proposal][status].amount);
        }
        return uint(-1 * proposalVotes[user][proposal][status].amount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == floatLawsAddress && newImplementation != address(0));
    }
}