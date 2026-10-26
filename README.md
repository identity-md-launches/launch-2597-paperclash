# PAPERCLASH

An ERC-20 token with a fixed supply, implemented in
[`src/PAPERCLASH.sol`](src/PAPERCLASH.sol) using the vendored OpenZeppelin
Contracts v5.0.2 ERC-20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract | `PAPERCLASH` |
| Token name | `PAPERCLASH` |
| Token symbol | `PAPERCLASH` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deployer (`msg.sender`) |

The constructor mints the whole supply once and emits one
`Transfer(address(0), deployer, supply)` event. `INITIAL_SUPPLY` is the named
constant for that amount. No other function can mint or burn.

## Behavior and assumptions

The brief specifies no special transfer rules, so this implementation uses
standard ERC-20 transfers and approvals. Transfers deliver the exact amount;
there are no taxes, fees, rebases, holding limits, or trading gates. Transfers
of zero tokens and transfers to oneself are supported. Transfers to the zero
address and approvals to a zero spender revert. Insufficient balances and
allowances revert with OpenZeppelin's ERC-6093 custom errors, preserving state.

`approve` replaces the caller's allowance for that spender. `transferFrom`
requires the caller's allowance, including when the caller is the holder or
deployer. A finite allowance decreases by the amount spent; `type(uint256).max`
is an unlimited allowance and is not decreased. A successful zero-value
`transferFrom` between valid addresses needs no positive allowance. Transfers
emit `Transfer`; explicit approvals emit `Approval`. In this library version,
spending an allowance does not emit `Approval`: integrations should query
`allowance` for its current value.

There is no owner, administrator, pausing, blacklisting, confiscation, rescue,
upgrade path, permit, or external initialization. Metadata and supply cannot
be changed after deployment. The token makes no external calls, invokes no
recipient callbacks, and uses no oracles, clocks, randomness, external contract
addresses, or chain-specific precompiles.

## Build and test

The project is at the repository root. Foundry and Solidity **0.8.26** must be
installed; every Solidity dependency is included as ordinary files under
`lib/`, with no submodules or dependency downloads needed to build or test.
See [DEPENDENCIES.md](DEPENDENCIES.md) for versions, provenance, and licenses.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x53f8c832708cb92b2cb340cf419ef346331fd95999468545ec5c466320c531b7 forge test
forge fmt --check
```

`foundry.toml` pins compiler 0.8.26, the Paris EVM target, optimizer enabled
with 200 runs, and `bytecode_hash = "none"`. Paris avoids requiring newer EVM
opcodes for this basic ERC-20. FFI and filesystem permissions are not enabled.

The tests cover metadata, the single mint event, direct and CREATE2 factory
deployment, immediate deployer versus transaction origin, exact distribution
and claim transfers, successful and failed transfers, zero and self transfers,
approval replacement/revocation, finite and unlimited allowances, failure
atomicity, and rejection of mint/burn/admin calls. Five fuzz tests each run
1,024 cases. The stateful invariant runs 256 sequences of 64 calls, comparing
balances and allowances to a separate ledger and checking conservation of the
whole supply. Tests are local, isolated, and require no RPC or environment
configuration; the shell seed above only selects Foundry's fuzz input stream.

## Deployment handoff

The assignment's launch target is Robinhood Chain, chain ID **4663**. Deploy
`src/PAPERCLASH.sol:PAPERCLASH` directly from its creation bytecode, with no
constructor arguments, no linked libraries, and no ETH. The compiled artifact
is `out/PAPERCLASH.sol/PAPERCLASH.json`. No deployment script or initialization
transaction is needed. A wrapper that creates this contract receives its
entire supply, so the launch factory must be the immediate deployer.

The IdentityMD launch factory receives all `10^27` base units before it makes
any distributions. Under the supplied launch policy it handles the 10% swarm
distribution, 80% pool allocation, and 10% remainder to
`0x863e974406764c8526b102c28a1e53906e032954`. These are factory responsibilities;
the token's constructor performs no allocations or calls to other contracts.

The supplied pool parameters are native ETH pairing, fee `12500` (1.25%),
tick spacing `60`, and initial market capitalization
`10000000000000000000` wei (10 ETH). The manifest's initial-price field is
`79228162514264337593543950336`; the launch deployer derives the actual opening
price from the economics and token address. These parameters do not affect
the token's bytecode. The separate manifest step writes `launch.json`; this
project intentionally supplies no manifest or application contracts.

The launch operator is responsible for source/bytecode verification, checking
the constructor mint event and balances, executing the factory distribution,
and validating pool initialization, seeding, and swaps through the protected
launch harness. The local distribution test checks exact token movements; it
does not execute Uniswap v4 or establish that the live launch infrastructure
has been validated. No transactions have been broadcast by this project.

## After launch

There are no owner settings, scheduled jobs, or administrative keys to manage.
Holders control their balances and approvals. Use allowances appropriate to
the intended spend, and revoke an existing allowance and wait for confirmation
before granting a replacement when avoiding concurrent spending matters.

Normal ETH transfers to the token revert. Tokens sent to the token contract
itself, unsupported recipient contracts, or inaccessible wallets cannot be
rescued by an administrator. Supply remains unchanged even if tokens become
inaccessible. Any ETH forced into the contract is likewise not recoverable.

The local source review checked mint reachability, access controls, arithmetic,
approval behavior, and the absence of external calls and upgrade mechanisms.
Foundry tests are validation of the included code, not an independent security
audit. Independent adversarial review and the protected launch integration
checks belong to the release process; Slither and Mythril were not run here.
