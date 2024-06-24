// SPDX-License-Identifier: CC-BY-NC-ND-4.0

pragma solidity ^0.8.20;

import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ICondition {
    function condition(uint32 id) external view returns (bool);
    function repayment(uint32 id) external view returns (uint256);
}


contract FloatToken is ERC20VotesUpgradeable, UUPSUpgradeable {
    address public floatGovernanceAddress;
    address public floatExchangeAddress;
    address public floatLawsAddress;
    mapping (uint32 => DelegateWithCondition) public conditionalDelegates;
    uint32 public conditionalDelegatesId;
    mapping (address => uint256) public frozenBalance;

    struct DelegateWithCondition {
        address from;
        address to;
        address conditionContract;
        uint256 amount;
        uint256 ts;
    }

    event ConditionalDelegates(
        address indexed from, 
        address indexed to, 
        uint256 amount, 
        uint32 indexed id, 
        uint256 ts,
        address conditionAddress
    );

    event ReturnDelegates(
        address indexed from, 
        address indexed to, 
        uint256 amount, 
        uint32 indexed id, 
        uint256 ts,
        address conditionAddress
    );

    function initialize(
        string memory name, 
        string memory symbol, 
        uint256 initialSupply,
        address gov,
        address exchange,
        address laws
    ) 
        public 
        initializer 
    {
        __ERC20_init(name, symbol);
        _mint(msg.sender, initialSupply);
        floatGovernanceAddress = gov;
        floatExchangeAddress = exchange;
        floatLawsAddress = laws;
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        require(value <= balanceOf(owner) - frozenBalance[owner]);
        _transfer(owner, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        require(value <= balanceOf(from) - frozenBalance[from]);
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function mintGovernance(address account, uint256 value) public {
        require(msg.sender == floatGovernanceAddress);
        _mint(account, value);
    }

    function exchangeTransfer(address from, address to, uint256 amount) public {
        require(msg.sender == floatExchangeAddress);
        _transfer(from, to, amount);
    }

    function delegate(address delegatee) public override {
        delegatee = _msgSender();
        _delegate(delegatee, delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) 
        public 
        override 
    {}

    function delegateWithCondition(
        address to, 
        uint256 amount, 
        address conditionContract
    ) 
        public 
        virtual 
    {
        address sender = _msgSender();
        require(delegates(sender) != address(0) && delegates(to) != address(0));
        require(amount <= _getVotingUnits(sender) && amount <= getVotes(sender));
        frozenBalance[sender] += amount;
        conditionalDelegatesId++;
        conditionalDelegates[conditionalDelegatesId] = DelegateWithCondition(
            sender, 
            to, 
            conditionContract, 
            amount, 
            block.timestamp
        );
        _transferVotingUnits(sender, to, amount);
        emit ConditionalDelegates(
            sender, 
            to, 
            amount, 
            conditionalDelegatesId, 
            block.timestamp,
            conditionContract
        );
    }

    function returnDelegatedVotes(uint32 id) public virtual {
        require(ICondition(conditionalDelegates[id].conditionContract).condition(id));
        require(conditionalDelegates[id].from == msg.sender);
        address _delegatee = conditionalDelegates[id].to;
        address _sender = _msgSender();
        frozenBalance[_sender] -= conditionalDelegates[id].amount;
        _transferVotingUnits(_delegatee, _sender, conditionalDelegates[id].amount);
        uint256 repayment = ICondition(conditionalDelegates[id].conditionContract).repayment(id);
        _transfer(_sender, _delegatee, repayment);
        emit ReturnDelegates(
            _sender, 
            _delegatee, 
            conditionalDelegates[id].amount, 
            id,
            block.timestamp,
            conditionalDelegates[id].conditionContract
        );
        delete conditionalDelegates[id];
    }

    function clock() public view override returns (uint48) {
        return Time.timestamp();
    }

    function CLOCK_MODE() public view override returns (string memory) {
        if (clock() != Time.timestamp()) {
            revert ERC6372InconsistentClock();
        }
        return "mode=timestamp&from=default";
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == floatLawsAddress && newImplementation != address(0));
    }
}

