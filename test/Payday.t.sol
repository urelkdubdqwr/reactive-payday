// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "omni/interfaces/IReactive.sol";
import { ISystemContract } from "omni/interfaces/ISystemContract.sol";
import "../src/AutoSaver.sol";
import "../src/PaydayVault.sol";
import "../src/SavingsLedger.sol";

/// @dev Minimal stand-in for Reactive's system contract: the only caller allowed
///      to drive `react()`. It records the callback requests it receives so the
///      test can assert the loop locally.
contract MockSystem {
    uint256 public callbackCount;
    uint256 public lastChainId;
    address public lastRecipient;
    bytes public lastPayload;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory c) external {
        callbackCount++;
        lastChainId = c.chainId;
        lastRecipient = c.recipient;
        lastPayload = c.payload;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }
}

contract PaydayTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    address internal constant PROXY_ADDR = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    uint256 internal constant TOPIC0 =
        0x90890809c654f11d6e72a28fa60149770a0d11ec6c92319d6ceb2bb0a4ea1a15;

    PaydayVault internal vault;
    AutoSaver internal saver;
    MockSystem internal system; // code lives at SYSTEM_ADDR via vm.etch

    address internal payer = makeAddr("payer");

    function setUp() public {
        // Etch the mock at the hardcoded system address so `onlySystem` passes
        // when we prank as that address.
        MockSystem impl = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        system = MockSystem(SYSTEM_ADDR);

        vault = new PaydayVault();
        saver = new AutoSaver{ value: 1 ether }(84532, 84532, address(vault), TOPIC0, 0.001 ether);
        saver.setDestination(84532, PROXY_ADDR); // any non-zero recipient for the unit test
    }

    function _deliver(address depositor, uint256 amount) internal {
        IReactive.LogRecord memory rec;
        rec.chainId = 84532;
        rec.contractAddress = address(vault);
        rec.topic0 = TOPIC0;
        rec.topic1 = uint256(uint160(depositor));
        rec.data = abi.encode(amount, amount);
        vm.prank(SYSTEM_ADDR);
        saver.react(rec);
    }

    function test_belowThreshold_requestsNothing() public {
        _deliver(payer, 0.0005 ether);
        assertEq(system.callbackCount(), 0, "no sweep under threshold");
    }

    function test_aboveThreshold_requestsCallback() public {
        _deliver(payer, 0.01 ether);
        assertEq(system.callbackCount(), 1, "sweep requested at/above threshold");
        assertEq(system.lastChainId(), 84532);
        assertEq(system.lastRecipient(), PROXY_ADDR);

        // the payload targets `sweep(address,address,uint256)` with the reactive
        // address slot left as the placeholder the network overwrites.
        assertEq(
            system.lastPayload(),
            abi.encodeWithSignature("sweep(address,address,uint256)", address(0), payer, 0.01 ether)
        );
    }

    function test_react_rejectsNonSystem() public {
        IReactive.LogRecord memory rec;
        rec.topic1 = uint256(uint160(payer));
        rec.data = abi.encode(1 ether, 1 ether);
        vm.expectRevert();
        saver.react(rec);
    }

    function test_vaultEmitMatchesSubscription() public {
        vm.deal(payer, 1 ether);
        vm.prank(payer);
        vault.deposit{ value: 0.02 ether }();
        assertEq(vault.totalDeposited(), 0.02 ether);
        assertEq(
            keccak256("Deposit(address,uint256,uint256)"),
            bytes32(TOPIC0),
            "topic0 matches the Deposit event"
        );
    }
}
