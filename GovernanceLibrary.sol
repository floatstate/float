// SPDX-License-Identifier: CC-BY-NC-ND-4.0

pragma solidity ^0.8.20;

struct Project {
    uint32 id;
    string text;
    string hash;
    address user;
}

struct Proposal {
    uint32 id;
    string text;
    string hash;
    address user;
    uint256 price;
    uint8 prepay;
    uint256 collected;
    uint32 projectId;
    uint8 status;
    uint256 startVoting;
    int256 voteBalance;
    bool emissionProposal;
}

struct Investment {
    uint256 value;
    uint256 date;
    uint32 proposalId;
    uint32 projectId;
    address user;
}


library GovernanceLibrary { 
    function newProject(
        string memory text, 
        string memory hash,
        uint32 projectId,
        mapping(uint32 => Project) storage projects,
        address user
    ) 
        external  
    {
        projects[projectId] = Project(projectId, text, hash, user);
    }

    function editProject(
        string memory text, 
        string memory hash,
        uint32 id,
        mapping(uint32 => Project) storage projects,
        address user
    ) 
        external  
    {
        require(user == projects[id].user);
        if (bytes(text).length > 0) projects[id].text = text;
        if (bytes(hash).length > 0) projects[id].hash = hash;
    }

    function newProposal(
        string memory text, 
        string memory hash,
        uint256 proposalPrice,
        uint8 prepay,
        uint32 proposalProjectId, 
        bool emissionProposal,
        uint32 proposalId,
        mapping(uint32 => Proposal) storage proposals,
        address user
    ) 
        external  
    {
        proposals[proposalId] = Proposal(
            proposalId, 
            text, 
            hash, 
            user, 
            proposalPrice, 
            prepay,
            0,
            proposalProjectId,
            0,
            0,
            0,
            emissionProposal
        );
        if (!emissionProposal)proposals[proposalId].collected = proposalPrice;
    }

    function editProposal(
        string memory text, 
        string memory hash,
        uint256 proposalPrice,
        uint8 prepay,
        uint32 id,
        mapping(uint32 => Proposal) storage proposals,
        address user
    ) 
        external 
    {
        Proposal memory proposal = proposals[id];
        require(user == proposal.user);
        require(proposal.status < 1);
        if (bytes(text).length > 0) proposal.text = text;
        if (bytes(hash).length > 0) proposal.hash = hash;
        proposal.price = proposalPrice;
        proposal.prepay = prepay;
        proposal.user = user;
        proposals[id] = proposal;
    }

    function cancelProposal(
        uint32 id, 
        mapping(uint32 => Proposal) storage proposals,
        address user,
        uint256 maxVotingTime
    ) external {
        if (user == proposals[id].user) {
            require(proposals[id].status == 0);
        } else {
            require(proposals[id].status == 1);
            require(block.timestamp >= proposals[id].startVoting + maxVotingTime);
        }
        proposals[id].status = 6;
    }

    function invest(
        uint32 project, 
        uint32 proposal,
        uint32 investmentId,
        mapping(uint32 => Proposal) storage proposals,
        mapping(uint32 => Investment) storage investments,
        address user,
        uint256 value
    ) 
        external  
    {
        require(proposals[proposal].status == 0);
        require(proposals[proposal].emissionProposal);
        require(proposals[proposal].collected + value <= proposals[proposal].price);
        proposals[proposal].collected += value;
        investments[investmentId] = Investment(
            value,
            block.timestamp,
            proposal,
            project,
            user
            );
    }

    function cancelInvestment(
        uint32 id,
        mapping(uint32 => Proposal) storage proposals,
        mapping(uint32 => Investment) storage investments,
        mapping(address => uint256) storage pendingWithdrawals,
        address user
    ) 
        external 
    {
        require(investments[id].user == user);
        Proposal storage thisProposal = proposals[investments[id].proposalId];
        require(thisProposal.status == 0 || thisProposal.status == 6);
        thisProposal.collected -= investments[id].value;
        pendingWithdrawals[investments[id].user] += investments[id].value;
        delete investments[id];
    }

    function proposalStartVoting(
        uint32 proposal,
        uint8 status,
        mapping(uint32 => Proposal) storage proposals,
        address user
    ) 
        external  
    {
        require(proposals[proposal].user == user);
        require(proposals[proposal].collected >= proposals[proposal].price);
        require(proposals[proposal].status == status - 1 && proposals[proposal].status != 6);
        proposals[proposal].status = status;
        proposals[proposal].startVoting = block.timestamp;
        proposals[proposal].voteBalance = 0;
    }

    function proposalStopVoting(
        uint32 proposal, 
        mapping(uint32 => Proposal) storage proposals,
        uint256 minVotingTime,
        uint256 frozenBalance,
        uint256 tokenPrice,
        mapping(address => uint256) storage pendingWithdrawals,
        address user
    ) 
        external  
        returns (bool)
    {
        require(proposals[proposal].user == user);
        require(proposals[proposal].status == 1);
        require(block.timestamp >= proposals[proposal].startVoting + minVotingTime);
        if (!proposals[proposal].emissionProposal) {
            require(proposals[proposal].price <= address(this).balance - frozenBalance);
        }
        if (proposals[proposal].voteBalance * int(1000000000 * tokenPrice) >= int256(proposals[proposal].price)) {
            proposals[proposal].status = 2;
            pendingWithdrawals[proposals[proposal].user] += proposals[proposal].collected * proposals[proposal].prepay/100;
            return true;
        } else {
            proposals[proposal].status = 0;
        }
        return false;
    }

    function projectCompletedStopVoting(
        uint32 proposal, 
        mapping(uint32 => Proposal) storage proposals,
        uint256 minVotingTime,
        uint256 tokenPrice,
        mapping(address => uint256) storage pendingWithdrawals,
        address user,
        uint256 maxVotingTime,
        uint256 maxDevelopmentTime
    ) 
        external
        returns (uint256)
    {
        if (proposals[proposal].user == user) {
            require(proposals[proposal].status == 3);
            require(block.timestamp > proposals[proposal].startVoting + minVotingTime);
        } else {
            if (proposals[proposal].status == 2) {
                require(block.timestamp > proposals[proposal].startVoting + maxDevelopmentTime);
            }
            if (proposals[proposal].status == 3) {
                require(block.timestamp > proposals[proposal].startVoting + maxVotingTime);
            }
            proposals[proposal].voteBalance = -1 * int((proposals[proposal].price * proposals[proposal].prepay) / (1000000000 * tokenPrice * 100));
        }
        uint256 remainder = proposals[proposal].collected - proposals[proposal].collected * proposals[proposal].prepay/100;
        if (proposals[proposal].voteBalance >= 0) {
            pendingWithdrawals[proposals[proposal].user] += remainder;
        } else {
            uint rest;
            if (uint(-proposals[proposal].voteBalance) * 1000000000 * tokenPrice > proposals[proposal].price) rest = 0;
            else rest = proposals[proposal].price - uint(-proposals[proposal].voteBalance) * 1000000000 * tokenPrice; 
            pendingWithdrawals[proposals[proposal].user] += remainder * rest / proposals[proposal].price;
            proposals[proposal].status = 4;
            return remainder - remainder * rest / proposals[proposal].price;
        }
        proposals[proposal].status = 4;
        return 0;
    }
}