// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
// import {console} from "forge-std/Console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../src/Monsterx.sol";

pragma solidity ^0.8.0;

contract AddressToString {
    function toString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}

contract ContractTest is Test, AddressToString {
    using Strings for string;
    uint256 polygonFork;

    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    Monsterx monsterx;
    address testAddr = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address validAddr = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address treasuryAddr = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    address sellerAddr = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address buyerAddr = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f;
    uint256 testToken;
    function setUp() public {
        monsterx = new Monsterx();
        monsterx.setTreasury(treasuryAddr);
        string memory uri = "ipfs://example-token-uri";
        testToken = monsterx.tokenizeAsset(uri);
        polygonFork = vm.createFork(POLYGON_RPC_URL);
        vm.selectFork(polygonFork);
        address[] memory sellers = new address[](1);
        sellers[0] = sellerAddr;
        monsterx.setAdmin(sellers, true);
        monsterx.setCurators(sellers, true);
    }

    function test_balance() public view {
        uint256 testBalance = address(testAddr).balance;
        console.logUint(testBalance / 1e18);
    }

    function test_getMaticBalance() public view {
        int price = monsterx.getLatestMaticPrice();
        console.logInt(price);
    }

    function test_tokenMinting() public {
        string memory uri = "ipfs://example-token-uri";
        uint256 tokenId = monsterx.tokenizeAsset(uri);
        console.log(tokenId, uri, monsterx.tokenURI(tokenId));
        assertTrue(uri.equal(monsterx.getURI(tokenId)));
    }

    function test_listingAsset() public {
        string memory uri = "ipfs://example-listing-uri";
        uint256 price = 100;
        Monsterx.RoyaltyDetails memory royalty = Monsterx.RoyaltyDetails({royaltyWallet: address(0x123), royaltyPercentage: 10});
        Monsterx.PaymentSplit[] memory paymentSplit = new Monsterx.PaymentSplit[](1);
        paymentSplit[0] = Monsterx.PaymentSplit({paymentWallet: address(0x456), paymentPercentage: 90});

        monsterx.listAsset(uri, price, royalty, paymentSplit);
        uint256 tokenId = 2;
        assertEq(monsterx.getSaleDetail(tokenId).price, price);
        assertEq(monsterx.getSaleDetail(tokenId).maticPrice, 0);
    }

    function test_purchaseAssetShouldBeRevert() public {
        vm.expectRevert("Sale is not live");
        monsterx.purchaseAsset{value: 100}(testToken);
    }

    function test_purchaseAssets() public {
        string memory uri = "ipfs://example-listing-uri";
        uint256 price = 100;
        Monsterx.RoyaltyDetails memory royalty = Monsterx.RoyaltyDetails({royaltyWallet: address(0x123), royaltyPercentage: 10});
        Monsterx.PaymentSplit[] memory paymentSplit = new Monsterx.PaymentSplit[](1);
        paymentSplit[0] = Monsterx.PaymentSplit({paymentWallet: address(0x456), paymentPercentage: 90});

        monsterx.listAsset(uri, price, royalty, paymentSplit);
        uint256 tokenId = 2;
        assertEq(monsterx.getSaleDetail(tokenId).price, price);

        uint256 maticAmount = monsterx.getMaticAmount(100);
        monsterx.purchaseAsset{value: maticAmount}(tokenId);
        Monsterx.SaleDetails memory _detail = monsterx.getSaleDetail(tokenId);
        assertEq(_detail.maticPrice, maticAmount);
    }

    function test_purchaseAssetUnminted() public {
        // Setup: Define parameters for the purchase
        string memory uri = "ipfs://example.com/asset.json"; // Example URI
        address royaltyAddress = address(0x123);
        address splitAddress = address(0x456);
        console.logUint(royaltyAddress.balance);
        console.logUint(splitAddress.balance);

        Monsterx.RoyaltyDetails memory royalty = Monsterx.RoyaltyDetails({royaltyWallet: royaltyAddress, royaltyPercentage: 10});
        Monsterx.PaymentSplit[] memory paymentSplit = new Monsterx.PaymentSplit[](1);
        paymentSplit[0] = Monsterx.PaymentSplit({paymentWallet: splitAddress, paymentPercentage: 90});

        // Simulate the balance of the mock address
        address someRandomUser = vm.addr(1);

        // Execute the function
        vm.startPrank(someRandomUser); // Simulate the seller initiating the purchase
        vm.deal(someRandomUser, 100 ether);

        uint256 tokenId = 2;
        uint256 usdAmount = 1e18;
        uint256 maticAmount = monsterx.getMaticAmount(usdAmount);
        monsterx.purchaseAssetUnmited{value: maticAmount}(uri, testAddr, usdAmount, royalty, paymentSplit);
        Monsterx.SaleDetails memory _detail = monsterx.getSaleDetail(tokenId);
        assertEq(_detail.maticPrice, maticAmount);
        console.logUint(royaltyAddress.balance);
        console.logUint(splitAddress.balance);
        vm.stopPrank();
    }

    function test_releaseEscrow() public {
        string memory uri = "ipfs://example-listing-uri";
        uint256 price = 1e18;
        address royaltyAddress = testAddr;
        address splitAddress = validAddr;
        console.log("before release escrow royalty and split address");
        console.logUint(royaltyAddress.balance);
        console.logUint(splitAddress.balance);
        Monsterx.RoyaltyDetails memory royalty = Monsterx.RoyaltyDetails({royaltyWallet: royaltyAddress, royaltyPercentage: 10});
        Monsterx.PaymentSplit[] memory paymentSplit = new Monsterx.PaymentSplit[](1);
        paymentSplit[0] = Monsterx.PaymentSplit({paymentWallet: splitAddress, paymentPercentage: 90});

        vm.startPrank(sellerAddr);
        monsterx.listAsset(uri, price, royalty, paymentSplit);
        uint256 tokenId = 2;
        assertEq(monsterx.getSaleDetail(tokenId).price, price);
        vm.stopPrank();
        address someRandomUser = buyerAddr;

        // Execute the function
        vm.startPrank(someRandomUser); // Simulate the seller initiating the purchase
        vm.deal(someRandomUser, 10 ether);
        uint256 maticAmount = monsterx.getMaticAmount(price);
        monsterx.purchaseAsset{value: maticAmount}(tokenId);

        // check IdToSale struct
        Monsterx.SaleDetails memory _detail = monsterx.getSaleDetail(tokenId);
        console.logAddress(_detail.seller);
        console.logUint(address(_detail.seller).balance);
        monsterx.releaseEscrow(tokenId);
        console.log("after release escrow royalty and split address");
        console.logUint(royaltyAddress.balance);
        console.logUint(splitAddress.balance);
        monsterx.reSaleAsset(tokenId, 100);
        vm.stopPrank();
    }

    function test_placeBid() public {
        monsterx.placeBid{value: 150}(testToken);
        assertEq(monsterx.getBidDetail(testToken).bidder, address(this));
    }

    function test_setAdmin() public {
        address[] memory admins = new address[](1);
        admins[0] = address(0x789);
        monsterx.setAdmin(admins, true);
        assertTrue(monsterx.isAdmin(admins[0]));
    }

    function test_setCuratorShouldRevert() public {
        vm.startPrank(testAddr);
        vm.expectRevert("Access Denied");
        address[] memory addresses = new address[](1);
        addresses[0] = address(testAddr);
        monsterx.setCurators(addresses, true);
        vm.stopPrank();
    }

    function test_setCuratorShouldBeOK() public {
        address[] memory admins = new address[](1);
        admins[0] = address(testAddr);
        monsterx.setAdmin(admins, true);
        assertTrue(monsterx.isAdmin(address(testAddr)));

        vm.startPrank(testAddr);
        address[] memory addresses = new address[](1);
        addresses[0] = address(testAddr);
        monsterx.setCurators(addresses, true);
        assertTrue(monsterx.isAdmin(addresses[0]));
        vm.stopPrank();
    }
}
