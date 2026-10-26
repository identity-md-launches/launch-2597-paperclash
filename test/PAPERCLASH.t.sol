// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PAPERCLASH} from "../src/PAPERCLASH.sol";
import {TokenFactory, RejectingRecipient} from "./helpers/TokenFactory.sol";

contract PAPERCLASHTest is Test {
    // Literal independent of the implementation's supply expression.
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    PAPERCLASH internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new PAPERCLASH();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "PAPERCLASH");
        assertEq(token.symbol(), "PAPERCLASH");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        PAPERCLASH deployed = new PAPERCLASH();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_constructorMintsToImmediateDeployer() public {
        vm.prank(alice, bob);
        PAPERCLASH deployed = new PAPERCLASH();
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_factoryCreate2ReceivesWholeSupply() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("local factory deployment");
        address predicted = vm.computeCreate2Address(salt, keccak256(type(PAPERCLASH).creationCode), address(factory));
        vm.prank(alice, alice);
        PAPERCLASH deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
    }

    function test_factoryDistributionClaimsAndPoolTransfersArriveWhole() public {
        TokenFactory factory = new TokenFactory();
        PAPERCLASH deployed = factory.deploy(keccak256("local launch flow"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("poolManager");
        address remainder = makeAddr("remainder");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;

        assertTrue(factory.move(deployed, distributor, swarm));
        assertTrue(factory.move(deployed, poolManager, pool));
        assertTrue(factory.move(deployed, remainder, SUPPLY - swarm - pool));
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), swarm);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarm));
        assertEq(deployed.balanceOf(alice), swarm);
        assertEq(deployed.balanceOf(distributor), 0);

        // Exercise both directions of the token leg; this is not an AMM simulation.
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, 123 ether));
        assertEq(deployed.balanceOf(bob), 123 ether);
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, 123 ether));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 125 ether);
        assertTrue(token.transfer(alice, 125 ether));
        assertEq(token.balanceOf(alice), 125 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 125 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractDoesNotCallRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferExceedingBalanceRevertsWithoutChanges() public {
        token.transfer(alice, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        vm.prank(alice);
        token.transfer(bob, 6 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_approveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertTrue(token.approve(spender, 25 ether));
        assertEq(token.allowance(address(this), spender), 25 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 10);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_revokedAllowanceCannotBeSpent() public {
        token.approve(spender, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromConsumesFiniteAllowance() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromPreservesInfiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1 ether));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    function test_transferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 60));
        assertEq(token.allowance(address(this), spender), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoPositiveAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromInsufficientAllowanceReverts() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_allowanceIsSpecificToSpender() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_deployerCannotSpendUnapprovedHolderBalance() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(alice, 5);
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromZeroRecipientRestoresAllowance() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 6);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntrypoints() public {
        token.transfer(alice, 100);
        bytes[] memory attempts = new bytes[](17);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("burn(uint256)", 1);
        attempts[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        attempts[5] = abi.encodeWithSignature("pause()");
        attempts[6] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[7] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[8] = abi.encodeWithSignature("seize(address)", alice);
        attempts[9] = abi.encodeWithSignature("initialize(address)", bob);
        attempts[10] = abi.encodeWithSignature("upgradeTo(address)", bob);
        attempts[11] = abi.encodeWithSignature("transferOwnership(address)", bob);
        attempts[12] = abi.encodeWithSignature("setMinter(address)", bob);
        attempts[13] = abi.encodeWithSignature("owner()");
        attempts[14] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[15] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        attempts[16] = abi.encodeWithSignature("_mint(address,uint256)", bob, SUPPLY);
        for (uint256 i; i < attempts.length; ++i) {
            (bool deployerSuccess,) = address(token).call(attempts[i]);
            assertFalse(deployerSuccess, "deployer reached an unsupported function");
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(attempts[i]);
            assertFalse(strangerSuccess, "stranger reached an unsupported function");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_plainEthAndUnknownCallsRevert() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool sent,) = address(token).call{value: 1 ether}("");
        assertFalse(sent);
        assertEq(address(token).balance, 0);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transfersAboveSupplyRevert(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_delegatedTransferConsumesOnlySpentAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransferOverAllowanceReverts(uint256 approved) public {
        approved = bound(approved, 0, SUPPLY - 1);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, approved + 1);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_infiniteApprovalSurvivesTransfer(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice), SUPPLY);
    }
}
