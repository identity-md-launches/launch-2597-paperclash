# Vendored dependencies

All dependency source files are stored directly in `lib/`. No package manager,
Git submodule, environment variable, or network access is required by the
build. Foundry and the Solidity 0.8.26 compiler remain toolchain prerequisites.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | `v5.0.2` | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors | MIT |
| forge-std | `v1.9.7` | Complete `src/` directory, used only by tests | MIT / Apache-2.0 |

OpenZeppelin source:
<https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2>

Downloaded archive:
<https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2>

Archive SHA-256:
`18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`

forge-std source:
<https://github.com/foundry-rs/forge-std/tree/v1.9.7>

Downloaded archive:
<https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7>

Archive SHA-256:
`45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Selected source files are unmodified from those archives. Licenses are included
at `lib/openzeppelin-contracts/LICENSE`, `lib/forge-std/LICENSE-MIT`, and
`lib/forge-std/LICENSE-APACHE`. `DEPENDENCIES.sha256` records the hash of every
vendored file. Check the local copies with:

```sh
sha256sum --check DEPENDENCIES.sha256
```

The minimal OpenZeppelin subset contains all transitive dependencies of
`ERC20.sol`. No other OpenZeppelin modules are part of the deployed token.
The library's internal mint and burn helpers are not exposed by PAPERCLASH.
