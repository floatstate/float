// SPDX-License-Identifier: CC-BY-NC-ND-4.0

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IFloatLaws {
    function getTokenPrice() external view returns (uint256);
}

interface IFloatToken {
    function balanceOf(address account) external view returns (uint256);
    function frozenBalance(address account) external view returns (uint256);
    function exchangeTransfer(address _from, address _to, uint256 _amount) external;
    function transfer(address to, uint256 value) external returns (bool);
}


contract FloatExchange is Initializable, UUPSUpgradeable {
    BuyOrders public buyOrders;
    SellOrders public sellOrders;
    IFloatLaws floatLaws;
    IFloatToken floatToken;
    mapping(address => uint256) public pendingWithdrawals;
    address public floatLawsAddress;
    bool _contractsInitialized;
    address _owner;

    struct OrderBuy {
        uint256 value;
        address user;
        uint64 id;
    }

    struct OrderSell {
        uint256 amount;
        address user;
        uint64 id;
    }

    struct BuyOrders {
        uint64 start;
        uint64 end;
        mapping(uint64 => OrderBuy) orders;
    }

    struct SellOrders {
        uint64 start;
        uint64 end;
        mapping(uint64 => OrderSell) orders;
    }

    struct Parameters {
        uint256 tokenPrice;
        uint8 discount;
        uint32 proposalMinVotingTime;
        uint32 lawMinVotingTime;
        uint32 parameterMinVotingTime;
        uint8 lawQuorum;
        uint8 parameterQuorum;
        uint8 smartContractQuorum;
    }

    event BuyOrder(address user, uint256 value, uint64 id, uint256 price, uint256 ts);
    event SellOrder(address user, uint256 amount, uint64 id, uint256 price, uint256 ts);

    event Trade(
        address buyer, 
        address seller, 
        uint256 amount, 
        uint256 price
    );

    event CancelOrder(
        bool isBuyOrder,
        address user, 
        uint256 value, 
        uint256 amount,
        uint64 id, 
        uint256 ts
    );

    event Withdrawal(address user, uint256 amount);

    function initialize(address addrLaws) public initializer {
        floatLaws = IFloatLaws(addrLaws);
        floatLawsAddress = addrLaws;
        _owner = msg.sender;
    }

    function buyOrder() public virtual payable {
        uint256 price = floatLaws.getTokenPrice();
        uint256 remainder = msg.value / (price * 1000000000);
        for (uint64 i = sellOrders.start; i <= sellOrders.end; i++) {
            if (sellOrders.orders[i].amount > 0) {
                if (remainder == 0) {
                    break;
                }
                if (remainder < sellOrders.orders[i].amount) {
                    sellOrders.orders[i].amount -= remainder;
                    pendingWithdrawals[sellOrders.orders[i].user] += remainder * price * 1000000000;
                    floatToken.exchangeTransfer(address(this), msg.sender, remainder);
                    remainder = 0;
                    emit Trade(msg.sender, sellOrders.orders[i].user, remainder, price);
                    break;
                } else {
                    pendingWithdrawals[sellOrders.orders[i].user] += sellOrders.orders[i].amount * price * 1000000000;
                    sellOrders.start++;
                    remainder -= sellOrders.orders[i].amount;
                    floatToken.exchangeTransfer(address(this), msg.sender, sellOrders.orders[i].amount);
                    emit Trade(msg.sender, sellOrders.orders[i].user, sellOrders.orders[i].amount, price);
                    delete sellOrders.orders[i];
                }
            } else {
                if (sellOrders.start != sellOrders.end) {
                    sellOrders.start++;
                }
            }
        }
        if (remainder > 0) {
            buyOrders.orders[buyOrders.end] = OrderBuy(remainder * price * 1000000000, msg.sender, buyOrders.end);
            emit BuyOrder(msg.sender, remainder * price * 1000000000, buyOrders.end, price, block.timestamp);
            buyOrders.end++;
        }
    }

    function sellOrder(uint256 sellAmount) public {
        require(floatToken.balanceOf(msg.sender) - floatToken.frozenBalance(msg.sender) >= sellAmount);
        uint256 price = floatLaws.getTokenPrice();
        uint256 remainder = sellAmount;
        for (uint64 i = buyOrders.start; i <= buyOrders.end; i++) {
            if (buyOrders.orders[i].value > 0) {
                if (remainder == 0) {
                    break;
                }
                if (remainder < buyOrders.orders[i].value / (price * 1000000000)) {
                    buyOrders.orders[i].value -= remainder * price * 1000000000;
                    pendingWithdrawals[msg.sender] += remainder * price * 1000000000;
                    floatToken.exchangeTransfer(msg.sender, buyOrders.orders[i].user, remainder);
                    emit Trade(buyOrders.orders[i].user, msg.sender, remainder, price);
                    remainder = 0;
                    break;
                } else {
                    pendingWithdrawals[msg.sender] += buyOrders.orders[i].value;
                    floatToken.exchangeTransfer(
                        msg.sender, 
                        buyOrders.orders[i].user, 
                        buyOrders.orders[i].value / (price * 1000000000)
                    );
                    emit Trade(
                        buyOrders.orders[i].user, 
                        msg.sender, 
                        buyOrders.orders[i].value / (price * 1000000000), 
                        price
                    );
                    buyOrders.start++;
                    remainder -= buyOrders.orders[i].value / (price * 1000000000);
                    delete buyOrders.orders[i];
                }
            } else {
                if (buyOrders.start != buyOrders.end) {
                    buyOrders.start++;
                }
            }
        }
        if (remainder > 0) {
            sellOrders.orders[sellOrders.end] = OrderSell(remainder, msg.sender, sellOrders.end);
            floatToken.exchangeTransfer(msg.sender, address(this), remainder);
            emit SellOrder(msg.sender, remainder, sellOrders.end, price, block.timestamp);
            sellOrders.end++;
        }
    }

    function cancelBuyOrder(uint64 id) public virtual {
        require(msg.sender == buyOrders.orders[id].user);
        pendingWithdrawals[msg.sender] += buyOrders.orders[id].value;
        
        emit CancelOrder(
            true,
            buyOrders.orders[id].user, 
            buyOrders.orders[id].value, 
            0,
            id,  
            block.timestamp
        );
        delete buyOrders.orders[id];
    }

    function cancelSellOrder(uint64 id) public virtual {
        require(msg.sender == sellOrders.orders[id].user);
        floatToken.exchangeTransfer(address(this), sellOrders.orders[id].user, sellOrders.orders[id].amount);
        emit CancelOrder(
            false,
            sellOrders.orders[id].user, 
            0, 
            sellOrders.orders[id].amount,
            id, 
            block.timestamp
        );
        delete sellOrders.orders[id];
    }

    function withdraw() public {
        uint amount = pendingWithdrawals[msg.sender];
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    function floatTokenInit(address addr) public {
        require(!_contractsInitialized && msg.sender == _owner);
        floatToken = IFloatToken(addr);
        _contractsInitialized = true;
    }

    function getBuyOrders() public view virtual returns (OrderBuy[] memory) {
        uint64 len = buyOrders.end;
        OrderBuy[] memory orders = new OrderBuy[](len);
        for (uint64 i = buyOrders.start; i <= buyOrders.end; i++) {
            if (buyOrders.orders[i].value > 0) {
                orders[i] = buyOrders.orders[i];
            }
        }
        return orders;
    }

    function getSellOrders() public view virtual returns (OrderSell[] memory) {
        uint64 len = sellOrders.end;
        OrderSell[] memory orders = new OrderSell[](len);
        for (uint64 i = sellOrders.start; i <= sellOrders.end; i++) {
            if (sellOrders.orders[i].amount > 0) {
                orders[i] = sellOrders.orders[i];
            }
        }
        return orders;
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == floatLawsAddress && newImplementation != address(0));
    }
}