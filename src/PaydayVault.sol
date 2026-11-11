// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PaydayVault
/// @notice Origin-chain contract for the "Set It and Forget It" track.
///
/// Anyone (usually the account holder's payroll address) sends ETH here. Every
/// deposit emits a `Deposit` event. That event is the *only* trigger the whole
/// system needs: it is watched by the reactive contract `AutoSaver`, which then
/// decides — on-chain, in Solidity — whether the deposit should be swept into
/// the on-chain savings ledger. No bots, no cron, no keeper.
contract PaydayVault {
    /// @notice Emitted on every ETH deposit. `topic0` is the subscription key.
    event Deposit(address indexed sender, uint256 amount, uint256 balance);

    /// @notice Account holder; the only address allowed to take money back out.
    address public immutable owner;

    /// @notice Lifetime deposits observed by this contract.
    uint256 public totalDeposited;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Bare transfers are treated as deposits.
    receive() external payable {
        _deposit();
    }

    /// @notice Explicit deposit entry point (idiomatic; emits the same event).
    function deposit() external payable {
        _deposit();
    }

    /// @notice Withdraw funds. Owner-only — the automation never bears custody
    ///         of the principal, it only *observes* deposits.
    function withdraw(uint256 amount_) external {
        require(msg.sender == owner, "PaydayVault: not owner");
        (bool ok,) = payable(owner).call{ value: amount_ }("");
        require(ok, "PaydayVault: withdraw failed");
    }

    function _deposit() internal {
        totalDeposited += msg.value;
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
