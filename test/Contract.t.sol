// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Test.sol";
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

    Monsterx monsterx;
    address testAddr = makeAddr("Test");
    address validAddr = makeAddr("Valid");
    uint256 testToken;
    function setUp() public {
        monsterx = new Monsterx();
        string memory uri = "ipfs://example-token-uri";
        testToken = monsterx.tokenizeAsset(uri);
    }

    function testTokenMinting() public {
        string memory uri = "ipfs://example-token-uri";
        uint256 tokenId = monsterx.tokenizeAsset(uri);
        console.log(tokenId, uri, monsterx.tokenURI(tokenId));
        assertTrue(uri.equal(monsterx.getURI(tokenId)));
    }

    function testListingAsset() public {
        string memory uri = "ipfs://example-listing-uri";
        uint256 price = 100;
        Monsterx.RoyaltyDetails memory royalty = Monsterx.RoyaltyDetails({royaltyWallet: address(0x123), royaltyPercentage: 10});
        Monsterx.PaymentSplit[] memory paymentSplit = new Monsterx.PaymentSplit[](1);
        paymentSplit[0] = Monsterx.PaymentSplit({paymentWallet: address(0x456), paymentPercentage: 90});

        monsterx.listAsset(uri, price, royalty, paymentSplit);
        uint256 tokenId = 2;
        assertEq(monsterx.getSaleDetail(tokenId).price, price);
    }

    function testPurchaseAsset() public {
        vm.expectRevert("Sale is not live");
        monsterx.purchaseAsset{value: 100}(testToken);
    }

    function testPlaceBid() public {
        monsterx.placeBid{value: 150}(testToken);
        assertEq(monsterx.getBidDetail(testToken).bidder, address(this));
    }

    function testSetAdmin() public {
        address[] memory admins = new address[](1);
        admins[0] = address(0x789);
        monsterx.setAdmin(admins, true);
        assertTrue(monsterx.isAdmin(admins[0]));
    }

    function testSetCuratorShouldRevert() public {
        vm.startPrank(testAddr);
        vm.expectRevert("Access Denied");
        address[] memory addresses = new address[](1);
        addresses[0] = address(testAddr);
        monsterx.setCurators(addresses, true);
        vm.stopPrank();
    }

    function testSetCuratorShouldBeOK() public {
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
