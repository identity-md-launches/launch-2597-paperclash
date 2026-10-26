// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PAPERCLASH} from "../src/PAPERCLASH.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

/// @dev Stateless properties over arbitrary callers and amounts, focused on the paths that must fail.
contract PAPERCLASHAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    PAPERCLASH internal token;

    function setUp() public {
        token = new PAPERCLASH();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotPullWithoutAllowance(address caller, address to, uint256 amount) public {
        vm.assume(caller != address(this) && to != address(0));
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, 0, amount));
        vm.prank(caller);
        token.transferFrom(address(this), to, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_emptyAccountCannotSendPositiveAmount(address from, address to, uint256 amount) public {
        vm.assume(from != address(this) && from != address(0) && to != address(0));
        amount = bound(amount, 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, 0, amount));
        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(from), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactValueForAnyPair(address owner, address spender, uint256 first, uint256 second)
        public
    {
        vm.assume(owner != address(0) && spender != address(0));
        vm.startPrank(owner);
        assertTrue(token.approve(spender, first));
        assertEq(token.allowance(owner, spender), first);
        assertTrue(token.approve(spender, second));
        vm.stopPrank();
        assertEq(token.allowance(owner, spender), second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromOverBalanceRevertsEvenWithInfiniteAllowance(uint256 held, uint256 amount) public {
        address holder = makeAddr("holder");
        address spender = makeAddr("spender");
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, type(uint256).max);
        token.transfer(holder, held);
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, held, amount));
        vm.prank(spender);
        token.transferFrom(holder, spender, amount);
        assertEq(token.balanceOf(holder), held);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_chainedTransfersConserveSupply(uint256 a, uint256 b, uint256 c) public {
        address x = makeAddr("x");
        address y = makeAddr("y");
        address z = makeAddr("z");
        a = bound(a, 0, SUPPLY);
        token.transfer(x, a);
        b = bound(b, 0, a);
        vm.prank(x);
        token.transfer(y, b);
        c = bound(c, 0, b);
        vm.prank(y);
        token.transfer(z, c);
        assertEq(token.balanceOf(address(this)), SUPPLY - a);
        assertEq(token.balanceOf(x), a - b);
        assertEq(token.balanceOf(y), b - c);
        assertEq(token.balanceOf(z), c);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(x) + token.balanceOf(y) + token.balanceOf(z), SUPPLY);
    }

    function test_oneWeiEdges() public {
        address holder = makeAddr("holder");
        token.transfer(holder, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(holder);
        token.transfer(address(this), 2);
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromConsumingAllowanceEmitsNoApproval() public {
        address spender = makeAddr("spender");
        address to = makeAddr("to");
        token.approve(spender, 10);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), to, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(token.allowance(address(this), spender), 6);
    }

    function test_maxMinusOneAllowanceIsFiniteAndDecrements() public {
        address spender = makeAddr("spender");
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), spender, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_transferFromZeroOwnerReverts() public {
        // No approval can exist for the zero address, so the allowance check is reached first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(0), address(this), 1);
        // A zero-amount pull passes the allowance comparison, but rewriting the zero owner's allowance reverts.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), address(this), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAddressCannotApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(address(this), 1);
    }

    function test_redeployedTokensAreIndependent() public {
        TokenFactory factory = new TokenFactory();
        PAPERCLASH first = factory.deploy(bytes32(uint256(1)));
        PAPERCLASH second = factory.deploy(bytes32(uint256(2)));
        assertTrue(address(first) != address(second));
        factory.move(first, address(this), SUPPLY);
        assertEq(first.balanceOf(address(factory)), 0);
        assertEq(second.balanceOf(address(factory)), SUPPLY);
        assertEq(second.balanceOf(address(this)), 0);
        vm.expectRevert();
        factory.deploy(bytes32(uint256(1)));
    }
}

/// @dev Drives successful and must-fail calls in random order. Every failing attempt is checked to
/// revert and to leave balances, allowances and supply exactly as they were.
contract AdversarialHandler is Test {
    PAPERCLASH internal immutable token;
    address[6] internal actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public moved;
    uint256 public failedAttempts;

    constructor(PAPERCLASH token_, address[6] memory actors_, uint256 supply_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = supply_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        moved += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = bound(amount, 0, 2 * token.totalSupply());
        if (amount == 2 * token.totalSupply()) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        moved += amount;
    }

    function overspendTransfer(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = expectedBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        vm.prank(from);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(ok, "transfer above balance succeeded");
        failedAttempts++;
    }

    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)));
        assertFalse(ok, "transferFrom above allowance succeeded");
        failedAttempts++;
    }

    function overspendBalanceWithAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance[owner];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)));
        assertFalse(ok, "transferFrom above balance succeeded");
        failedAttempts++;
    }

    function sendToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        assertFalse(ok, "transfer to the zero address succeeded");
        failedAttempts++;
    }

    function approveZero(uint256 ownerSeed, uint256 amount) external {
        vm.prank(_actor(ownerSeed));
        (bool ok,) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(ok, "approval of the zero address succeeded");
        failedAttempts++;
    }

    function callPrivileged(uint256 callerSeed, uint256 which, uint256 amount) external {
        bytes[6] memory attempts = [
            abi.encodeWithSignature("mint(address,uint256)", _actor(callerSeed), amount),
            abi.encodeWithSignature("burn(uint256)", amount),
            abi.encodeWithSignature("burnFrom(address,uint256)", actors[0], amount),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", actors[0]),
            abi.encodeWithSignature("seize(address)", actors[0])
        ];
        vm.prank(_actor(callerSeed));
        (bool ok,) = address(token).call(attempts[which % attempts.length]);
        assertFalse(ok, "privileged entrypoint reachable");
        failedAttempts++;
    }
}

contract PAPERCLASHAdversarialInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PAPERCLASH internal token;
    TokenFactory internal factory;
    AdversarialHandler internal handler;
    address[6] internal actors;

    function setUp() public {
        // Deployed through a factory as the launch does; the factory is actor 0 and starts with everything.
        factory = new TokenFactory();
        token = factory.deploy(keccak256("adversarial invariant"));
        actors[0] = address(factory);
        actors[1] = makeAddr("distributor");
        actors[2] = makeAddr("poolManager");
        actors[3] = makeAddr("trader-a");
        actors[4] = makeAddr("trader-b");
        actors[5] = address(token);
        handler = new AdversarialHandler(token, actors, SUPPLY);
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = AdversarialHandler.transfer.selector;
        selectors[1] = AdversarialHandler.approve.selector;
        selectors[2] = AdversarialHandler.transferFrom.selector;
        selectors[3] = AdversarialHandler.overspendTransfer.selector;
        selectors[4] = AdversarialHandler.overspendAllowance.selector;
        selectors[5] = AdversarialHandler.overspendBalanceWithAllowance.selector;
        selectors[6] = AdversarialHandler.sendToZero.selector;
        selectors[7] = AdversarialHandler.approveZero.selector;
        selectors[8] = AdversarialHandler.callPrivileged.selector;
        selectors[9] = AdversarialHandler.transfer.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_ledgerMatchesAfterMixedSuccessAndFailure() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(address(token).balance, 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "PAPERCLASH");
        assertEq(token.symbol(), "PAPERCLASH");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
