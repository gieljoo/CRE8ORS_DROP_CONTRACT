// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
// Forge Imports
import {DSTest} from "ds-test/test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
// interface imports
import {ICollectionHolderMint} from "../../src/interfaces/ICollectionHolderMint.sol";
import {ICre8ors} from "../../src/interfaces/ICre8ors.sol";
import {IERC721A} from "../../lib/ERC721A/contracts/interfaces/IERC721A.sol";
import {IERC721Drop} from "../../src/interfaces/IERC721Drop.sol";
import {IFriendsAndFamilyMinter} from "../../src/interfaces/IFriendsAndFamilyMinter.sol";
import {IMinterUtilities} from "../../src/interfaces/IMinterUtilities.sol";
import {ILockup} from "../../src/interfaces/ILockup.sol";
import {IERC721ACH} from "ERC721H/interfaces/IERC721ACH.sol";
// contract imports
import {CollectionHolderMint} from "../../src/minter/CollectionHolderMint.sol";
import {Cre8ors} from "../../src/Cre8ors.sol";
import {Cre8orTestBase} from "../utils/Cre8orTestBase.sol";
import {DummyMetadataRenderer} from "../utils/DummyMetadataRenderer.sol";
import {FriendsAndFamilyMinter} from "../../src/minter/FriendsAndFamilyMinter.sol";
import {Lockup} from "../../src/utils/Lockup.sol";
import {MinterUtilities} from "../../src/utils/MinterUtilities.sol";
import {Cre8ing} from "../../src/Cre8ing.sol";
import {OwnerOfHook} from "../../src/hooks/OwnerOf.sol";
import {TransferHook} from "../../src/hooks/Transfers.sol";
import {Subscription} from "../../src/subscription/Subscription.sol";
import {IERC721ACH} from "ERC721H/interfaces/IERC721ACH.sol";

