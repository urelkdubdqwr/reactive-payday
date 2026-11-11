// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "omni/base/AbstractReactive.sol";
import { ISystemContract } from "omni/interfaces/ISystemContract.sol";

/// @title AutoSaver
/// @notice The reactive "brain" of the system, deployed on Reactive Lasna (5318007).
///
/// It subscribes to `PaydayVault.Deposit` on the origin chain. When a deposit
/// arrives, `react()` runs inside Reactive Network and applies the user's rule:
/// if the deposit is at least `threshold`, it asks the system contract to post a
/// callback to `SavingsLedger.sweep()` on the destination chain.
///
/// This is the whole product: one unconditional rule ("sweep the big ones into
/// savings"), evaluated on-chain, forever, with no off-chain watcher.
contract AutoSaver is AbstractReactive {
    /// @notice Destination chain for the sweep callback.
    uint256 public destinationChainId;
    /// @notice Chain that emits the deposits being watched.
    uint256 public immutable originChainId;
    /// @notice Contract whose `Deposit` events are watched.
    address public immutable originContract;
    /// @notice Event signature (topic0) being watched.
    uint256 public immutable depositTopic0;

    /// @notice Account holder; allowed to tune the rule.
    address public immutable owner;
    /// @notice Deposits strictly below this amount are ignored (in wei).
    uint256 public threshold;
    /// @notice Destination callback recipient on the destination chain.
    address public destination;

    /// @notice Gas forwarded to the destination callback.
    uint64 private constant CALLBACK_GAS_LIMIT = 300_000;

    event SweepRequested(
        address indexed payer,
        uint256 amount,
        uint256 destinationChainId,
        address destination
    );
    event RuleUpdated(uint256 threshold);
    event DestinationUpdated(uint256 destinationChainId, address destination);

    /// @param destinationChainId_ Chain receiving the callback (84532 = Base Sepolia).
    /// @param originChainId_      Chain emitting deposits (84532 = Base Sepolia).
    /// @param originContract_     `PaydayVault` address.
    /// @param depositTopic0_      `Deposit(address,uint256,uint256)` topic0.
    /// @param threshold_          Minimum deposit (wei) that triggers a sweep.
    /// @dev `payable` so the contract is funded at deploy time; it pays for the
    ///      reactive transactions it triggers.
    constructor(
        uint256 destinationChainId_,
        uint256 originChainId_,
        address originContract_,
        uint256 depositTopic0_,
        uint256 threshold_
    ) payable {
        destinationChainId = destinationChainId_;
        originChainId = originChainId_;
        originContract = originContract_;
        depositTopic0 = depositTopic0_;
        threshold = threshold_;
        owner = msg.sender;
        SYSTEM.subscribe(
            originChainId_,
            originContract_,
            depositTopic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Point the rule at the destination callback contract. Set after
    ///         `SavingsLedger` is deployed (it needs this contract's address,
    ///         so the reactive side breaks the cycle). Chain and address move
    ///         together so they can never drift out of sync.
    function setDestination(uint256 destinationChainId_, address destination_) external {
        require(msg.sender == owner, "AutoSaver: not owner");
        destinationChainId = destinationChainId_;
        destination = destination_;
        emit DestinationUpdated(destinationChainId_, destination_);
    }

    /// @notice Tune the rule without redeploying.
    function setThreshold(uint256 threshold_) external {
        require(msg.sender == owner, "AutoSaver: not owner");
        threshold = threshold_;
        emit RuleUpdated(threshold_);
    }

    /// @notice Reactive entry point. Called by the system contract for every
    ///         matching `Deposit` log on the origin chain.
    /// @param log_ The matching log record delivered by the system contract.
    function react(LogRecord calldata log_) external onlySystem {
        address payer = address(uint160(log_.topic1));
        uint256 amount = abi.decode(log_.data, (uint256));

        if (amount < threshold || destination == address(0)) {
            return;
        }

        // First slot is reserved: the network overwrites it with this contract's
        // address so the destination can authenticate the sender.
        bytes memory payload =
            abi.encodeWithSignature("sweep(address,address,uint256)", address(0), payer, amount);

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: destination,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );

        emit SweepRequested(payer, amount, destinationChainId, destination);
    }
}
