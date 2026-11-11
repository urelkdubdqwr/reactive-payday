#!/usr/bin/env bash
# Reactive Payday — one-command live demo of the full event → react → callback loop.
#
#   1. Deploy PaydayVault + SavingsLedger on Base Sepolia (origin & destination).
#   2. Deploy AutoSaver on Reactive Lasna, auto-subscribing to PaydayVault.Deposit.
#   3. Fund the automation contracts, wire the destination.
#   4. Deposit into PaydayVault — the trigger transaction.
#   5. Poll until the callback lands on SavingsLedger and print every tx hash.
#
# Env: PRIVATE_KEY | MNEMONIC_FILE | MNEMONIC_PHRASE, plus optional overrides.
# Usage: bash script/demo.sh [threshold_eth] [deposit_eth]

set -euo pipefail

THRESHOLD_ETH="${1:-0.0005}"
DEPOSIT_ETH="${2:-0.001}"

: "${RPC_ORIGIN:=${BASE_SEPOLIA_RPC:-https://sepolia.base.org}}"
: "${RPC_REACTIVE:=${REACTIVE_RPC:-https://lasna-rpc.rnk.dev/}}"
: "${CALLBACK_PROXY:=0x476F44b11F5C942c58f4c8E3d0300E5710743585}" # Base Sepolia proxy
ORIGIN_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_ORIGIN")
REACTIVE_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_REACTIVE")
DEPOSIT_TOPIC0=$(cast keccak "Deposit(address,uint256,uint256)")

PK_FLAG=()
if [[ -n "${PRIVATE_KEY:-}" ]]; then
    PK_FLAG=(--private-key "$PRIVATE_KEY")
elif [[ -n "${MNEMONIC_FILE:-}" ]]; then
    PK_FLAG=(--mnemonic-path "$MNEMONIC_FILE")
elif [[ -n "${MNEMONIC_PHRASE:-}" ]]; then
    PK_FLAG=(--mnemonic-path "$(mktemp)"); chmod 600 "${PK_FLAG[1]}"
    printf '%s\n' "$MNEMONIC_PHRASE" > "${PK_FLAG[1]}"
else
    echo "Set PRIVATE_KEY, MNEMONIC_FILE or MNEMONIC_PHRASE" >&2; exit 1
fi

AUTOSAVER_FUNDING="${AUTOSAVER_FUNDING_ETH:-0.05}"   # lREACT, covers network fees
LEDGER_FUNDING="${LEDGER_FUNDING_ETH:-0.0005}"       # ETH, covers callback billing
THRESHOLD_WEI=$(cast to-wei "$THRESHOLD_ETH" ether)

deploy() { # deploy <rpc> <legacy?> <path:name> [extra args...]
    local rpc="$1"; shift
    forge create --broadcast --json --rpc-url "$rpc" "${PK_FLAG[@]}" "$@"
}

echo "origin   $RPC_ORIGIN   (chain $ORIGIN_CHAIN_ID)"
echo "reactive $RPC_REACTIVE (chain $REACTIVE_CHAIN_ID)"
echo "threshold $THRESHOLD_ETH ETH    deposit $DEPOSIT_ETH ETH"
echo

# 1 + 2 ---------------------------------------------------------------- vault
VAULT=$(deploy "$RPC_ORIGIN" src/PaydayVault.sol:PaydayVault | jq -r .deployedTo)
echo "PaydayVault   (origin)   $VAULT"

# reactive brain on Lasna (funded via constructor; subscribes in its constructor)
AUTOSAVER=$(deploy "$RPC_REACTIVE" --legacy src/AutoSaver.sol:AutoSaver \
    --value "${AUTOSAVER_FUNDING}ether" \
    --constructor-args "$ORIGIN_CHAIN_ID" "$ORIGIN_CHAIN_ID" "$VAULT" \
        "$DEPOSIT_TOPIC0" "$THRESHOLD_WEI" | jq -r .deployedTo)
echo "AutoSaver     (reactive) $AUTOSAVER"

# destination callback contract, then break the deploy cycle
LEDGER=$(deploy "$RPC_ORIGIN" src/SavingsLedger.sol:SavingsLedger \
    --value "${LEDGER_FUNDING}ether" \
    --constructor-args "$CALLBACK_PROXY" "$AUTOSAVER" | jq -r .deployedTo)
echo "SavingsLedger (dest)     $LEDGER"
LEDGER_BLOCK=$(cast block-number --rpc-url "$RPC_ORIGIN")

SET_TX=$(cast send --legacy --json --rpc-url "$RPC_REACTIVE" "${PK_FLAG[@]}" \
    "$AUTOSAVER" "setDestination(uint256,address)" "$ORIGIN_CHAIN_ID" "$LEDGER" | jq -r .transactionHash)
echo "setDestination tx        $SET_TX"

# 4 ------------------------------------------------------------------ trigger
DEPOSIT_TX=$(cast send --json --rpc-url "$RPC_ORIGIN" "${PK_FLAG[@]}" \
    "$VAULT" --value "${DEPOSIT_ETH}ether" | jq -r .transactionHash)
echo "deposit tx (origin)      $DEPOSIT_TX"

# 5 -------------------------------------------------- wait for the callback
echo
echo "waiting for the callback on SavingsLedger..."
SWEEP_TX=""
for _ in $(seq 1 120); do
    out=$(cast logs --address "$LEDGER" --from-block "$LEDGER_BLOCK" --to-block latest \
        --rpc-url "$RPC_ORIGIN" --json 2>/dev/null || echo '[]')
    SWEEP_TX=$(echo "$out" | jq -r 'if length>0 then .[-1].transactionHash else empty end')
    [[ -n "$SWEEP_TX" ]] && break
    sleep 5
done

echo
echo "=================== TX HASHES ==================="
echo "deposit / trigger   $DEPOSIT_TX"
echo "setDestination      $SET_TX"
echo "callback (dest)     ${SWEEP_TX:-PENDING — rerun the watcher below}"
echo "================================================="
echo "vault=$VAULT autosaver=$AUTOSAVER ledger=$LEDGER"
echo "total swept: $(cast call "$LEDGER" 'totalSwept()(uint256)' --rpc-url "$RPC_ORIGIN")"

if [[ -n "${HASHES_OUT:-}" ]]; then
    mkdir -p "$(dirname "$HASHES_OUT")"
    {
        echo "vault=$VAULT"; echo "autosaver=$AUTOSAVER"; echo "ledger=$LEDGER"
        echo "deposit_tx=$DEPOSIT_TX"; echo "set_destination_tx=$SET_TX"
        echo "callback_tx=${SWEEP_TX:-pending}"
    } >> "$HASHES_OUT"
    echo "appended to $HASHES_OUT"
fi