contract CollectionHolderMintTest is DSTest, StdUtils {
    struct TierInfo {
        uint256 price;
        uint256 lockup;
    }
    DummyMetadataRenderer public dummyRenderer = new DummyMetadataRenderer();
    address public constant DEFAULT_OWNER_ADDRESS = address(0x23499);
    address public constant DEFAULT_BUYER_ADDRESS = address(0x111);
    address payable public constant DEFAULT_FUNDS_RECIPIENT_ADDRESS =
        payable(address(0x21303));
    uint64 DEFAULT_EDITION_SIZE = 888;
    uint16 DEFAULT_ROYALTY_BPS = 888;
    Cre8ors public cre8orsNFTBase;
    Cre8ing public cre8ingBase;
    Cre8ors public cre8orsPassport;
    MinterUtilities public minterUtility;
    CollectionHolderMint public minter;
    FriendsAndFamilyMinter public friendsAndFamilyMinter;
    TransferHook public transferHookCre8orsNFTBase;
    TransferHook public transferHookCre8orsPassport;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    Lockup lockup = new Lockup();
    bool _withoutLockup = false;

    OwnerOfHook public ownerOfHook;
    TransferHook public transferHook;
    Subscription public subscription;

    uint64 public constant ONE_YEAR_DURATION = 365 days;

    function setUp() public {
        cre8orsNFTBase = _setUpContracts();
        cre8orsPassport = _setUpContracts();
        minterUtility = new MinterUtilities(
            address(cre8orsNFTBase),
            50000000000000000,
            100000000000000000,
            150000000000000000
        );
        friendsAndFamilyMinter = new FriendsAndFamilyMinter(
            address(cre8orsNFTBase),
            address(minterUtility)
        );

        minter = new CollectionHolderMint(
            address(cre8orsNFTBase),
            address(cre8orsPassport),
            address(minterUtility),
            address(friendsAndFamilyMinter)
        );
        cre8ingBase = new Cre8ing();

        subscription = _setupSubscription();

        transferHook = _setupTransferHook();
        ownerOfHook = _setupOwnerOfHook();

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        transferHookCre8orsNFTBase.setCre8ing(address(cre8ingBase));
        transferHookCre8orsPassport.setCre8ing(address(cre8ingBase));
        cre8orsNFTBase.setHook(
            IERC721ACH.HookType.BeforeTokenTransfers,
            address(transferHookCre8orsNFTBase)
        );
        cre8orsPassport.setHook(
            IERC721ACH.HookType.BeforeTokenTransfers,
            address(transferHookCre8orsPassport)
        );
        vm.stopPrank();
    }

    function testLockup() public {
        assertEq(
            address(cre8ingBase.lockup(address(cre8orsNFTBase))),
            address(0)
        );
    }

    function testMintingUtility() public {
        assertEq(
            address(minter.minterUtilityContractAddress()),
            address(minterUtility)
        );
    }

    function testSetNewMinterContract(address _minter) public {
        _setUpMinter();
        vm.prank(DEFAULT_OWNER_ADDRESS);
        minter.setNewMinterUtilityContractAddress(_minter);
        assertEq(address(minter.minterUtilityContractAddress()), _minter);
    }

    function testSuccessfulMint(address _buyer, uint256 _mintQuantity) public {
        vm.assume(_buyer != address(0));
        vm.assume(_mintQuantity > 0);
        vm.assume(_mintQuantity < DEFAULT_EDITION_SIZE);
        _setUpMinter();
        uint256[] memory tokens = generateTokens(_mintQuantity);
        vm.startPrank(_buyer);
        cre8orsPassport.purchase(_mintQuantity);
        assertTrue(
            cre8orsNFTBase.hasRole(
                cre8orsNFTBase.MINTER_ROLE(),
                address(minter)
            )
        );
        uint256 pfpID = minter.mint(tokens, _buyer);
        assertEq(tokens.length, pfpID);
        assertEq(tokens.length, cre8orsNFTBase.balanceOf(_buyer));
        assertEq(
            0,
            cre8orsNFTBase.mintedPerAddress(address(minter)).totalMints
        );
        assertEq(
            tokens.length,
            cre8orsNFTBase.mintedPerAddress(_buyer).totalMints
        );

        // Subscription Asserts
        assertTrue(subscription.isSubscriptionValid(pfpID));

        // 1 year passed
        vm.warp(block.timestamp + ONE_YEAR_DURATION);

        // ownerOf should return address(0)
        assertEq(cre8orsNFTBase.ownerOf(pfpID), address(0));
        assertTrue(!subscription.isSubscriptionValid(pfpID));
    }

    function testSuccessfulMintWithStaking(
        address _buyer,
        uint256 _mintQuantity
    ) public {
        testSuccessfulMint(_buyer, _mintQuantity);
        uint256[] memory tokens = generateTokens(_mintQuantity);
        for (uint256 i = 0; i < tokens.length; ) {
            assertTrue(
                cre8ingBase.getCre8ingStarted(
                    address(cre8orsNFTBase),
                    tokens[i]
                ) > 0
            );
            unchecked {
                i++;
            }
        }
    }

    function testSuccessfulMintWithDiscount(
        address _buyer,
        uint256 _mintQuantity
    ) public {
        vm.assume(_mintQuantity > 0);
        vm.assume(_buyer != address(0));
        vm.assume(_mintQuantity < DEFAULT_EDITION_SIZE);
        uint256[] memory tokens = generateTokens(_mintQuantity);
        _setUpMinter();

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        cre8orsNFTBase.grantRole(
            cre8orsNFTBase.DEFAULT_ADMIN_ROLE(),
            address(friendsAndFamilyMinter)
        );
        friendsAndFamilyMinter.addDiscount(_buyer);
        vm.stopPrank();
        vm.startPrank(_buyer);
        cre8orsPassport.purchase(_mintQuantity);
        assertTrue(
            cre8orsNFTBase.hasRole(
                cre8orsNFTBase.MINTER_ROLE(),
                address(minter)
            )
        );
        uint256 pfpID = minter.mint(tokens, _buyer);
        assertEq(tokens.length + 1, pfpID);
        assertEq(tokens.length + 1, cre8orsNFTBase.balanceOf(_buyer));
        assertEq(
            0,
            cre8orsNFTBase.mintedPerAddress(address(minter)).totalMints
        );
        assertEq(
            tokens.length + 1,
            cre8orsNFTBase.mintedPerAddress(_buyer).totalMints
        );
        vm.stopPrank();

        // Subscription Asserts
        assertTrue(subscription.isSubscriptionValid(pfpID));

        // 1 year passed
        vm.warp(block.timestamp + ONE_YEAR_DURATION);

        // ownerOf should return address(0)
        assertEq(cre8orsNFTBase.ownerOf(pfpID), address(0));
        assertTrue(!subscription.isSubscriptionValid(pfpID));
    }

    function testTotalMintsWithTransfer(
        address _buyer,
        address _recipient,
        uint256 _mintQuantity
    ) public {
        vm.assume(_mintQuantity > 0);
        vm.assume(_buyer != address(0));
        vm.assume(_recipient != address(0));
        vm.assume(_recipient.code.length == 0); // make sure it is an EOA
        vm.assume(_mintQuantity < DEFAULT_EDITION_SIZE);

        vm.startPrank(_buyer);
        cre8orsPassport.purchase(_mintQuantity);
        assertEq(
            _mintQuantity,
            cre8orsPassport.mintedPerAddress(_buyer).totalMints
        );

        cre8orsPassport.safeTransferFrom(_buyer, _recipient, 1);
        vm.stopPrank();
        assertEq(
            _mintQuantity,
            cre8orsPassport.mintedPerAddress(_buyer).totalMints
        );
    }

    function testRevertAlreadyClaimed(
        address _buyer,
        uint256 _passportQuantity
    ) public {
        vm.assume(_buyer != address(0));
        vm.assume(_passportQuantity > 0);
        vm.assume(_passportQuantity < DEFAULT_EDITION_SIZE);
        _setUpMinter();
        uint256[] memory tokens = generateTokens(_passportQuantity);

        vm.startPrank(_buyer);
        cre8orsPassport.purchase(_passportQuantity);
        minter.mint(tokens, _buyer);
        vm.expectRevert(ICollectionHolderMint.AlreadyClaimedFreeMint.selector);
        minter.mint(tokens, _buyer);
        vm.stopPrank();

        // Due to Revert there will be no tokenId greater than tokens.length
        uint256 tokenId = tokens.length + 1;

        assertTrue(!subscription.isSubscriptionValid(tokenId));
        assertEq(cre8orsNFTBase.ownerOf(tokenId), address(0));
    }

    function testRevertNotOwnerOfPassport(
        address _buyer,
        address _caller,
        uint256 _mintQuantity
    ) public {
        vm.assume(_buyer != address(0));
        vm.assume(_caller != address(0));
        vm.assume(_buyer != _caller);
        vm.assume(_mintQuantity > 0);
        vm.assume(_mintQuantity < DEFAULT_EDITION_SIZE);
        _setUpMinter();
        uint256[] memory tokens = generateTokens(_mintQuantity);

        vm.startPrank(_buyer);
        cre8orsPassport.purchase(_mintQuantity);
        vm.expectRevert(IERC721A.ApprovalCallerNotOwnerNorApproved.selector);
        minter.mint(tokens, _caller);
        vm.stopPrank();
    }

    function testManualPassportClaimToggle(
        address _buyer,
        uint256 _mintQuantity
    ) public {
        vm.assume(_buyer != address(0));
        vm.assume(_mintQuantity > 0);
        vm.assume(_mintQuantity < DEFAULT_EDITION_SIZE);
        _setUpMinter();
        vm.startPrank(_buyer);
        uint256[] memory tokens = generateTokens(_mintQuantity);

        cre8orsPassport.purchase(_mintQuantity);

        minter.mint(tokens, _buyer);

        vm.stopPrank();

        assertTrue(minter.freeMintClaimed(1));
        vm.prank(DEFAULT_OWNER_ADDRESS);
        minter.toggleHasClaimedFreeMint(1);
        assert(!minter.freeMintClaimed(1));

        // Subscription Asserts
        for (uint256 i = 0; i < tokens.length; i++) {
            assertTrue(subscription.isSubscriptionValid(tokens[i]));
        }

        // 1 year passed
        vm.warp(block.timestamp + ONE_YEAR_DURATION);

        for (uint256 i = 0; i < tokens.length; i++) {
            // ownerOf should return address(0)
            assertEq(cre8orsNFTBase.ownerOf(tokens[i]), address(0));
            assertTrue(!subscription.isSubscriptionValid(tokens[i]));
        }
    }

    function testRevertEmptyList(address _buyer) public {
        vm.assume(_buyer != address(0));
        _setUpMinter();
        vm.expectRevert(ICollectionHolderMint.NoTokensProvided.selector);
        minter.mint(new uint256[](0), _buyer);
    }

    function testRevertDuplicatesFound(address _buyer) public {
        vm.assume(_buyer != address(0));
        _setUpMinter();
        vm.expectRevert(ICollectionHolderMint.DuplicatesFound.selector);
        uint256[] memory tokens = generateTokens(2);
        tokens[0] = uint256(1);
        tokens[1] = tokens[0];
        minter.mint(tokens, _buyer);
    }

    function _setUpMinter() internal {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        cre8orsNFTBase.grantRole(cre8orsNFTBase.MINTER_ROLE(), address(minter));
        cre8orsNFTBase.grantRole(
            cre8orsNFTBase.MINTER_ROLE(),
            address(cre8ingBase)
        );
        cre8ingBase.setCre8ingOpen(address(cre8orsNFTBase), true);

        cre8ingBase.setLockup(address(cre8orsNFTBase), lockup);
        assertTrue(minter.minterUtilityContractAddress() != address(0));

        assertTrue(
            cre8orsNFTBase.hasRole(
                cre8orsNFTBase.MINTER_ROLE(),
                address(minter)
            )
        );
        vm.stopPrank();
    }

    function generateTokens(
        uint256 quantity
    ) internal pure returns (uint256[] memory) {
        uint256[] memory tokens = new uint256[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            tokens[i] = i + 1;
        }
        return tokens;
    }

    function _setUpContracts() internal returns (Cre8ors) {
        return
            new Cre8ors({
                _contractName: "CRE8ORS",
                _contractSymbol: "CRE8",
                _initialOwner: DEFAULT_OWNER_ADDRESS,
                _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
                _editionSize: DEFAULT_EDITION_SIZE,
                _royaltyBPS: DEFAULT_ROYALTY_BPS,
                _metadataRenderer: dummyRenderer,
                _salesConfig: IERC721Drop.SalesConfiguration({
                    publicSaleStart: 0,
                    erc20PaymentToken: address(0),
                    publicSaleEnd: type(uint64).max,
                    presaleStart: 0,
                    presaleEnd: 0,
                    publicSalePrice: 0,
                    maxSalePurchasePerAddress: 0,
                    presaleMerkleRoot: bytes32(0)
                })
            });
    }

    function _setMinterRole(address _assignee) internal {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        cre8orsNFTBase.grantRole(
            cre8orsNFTBase.MINTER_ROLE(),
            address(_assignee)
        );
        vm.stopPrank();
    }

    function _setupOwnerOfHook() internal returns (OwnerOfHook) {
        ownerOfHook = new OwnerOfHook();
        _setMinterRole(address(ownerOfHook));

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        // set hook
        cre8orsNFTBase.setHook(
            IERC721ACH.HookType.OwnerOf,
            address(ownerOfHook)
        );
        // set subscription
        ownerOfHook.setSubscription(
            address(cre8orsNFTBase),
            address(subscription)
        );
        vm.stopPrank();

        return ownerOfHook;
    }

    function _setupTransferHook() internal returns (TransferHook) {
        transferHook = new TransferHook();
        _setMinterRole(address(transferHook));

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        // set hook
        cre8orsNFTBase.setHook(
            IERC721ACH.HookType.AfterTokenTransfers,
            address(transferHook)
        );
        // set subscription
        transferHook.setSubscription(
            address(cre8orsNFTBase),
            address(subscription)
        );
        vm.stopPrank();

        return transferHook;
    }

    function _setupSubscription() internal returns (Subscription) {
        subscription = new Subscription({
            cre8orsNFT_: address(cre8orsNFTBase),
            minRenewalDuration_: 1 days,
            pricePerSecond_: 38580246913 // Roughly calculates to 0.1 ether per 30 days
        });

        return subscription;
    }
}
