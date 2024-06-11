// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

// ====== External imports ======
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
//  ==========  Internal imports    ==========

contract Monsterx is IERC721Receiver, ERC721, ReentrancyGuard, Ownable {

    using Counters for Counters.Counter;

    Counters.Counter public tokenCounter;
    Counters.Counter public bidCounter;

    mapping(uint256 => string) public uri; //returns uris for particular token id
    enum SaleStatus{NotForSale, Active, Ordered, Dispute, CancellationRequested, Sold, Cancelled }
    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isCurator;
    mapping(address => uint256) public sellerEscrowAmount;
    address public  treasury;
    uint256 public fee = 100; //1%
    uint256 public escrowReleaseTime;


    constructor() ERC721("MonsterX", "MonsterX"){
       isAdmin[msg.sender] = true;
       treasury = msg.sender;
       isCurator[msg.sender] = true;
    }

    //struct for each market item
    struct SaleDetails {
        uint256 tokenId;
        address seller;
        address buyer;
        uint256 price;
        uint256 status;
        uint256 shipmentTime;
        string description;
    }

    struct RoyaltyDetails{
        address royaltyWallet;
        uint256 royaltyPercentage;
    }

    struct BidDetails{
        uint256 tokenId;
        address bidder;
        uint256 bidAmount;
    }

    struct PaymentSplit{
        address paymentWallet;
        uint256 paymentPercentage;
    }

    mapping(uint256 => SaleDetails) public idToSale;
    mapping(uint256 => RoyaltyDetails) public idToRoyalty;
    mapping(uint256 => PaymentSplit[]) public idToPaymentSplit;
    mapping(uint256 => BidDetails) public idToBid;
    mapping(uint256 => uint256[]) public tokenOffers;

    event AssetListed(
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );

    event AssetPurchased(
        uint256 indexed tokenId,
        address buyer,
        uint256 price
    );

    event EscrowAdded(
        address seller,
        uint256 amount
    );

    event EscrowReleased(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 amount
    );

    event CancellationRequested(
        uint256 indexed tokenId,
        string description
    );

    event DisputeReported(
        uint256 indexed tokenId,
        string description
    );

    event DisputeResolved(
        uint256 indexed tokenId,
        uint256 indexed status
    );

    event SaleCancelled(
        uint256 indexed tokenId,
        string description
    );

    event SaleEnded(
        uint256 indexed tokenId
    );

    event AssetTokenized(
        uint256 indexed tokenId,
        string uri
    );

    event MarketplaceFee(
        uint256 indexed tokenId,
        uint256 feeAmount,
        address buyer
    );

    event RoyaltiesReceived(
        uint256 indexed tokenId,
        address indexed wallet,
        uint256 royaltyAmount
    );

    event PaymentSplitReceived(
        uint256 indexed tokenId,
        uint256 feeAmount,
        address indexed wallet
    );

    event BidPlaced(
        uint256 indexed tokenId,
        uint256 bidId,
        address bidder,
        uint256 bidAmount
    );

    event BidRejected(
        uint256 bidId,
        address bidder,
        uint256 bidAmount
    );

    event BidAccepted(
        uint256 bidId,
        address bidder,
        uint256 bidAmount
    );

    event NftBurned(address owner, uint256 tokenId);

    function tokenizeAsset(string memory _uri) public nonReentrant returns(uint256 tokenId) {
        tokenCounter.increment();
        uint256 _tokenId = tokenCounter.current();
        _mint(address(this), _tokenId);
        uri[_tokenId] = _uri;
        emit AssetTokenized(_tokenId, _uri);
        return(_tokenId);
    }

    function listAsset(string memory _uri, uint256 price,
     RoyaltyDetails memory royalty, PaymentSplit[] memory _paymentSplit) external{ 
        require(isCurator[msg.sender] == true, "Only Curators can mint");
        uint256 _tokenId = tokenizeAsset(_uri);
        idToSale[_tokenId] = SaleDetails(
        _tokenId,
        msg.sender,
        address(0),
        price, 
        uint256(SaleStatus.Active),
        0,
        ""
        );
        idToRoyalty[_tokenId] = royalty;
        for(uint256 i =0; i < _paymentSplit.length ; i++){
            idToPaymentSplit[_tokenId].push(_paymentSplit[i]);
        } 
        emit AssetListed(_tokenId, msg.sender, price);

    } 
   
    function reSaleAsset(uint256 _tokenId, uint256 price) external nonReentrant{
        require(_exists(_tokenId), "Nonexistent token");
        require(IERC721(address(this)).ownerOf(_tokenId) == msg.sender,"NFT not owned");
        IERC721(address(this)).safeTransferFrom(msg.sender, address(this), _tokenId);
        idToSale[_tokenId] = SaleDetails(
        _tokenId,
        msg.sender,
        address(0),
        price,
        uint256(SaleStatus.Active),
        block.timestamp,
        ""
        );
        emit AssetListed(_tokenId, msg.sender, price);
    }

    function purchaseAsset(uint256 _tokenId) external payable nonReentrant{
        require(_exists(_tokenId), "Nonexistent token");
        require(idToSale[_tokenId].status == uint256(SaleStatus.Active), "Sale is not live");
        require(msg.value == idToSale[_tokenId].price, " Incorrect Amount");
        idToSale[_tokenId].buyer = msg.sender;
        idToSale[_tokenId].shipmentTime = block.timestamp;
        idToSale[_tokenId].status = uint256(SaleStatus.Ordered);
        sellerEscrowAmount[idToSale[_tokenId].seller] += msg.value;
        refundOtherOffers(_tokenId, 0);
        emit EscrowAdded(idToSale[_tokenId].seller, msg.value);
        emit AssetPurchased(_tokenId, msg.sender, msg.value);

    }

    function purchaseAssetUnmited(string memory _uri, address seller, RoyaltyDetails memory royalty, PaymentSplit[] memory _paymentSplit) external payable nonReentrant{
        uint256 _tokenId = tokenizeAsset(_uri);
        idToSale[_tokenId] = SaleDetails(
        _tokenId,
        seller,
        msg.sender,
        msg.value, 
        uint256(SaleStatus.Active),
        block.timestamp,
        ""
        );
        idToRoyalty[_tokenId] = royalty;
        for(uint256 i =0; i < _paymentSplit.length ; i++){
            idToPaymentSplit[_tokenId].push(_paymentSplit[i]);
        }
        idToSale[_tokenId].buyer = msg.sender;
        idToSale[_tokenId].shipmentTime = block.timestamp;
        idToSale[_tokenId].status = uint256(SaleStatus.Ordered);
        sellerEscrowAmount[idToSale[_tokenId].seller] += msg.value;
        refundOtherOffers(_tokenId, 0);
        emit EscrowAdded(idToSale[_tokenId].seller, msg.value);
        emit AssetPurchased(_tokenId, msg.sender, msg.value);

    }


    function releaseEscrow(uint256 _tokenId) public nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(msg.sender == idToSale[_tokenId].buyer || isAdmin[msg.sender], "Only buyer or Admin can confirm delivery");
        idToSale[_tokenId].status = uint256(SaleStatus.Sold);
        idToSale[_tokenId].description = "The Asset was delivered and Escrow was released";
        fundDistribution(_tokenId);
        safeTransferFrom(address(this), idToSale[_tokenId].buyer, _tokenId);
        
    }

    function fundDistribution(uint256 _tokenId) private{
        uint256 _fee = (idToSale[_tokenId].price * fee)/10000;
        payable(treasury).transfer(_fee);
        emit MarketplaceFee(_tokenId, _fee, idToSale[_tokenId].buyer);

        uint256 _royalty = (idToRoyalty[_tokenId].royaltyPercentage * (idToSale[_tokenId].price - _fee))/10000;
        payable(idToRoyalty[_tokenId].royaltyWallet).transfer(_royalty);
        emit RoyaltiesReceived(_tokenId, idToRoyalty[_tokenId].royaltyWallet, _royalty);

        uint256 _paymentSplit;
        if(idToPaymentSplit[_tokenId].length >0){
            for(uint256 i =0; i < idToPaymentSplit[_tokenId].length ; i++){

            _paymentSplit += (idToPaymentSplit[_tokenId][i].paymentPercentage *
            (idToSale[_tokenId].price - _fee - _royalty))/10000;
            
            payable(idToPaymentSplit[_tokenId][i].paymentWallet).transfer
            ((idToPaymentSplit[_tokenId][i].paymentPercentage * (idToSale[_tokenId].price - _fee - _royalty))/10000);

            emit PaymentSplitReceived(_tokenId, 
            (idToPaymentSplit[_tokenId][i].paymentPercentage * (idToSale[_tokenId].price - _fee - _royalty))/10000, 
            idToPaymentSplit[_tokenId][i].paymentWallet);
        }
        
            payable(idToSale[_tokenId].seller).transfer(idToSale[_tokenId].price -(_royalty + _fee + _paymentSplit));
            sellerEscrowAmount[idToSale[_tokenId].seller] -= idToSale[_tokenId].price;
            emit EscrowReleased(_tokenId, idToSale[_tokenId].seller,
            idToSale[_tokenId].price -(_royalty + _fee + _paymentSplit));
       
            delete idToPaymentSplit[_tokenId];    
        }
    }

    function requestCancellation(uint256 _tokenId, string memory description) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(msg.sender == idToSale[_tokenId].buyer, "Only buyer can request cancellation");
        idToSale[_tokenId].status = uint256(SaleStatus.CancellationRequested);
        idToSale[_tokenId].description = description;
        emit CancellationRequested(_tokenId,description);
    }

    function endSale(uint256 _tokenId) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(idToSale[_tokenId].status == uint256(SaleStatus.Active), "Sale is not live");
        require(msg.sender == idToSale[_tokenId].seller, "Only seller can end Sale");
        safeTransferFrom(address(this), idToSale[_tokenId].seller, _tokenId);
        idToSale[_tokenId] = SaleDetails(
        _tokenId,
        idToSale[_tokenId].seller,
        address(0),
        0,
        uint256(SaleStatus.Cancelled),
        0,
        ""
        );
        emit SaleEnded(_tokenId);
    }

    function cancelOrder(uint256 _tokenId, string memory description) public nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(isAdmin[msg.sender] = true,"Only admin can cancel");
        payable(idToSale[_tokenId].buyer).transfer(idToSale[_tokenId].price);
        sellerEscrowAmount[idToSale[_tokenId].seller] -= idToSale[_tokenId].price;
        safeTransferFrom(address(this), idToSale[_tokenId].seller, _tokenId);
        idToSale[_tokenId] = SaleDetails(
        _tokenId,
        idToSale[_tokenId].seller,
        address(0),
        0,
        uint256(SaleStatus.Cancelled),
        0,
        description
        );
        emit SaleCancelled(_tokenId, description);

    }

    function reportDispute(uint256 _tokenId, string memory description) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(msg.sender == idToSale[_tokenId].seller, "Only seller of this token can report");
        require(idToSale[_tokenId].status == uint256(SaleStatus.Ordered), "The item has not been ordered");
        require(block.timestamp > idToSale[_tokenId].shipmentTime +  escrowReleaseTime, "Wait for Escrow Release Time");
        idToSale[_tokenId].status = uint256(SaleStatus.Dispute);
        idToSale[_tokenId].description = description;
        emit DisputeReported(_tokenId, description);
    }

    function resolveDispute(uint256 _tokenId, bool _releaseEscrow, string memory description) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(isAdmin[msg.sender] = true,"Only admin can cancel");
        require(idToSale[_tokenId].status == uint256(SaleStatus.Dispute) ||
        idToSale[_tokenId].status == uint256(SaleStatus.CancellationRequested),"No Dispute Reported");
        if(_releaseEscrow){
            releaseEscrow(_tokenId);
        }
        else{
            cancelOrder(_tokenId, description);
        }
        emit DisputeResolved(_tokenId, idToSale[_tokenId].status);

    }

    function placeBid(uint256 _tokenId) external payable nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(idToSale[_tokenId].status == uint256(SaleStatus.NotForSale) || idToSale[_tokenId].status == uint256(SaleStatus.Active) || idToSale[_tokenId].status == uint256(SaleStatus.Sold)
        || idToSale[_tokenId].status == uint256(SaleStatus.Cancelled), "Order Purchased");
        bidCounter.increment();
        uint256 bidCount = bidCounter.current();
        idToBid[bidCount] = BidDetails(
           _tokenId,
           msg.sender,
           msg.value
        );
        tokenOffers[_tokenId].push(bidCount);
        emit BidPlaced(_tokenId, bidCount, msg.sender, msg.value);
    } 

    function placeBidUnminted(string memory _uri, address seller, uint256 price, RoyaltyDetails memory royalty, PaymentSplit[] memory _paymentSplit) external payable nonReentrant {
        uint256 _tokenId = tokenizeAsset(_uri);
        idToSale[_tokenId] = SaleDetails(
        _tokenId,
        seller,
        address(0),
        price, 
        uint256(SaleStatus.Active),
        0,
        ""
        );
        idToRoyalty[_tokenId] = royalty;
        for(uint256 i =0; i < _paymentSplit.length ; i++){
            idToPaymentSplit[_tokenId].push(_paymentSplit[i]);
        }
        bidCounter.increment();
        uint256 bidCount = bidCounter.current();
        idToBid[bidCount] = BidDetails(
           _tokenId,
           msg.sender,
           msg.value 
        );
        tokenOffers[_tokenId].push(bidCount);
        emit BidPlaced(_tokenId, bidCount, msg.sender, msg.value);

    }  
 
    function acceptBid(uint256 _tokenId, uint256 _bidId) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(idToBid[_bidId].tokenId == _tokenId, "Bid not related to token");
        require(idToSale[_tokenId].status == uint256(SaleStatus.NotForSale) || idToSale[_tokenId].status == uint256(SaleStatus.Active) || idToSale[_tokenId].status == uint256(SaleStatus.Sold)
        || idToSale[_tokenId].status == uint256(SaleStatus.Cancelled), "Order Purchased");
        require(msg.sender == idToSale[_tokenId].seller || msg.sender == idToSale[_tokenId].buyer, "Only seller or buyer can accept offers");
        if(ownerOf(_tokenId) != address(this)){
            IERC721(address(this)).safeTransferFrom(msg.sender, address(this), _tokenId);
        }
        idToSale[_tokenId].buyer = idToBid[_bidId].bidder;
        idToSale[_tokenId].shipmentTime = block.timestamp;
        idToSale[_tokenId].status = uint256(SaleStatus.Ordered);
        sellerEscrowAmount[idToSale[_tokenId].seller] += idToBid[_bidId].bidAmount;
        emit BidAccepted(_bidId, idToBid[_bidId].bidder, idToBid[_bidId].bidAmount);
        emit EscrowAdded(idToSale[_tokenId].seller, idToBid[_bidId].bidAmount);
        emit AssetPurchased(_tokenId, idToBid[_bidId].bidder, idToBid[_bidId].bidAmount);
        refundOtherOffers(_tokenId, _bidId);

    }   

    function refundOtherOffers(uint256 _tokenId, uint256 _bidId) private {
        uint256 totalBids = tokenOffers[_tokenId].length;
        for(uint256 i =0; i< totalBids; i++){
            if(tokenOffers[_tokenId][i] != _bidId){
                payable(idToBid[tokenOffers[_tokenId][i]].bidder).transfer(idToBid[tokenOffers[_tokenId][i]].bidAmount);
                emit BidRejected(tokenOffers[_tokenId][i], idToBid[tokenOffers[_tokenId][i]].bidder,
                idToBid[tokenOffers[_tokenId][i]].bidAmount);
            }
        }
        delete tokenOffers[_tokenId];
    }

    function cancelBid(uint256 _bid) external nonReentrant {
        require(msg.sender == idToBid[_bid].bidder,"Only bidder can cancel");
        uint256 _tokenId = idToBid[_bid].tokenId;
        uint256 totalBids = tokenOffers[_tokenId].length;
        uint256 bidPlace;
        payable(idToBid[_bid].bidder).transfer(idToBid[_bid].bidAmount); 
        
        for(uint256 i =0; i< totalBids; i++){
             if(tokenOffers[_tokenId][i] == _bid){
                bidPlace = i;
                emit BidRejected(tokenOffers[_tokenId][i], idToBid[tokenOffers[_tokenId][i]].bidder,
                idToBid[tokenOffers[_tokenId][i]].bidAmount);
                break;
            }

        }
        if(bidPlace != totalBids-1){
           for(uint256 i = bidPlace; i<totalBids-1;i++){
            tokenOffers[_tokenId][i] = tokenOffers[_tokenId][i+1];
        }
        }     
        else{
            tokenOffers[_tokenId].pop();

        }  
    }

    function burnNft(uint256 _tokenId)external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(idToSale[_tokenId].status == uint256(SaleStatus.NotForSale) || idToSale[_tokenId].status == uint256(SaleStatus.Active) || idToSale[_tokenId].status == uint256(SaleStatus.Sold)
        || idToSale[_tokenId].status == uint256(SaleStatus.Cancelled), "NFT Purchased");
        require(ownerOf(_tokenId) == msg.sender || idToSale[_tokenId].seller == msg.sender, "Access Denied" );
        _burn(_tokenId);
        emit NftBurned(msg.sender, _tokenId);
    }

    function getAllBids(uint256 _tokenId) external view returns(uint256[] memory){
        require(_exists(_tokenId), "Nonexistent token");
        uint256[] memory _allBids = new uint256[](tokenOffers[_tokenId].length);
        _allBids = tokenOffers[_tokenId];
        return(_allBids);
    }
  
    function getURI(uint256 _tokenId) external view returns (string memory) {
        require(_exists(_tokenId), "Nonexistent token");
        return uri[_tokenId];
    }
    function getSaleDetail(uint256 _tokenId) external view returns(SaleDetails memory) {
        require(_exists(_tokenId), "Nonexistent token");
        return idToSale[_tokenId];
    }

    function getBidDetail(uint256 _tokenId) external view returns(BidDetails memory) {
        require(_exists(_tokenId), "Nonexistent token");
        return idToBid[_tokenId];
    }

    function updateUri(uint256 _tokenId, string memory _uri) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(isAdmin[msg.sender], "Access Denied");
        uri[_tokenId] = _uri;
    }

    function updatePrice(uint256 _tokenId, uint256 price) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(idToSale[_tokenId].status == uint256(SaleStatus.Active), "Sale is not live");
        require(msg.sender == idToSale[_tokenId].seller, "Only seller can change the price");
        idToSale[_tokenId].price = price;
    }

    function onERC721Received(address, address, uint256, bytes memory) public nonReentrant virtual override returns(bytes4) {
        return this.onERC721Received.selector;
    }

    function withdrawNft(uint256 _tokenId) external nonReentrant {
        require(_exists(_tokenId), "Nonexistent token");
        require(isAdmin[msg.sender], "Access Denied");
        safeTransferFrom(address(this), msg.sender, _tokenId);
    }

    function withdrawTokens(IERC20 token, address wallet) external nonReentrant onlyOwner {
		uint256 balanceOfContract = token.balanceOf(address(this));
		token.transfer(wallet, balanceOfContract);
	}

	function withdrawFunds(address wallet) external nonReentrant onlyOwner {
		uint256 balanceOfContract = address(this).balance;
		payable(wallet).transfer(balanceOfContract);
	}

    function setAdmin(address[] memory admins, bool _isAdmin) external nonReentrant onlyOwner {
        for(uint256 i=0;i<admins.length;i++){
            isAdmin[admins[i]] = _isAdmin;
        }
    }

    function setCurators(address[] memory curators, bool _isCurator) external nonReentrant {
        require(isAdmin[msg.sender], "Access Denied");
        for(uint256 i=0;i < curators.length;i++){
            isCurator[curators[i]] = _isCurator;
        }
    }

    function setFee(uint256 _fee) external nonReentrant {
        require(isAdmin[msg.sender], "Access Denied");
        fee = _fee;
    }

    function setTreasury(address _treasury) external nonReentrant onlyOwner{
        treasury = _treasury;
    }

    function setEscrowReleaseTime(uint256 _time) external nonReentrant {
        require(isAdmin[msg.sender], "Access Denied");
        escrowReleaseTime = _time;
    }


    receive() external payable {}
    fallback() external payable {}
}