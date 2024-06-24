// SPDX-License-Identifier: CC-BY-NC-ND-4.0

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IFloatToken {
    function totalSupply() external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
}

interface IFloatGovernance {
    function weights(address user) external view returns (uint256);
    function updateReputation(address user) external;
}

interface IUpgradeableContract {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable; 
}


contract FloatLaws is Initializable, UUPSUpgradeable {
    uint32 public lawId;
    uint32 public editLawId;
    uint32 public parameterVoteId;
    uint32 public contractVoteId;
    mapping(uint8 => mapping(uint32 => Rule)) public rules;
    Parameters public parameters;
    IFloatToken floatToken;
    IFloatGovernance floatGovernance;
    mapping(uint32 => Parameters) public newParameters;
    mapping(uint8 => mapping(uint32 => mapping(address =>  Vote[]))) public votes;
    mapping(uint32 => VotingContract) public newContract;
    address[5] public contractAddresses;
    bool _contractsInitialized;
    address _owner;

    struct Rule {
        uint8 typ;
        uint32 id;
        string text;
        string hash;
        address author;
        uint8 status;
        uint256 startVoting;
        int256 voteBalance;
    }

    struct Parameters {
        uint256 tokenPrice;
        uint8 discount;
        uint32 proposalMinVotingTime;
        uint32 proposalMaxVotingTime;
        uint32 proposalMaxDevelopmentTime;
        uint32 lawMinVotingTime;
        uint8 lawQuorum;
        uint8 parameterQuorum;
        uint8 smartContractQuorum;
    }

    struct VotingContract {
        uint8 contractNum;
        address newContractAddress;
        bytes data;
    }

    struct Vote {
        bool isFor;
        uint256 amount;
    }

    event NewLaw(
        string text, 
        address author, 
        string hash, 
        uint256 ts,
        uint32 id,
        uint8 status
    );

    event PassedLaw(uint32 id, uint256 ts, uint8 status);
    event EditPassedLaw(uint32 id, uint256 ts, uint8 status);

    event EditLawProposal(
        string text, 
        address author, 
        string hash, 
        uint256 ts,
        uint32 id,
        uint8 status,
        uint32 passedLawId
    );

    event CastVote(uint8 typ, uint32 law, uint256 votes, bool _for, address user, uint256 ts);
    event ParameterStartVoting(Parameters parameters, uint256 ts, uint32 id, address user);
    event PassedParameters(uint32 id, uint256 ts);

    event ContractsStartVoting(
        uint8 contractNum,
        uint256 startVoting,
        address user,
        address newContractAddress,
        uint32 id,
        bytes data
    );

    event PassedNewContract(uint32 id, uint256 ts);

    function initialize(
        uint256 initialPrice,
        uint8 initialDiscount,
        uint32 initialProposalMinVotingTime,
        uint32 initialProposalMaxVotingTime,
        uint32 initialProposalMaxDevelopmentTime,
        uint32 initialLawMinVotingTime,
        uint8 initialLawQuorum,
        uint8 initialParametersQuorum,
        uint8 initialSmartContractQuorum
    ) 
        public
        initializer
    {
        parameters.tokenPrice = initialPrice;
        parameters.discount = initialDiscount;
        parameters.proposalMinVotingTime = initialProposalMinVotingTime;
        parameters.proposalMaxVotingTime = initialProposalMaxVotingTime;
        parameters.proposalMaxDevelopmentTime = initialProposalMaxDevelopmentTime;
        parameters.lawMinVotingTime = initialLawMinVotingTime;
        parameters.lawQuorum = initialLawQuorum;
        parameters.parameterQuorum = initialParametersQuorum;
        parameters.smartContractQuorum = initialSmartContractQuorum;
        _owner = msg.sender;
    }

    function newLawStartVoting(
        string memory text, 
        string memory hash
    ) 
        public 
        virtual 
        returns (uint32) 
    {
        lawId++;
        rules[0][lawId] = Rule(
            0,
            lawId,
            text,
            hash,
            msg.sender,
            0,
            block.timestamp,
            0
        );
        emit NewLaw(
            text,
            msg.sender, 
            hash, 
            block.timestamp,
            lawId,
            0
        );
        return lawId;
    }

    function newLawStopVoting(uint32 id) public virtual {
        require(rules[0][id].status == 0);
        require(block.timestamp > rules[0][id].startVoting + parameters.lawMinVotingTime);
        require(rules[0][id].voteBalance >= int(parameters.lawQuorum * floatToken.totalSupply() / 100));
        rules[0][id].status = 1;
        rules[0][id].voteBalance = 0;
        emit PassedLaw(id, block.timestamp, 1);
    }

    function editLawStartVoting(
        string memory text, 
        string memory hash,
        uint32 id
    ) 
        public 
        virtual
    {
        require(rules[0][id].status == 1);
        editLawId++;
        rules[1][editLawId] = Rule(
            1,
            id,
            text,
            hash,
            msg.sender,
            0,
            block.timestamp,
            0
        );
        emit EditLawProposal(
            text, 
            msg.sender, 
            hash, 
            block.timestamp,
            editLawId,
            0,
            id
        );
    }

    function editLawStopVoting(
        uint32 id
    ) 
        public 
        virtual 
    {
        require(block.timestamp > rules[1][id].startVoting + parameters.lawMinVotingTime);
        require(rules[1][id].voteBalance >= int(parameters.lawQuorum * floatToken.totalSupply() / 100));
        rules[1][id].status = 1;
        rules[0][rules[1][id].id] = rules[1][id];
        emit EditPassedLaw(id, block.timestamp, 1);
    }

   function castVote(uint8 ruleType, uint32 id, uint256 votes_, bool isFor) public virtual {
        require(votes_ <= floatToken.getPastVotes(msg.sender, rules[ruleType][id].startVoting - 1) - getVotes(id, msg.sender, ruleType));
        require(rules[ruleType][id].status == 0 || rules[ruleType][id].status == 2);
        votes[ruleType][id][msg.sender].push(Vote(isFor, votes_));
        floatGovernance.updateReputation(msg.sender);
        if (isFor) 
            rules[ruleType][id].voteBalance += int256(votes_ * floatGovernance.weights(msg.sender) / 100000);
        else 
            rules[ruleType][id].voteBalance -= int256(votes_ * floatGovernance.weights(msg.sender) / 100000);
        emit CastVote(ruleType, id, votes_, isFor, msg.sender, block.timestamp);
    }

    function parametersStartVoting(
        uint256 price,
        uint8 discount,
        uint32 proposalMinVotingTime,
        uint32 proposalMaxVotingTime,
        uint32 proposalMaxDevelopmentTime,
        uint32 lawMinVotingTime,
        uint8 lawQuorum,
        uint8 parametersQuorum,
        uint8 smartContractQuorum
    ) 
        public 
        virtual 
    {
        parameterVoteId++;
        newParameters[parameterVoteId] = Parameters(
            price,
            discount,
            proposalMinVotingTime,
            proposalMaxVotingTime,
            proposalMaxDevelopmentTime,
            lawMinVotingTime,
            lawQuorum,
            parametersQuorum,
            smartContractQuorum
        );
        rules[2][parameterVoteId] = Rule(
            2,
            parameterVoteId,
            "",
            "",
            msg.sender,
            0,
            block.timestamp,
            0
        );
        emit ParameterStartVoting(newParameters[parameterVoteId], block.timestamp, parameterVoteId, msg.sender);
    }

    function parametersStopVoting(uint32 id) public virtual {
        require(rules[2][id].status == 0);
        require(block.timestamp > rules[2][id].startVoting + parameters.lawMinVotingTime);
        require(rules[2][id].voteBalance >= int(parameters.parameterQuorum * floatToken.totalSupply() / 100));
        rules[2][id].status = 1;
        parameters = newParameters[id];
        emit PassedParameters(id, block.timestamp);
    }

    function contractsStartVoting(address newAddress, uint8 _contract, bytes memory data) public virtual {
        contractVoteId++;
        newContract[contractVoteId] = VotingContract(_contract, newAddress, data);
        rules[3][contractVoteId] = Rule(
            3,
            contractVoteId,
            "",
            "",
            msg.sender,
            0,
            block.timestamp,
            0
        );
        emit ContractsStartVoting(
            _contract,
            block.timestamp,
            msg.sender,
            newAddress,
            contractVoteId,
            data
        );
    }

    function contractStopVoting(uint32 id) public virtual {
        require(rules[3][id].status == 0);
        require(block.timestamp > rules[3][id].startVoting + parameters.lawMinVotingTime);
        require(rules[3][id].voteBalance >= int(parameters.smartContractQuorum * floatToken.totalSupply() / 100));
        rules[3][id].status = 1;
        IUpgradeableContract(contractAddresses[newContract[id].contractNum]).upgradeToAndCall(
            newContract[id].newContractAddress, 
            newContract[id].data
        );
        emit PassedNewContract(id, block.timestamp);
    }

    function floatContractsInit(address tokenAddr, address exchangeAddr, address govAddr) public {
        require(!_contractsInitialized && msg.sender == _owner);
        floatToken = IFloatToken(tokenAddr);
        floatGovernance = IFloatGovernance(govAddr);
        contractAddresses[0] = tokenAddr;
        contractAddresses[1] = exchangeAddr;
        contractAddresses[2] = govAddr;
        contractAddresses[3] = address(this);
        _contractsInitialized = true;
    }

    function getTokenPrice() public view virtual returns (uint256) {
        return parameters.tokenPrice;
    }

    function getDiscount() public view virtual returns (uint8) {
        return parameters.discount;
    }

    function getProposalMinVotingTime() public view virtual returns (uint256) {
        return parameters.proposalMinVotingTime;
    }

    function getProposalMaxVotingTime() public view virtual returns (uint256) {
        return parameters.proposalMaxVotingTime;
    }

    function getProposalMaxDevelopmentTime() public view virtual returns (uint256) {
        return parameters.proposalMaxDevelopmentTime;
    }

    function getVotes(
        uint32 id, 
        address user, 
        uint8 typ
    ) 
        public 
        view  
        returns (uint256) 
    {
        uint256 votes_ = 0;
        for (uint i=0; i < votes[typ][id][user].length; i++ ) {
            votes_ += votes[typ][id][user][i].amount;
        }
        return votes_;
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == address(this) && newImplementation != address(0));
    }
}