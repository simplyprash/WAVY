// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WAVYEscrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct allowedTokens {
        bool isAllowed;
        string tokenName;
        IERC20 tokenAddress;
        uint decimals;
    }

    allowedTokens[] public allowedTokensList;
    mapping(IERC20 => bool) public isAllowed;

    struct Offer {
        uint sendTokenId;
        uint256 sendAmount;
        uint receiveTokenId;
        uint256 receiveAmount;
        uint256 minReceiveAmount;
        address listerAddress;
        uint256 status; // 0 - active, 1 - completed, 2 - revoked
    }

    Offer[] public offerDetails;
    address feeWallet = 0xE7f554bB576b2De89c73B0F2b1372F7a1744070E;

    event OfferCreated(address indexed createdBy, uint sendTokenId, uint256 sendAmount, uint receiveTokenId, uint256 receiveAmount, uint256 minReceiveAmount);

    function addToAllowList(string memory _tokenName, IERC20 _tokenAddress, uint _decimals) external onlyOwner {
        allowedTokensList.push(allowedTokens(true, _tokenName, _tokenAddress, _decimals));
        isAllowed[_tokenAddress] = true;
    }

    function removeFromAllowList(uint _tokenId) external onlyOwner {
        require(isAllowed[allowedTokensList[_tokenId].tokenAddress], "Not valid token Id or token already disabled");
        isAllowed[allowedTokensList[_tokenId].tokenAddress] = false;
    }

    function makeOffer(uint _sendTokenId, uint256 _sendAmount, uint _receiveTokenId, uint256 _receiveAmount, uint256 _minReceiveAmount) external {
        require(isAllowed[allowedTokensList[_sendTokenId].tokenAddress], "Token being sold is not allowed");
        require(isAllowed[allowedTokensList[_receiveTokenId].tokenAddress], "Token to be received is not allowed"); 
        require(_minReceiveAmount <= _receiveAmount, "Minimum receivable amount cannot be greater than the receive amount");

        IERC20 _token = allowedTokensList[_sendTokenId].tokenAddress;
        uint256 fee = calculateFee(_sendAmount);
        uint256 transferAmount = _sendAmount + fee;

        require(_token.balanceOf(msg.sender) >= transferAmount, "Insufficient balance");
        require(_token.allowance(msg.sender, address(this)) >= transferAmount, "Insufficient allowance");

        _token.safeTransferFrom(msg.sender, address(this), _sendAmount);
        _token.safeTransferFrom(msg.sender, feeWallet, fee);
        offerDetails.push(Offer(_sendTokenId, _sendAmount, _receiveTokenId, _receiveAmount, _minReceiveAmount, msg.sender, 0));

        emit OfferCreated(msg.sender, _sendTokenId, _sendAmount, _receiveTokenId, _receiveAmount, _minReceiveAmount);
    }

    function calculateFee(uint256 _amount) private pure returns (uint256) {
        return _amount * 25 / 10000;
    }

    function acceptOffer(uint256 _offerId, uint256 _amount) external nonReentrant {
        Offer storage _offer = offerDetails[_offerId];
        require(_offer.status == 0, "Offer not available");
        require(_offer.receiveAmount >= _amount, "Amount is greater than what listing expects");
        require(_amount >= _offer.minReceiveAmount, "Amount should be more than minimum Receivable amount");

        IERC20 _sendToken = allowedTokensList[_offer.sendTokenId].tokenAddress;
        IERC20 _receiveToken = allowedTokensList[_offer.receiveTokenId].tokenAddress;

        uint256 fee = calculateFee(_amount);

        require(_receiveToken.balanceOf(msg.sender) >= _amount + fee, "Insufficient balance");
        require(_receiveToken.allowance(msg.sender, address(this)) >= _amount + fee, "Insufficient allowance");

        uint256 proportionalSendAmount =  _offer.sendAmount * _amount / _offer.receiveAmount;
        _offer.sendAmount -= proportionalSendAmount;
        _offer.receiveAmount -= _amount;

        _receiveToken.safeTransferFrom(msg.sender, feeWallet, fee);
        _receiveToken.safeTransferFrom(msg.sender, _offer.listerAddress, _amount);
        _sendToken.safeTransfer(msg.sender, proportionalSendAmount);

        if(_offer.receiveAmount == 0) {
            _offer.status = 1;
        } else if(_offer.receiveAmount < _offer.minReceiveAmount) {
            _offer.minReceiveAmount = _offer.receiveAmount;
        }
    }

    function cancelOffer(uint256 _offerId) external nonReentrant {
        Offer storage _offer = offerDetails[_offerId];
        require(_offer.status == 0, "Offer not available");
        require(_offer.listerAddress == msg.sender, "Caller has not created the offer");
        IERC20 _sendToken = allowedTokensList[_offer.sendTokenId].tokenAddress;
        _sendToken.safeTransfer(_offer.listerAddress, _offer.sendAmount);
        _offer.status = 2;
    }

    function updateOffer(uint256 _offerId, uint256 _receiveAmount, uint256 _minReceiveAmount) external {
        Offer storage _offer = offerDetails[_offerId];
        require(_offer.status == 0, "Offer not available");
        require(_offer.listerAddress == msg.sender, "Caller has not created the offer");

        _offer.minReceiveAmount = _minReceiveAmount;
        _offer.receiveAmount = _receiveAmount;
    }
}
