# Contributing to MT3K Mac Tools

Thanks for considering a contribution. This project is a native SwiftUI
macOS app built with Swift Package Manager — no Xcode project file, no
Electron, no external build system beyond `swift build`.

## Getting Started

```bash
git clone https://github.com/MondoBoricua/MT3K-Mac-Tools.git
cd MT3K-Mac-Tools
./setup.sh
```

`setup.sh` verifies macOS 14+, Xcode Command Line Tools, and Swift 6, then
runs `swift build`. See the [README](README.md) for the full command list and
architecture overview.

## Code Style

- **Swift 6 strict concurrency.** New code should compile cleanly under
  strict concurrency checking — prefer `Sendable` value types and actors
  over ad-hoc locking.
- **SwiftUI conventions.** Keep views presentational; state that needs to
  survive across views belongs in a coordinator (see
  `InstallCoordinator.swift`) or a dedicated state object, not scattered
  `@State` properties.
- Prefer `let` over `var`; use `struct` unless reference semantics are
  actually required.
- Keep files focused. If a view file is doing too much, split it the way
  the existing `Flow*.swift` files are split (state / hotkey / engine / UI).
- The codebase has a mix of Spanish and English comments (this started as a
  personal tool). Match whatever the file you're editing already uses —
  don't do a drive-by translation.

## Testing

```bash
swift test
```

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not
XCTest. Pure logic — catalog integrity, stats/battery parsers, Flow text
cleanup, and the Battery Guard decision function in `BatteryGuardCore` — is
covered and should stay covered. If you touch `GuardDecision.swift`, add or
update a test in `Tests/MT3KMacToolsTests/GuardDecisionTests.swift`; that
logic controls real hardware charge behavior and regressions there are not
cosmetic.

CI (`.github/workflows/ci.yml`) runs `swift build` + `swift test` on every
push and pull request.

## Adding an App to the Catalog

The easiest first contribution: add an entry to
`Sources/MT3KMacTools/Catalog.swift`. Pick the right `InstallMethod`
(`brewCask`, `brewFormula`, `brewTap`, `npm`, `dmg`, or `githubLatest`) and
add the app under the appropriate `CatalogCategory`. Existing entries in the
same category are the best reference for formatting.

Do not add install logic that accepts arbitrary user input — every
installable package must be a static entry in the catalog.

## Pull Requests

1. Fork the repo and create a feature branch.
2. Keep PRs focused — one feature or fix per PR.
3. Make sure `swift build` and `swift test` pass locally before opening the PR.
4. Describe *why* the change is needed, not just what changed.
5. Link any related issue.

## Reporting Issues

Use the issue templates under `.github/ISSUE_TEMPLATE/`. Bug reports should
include your macOS version, Mac architecture (Apple Silicon / Intel), and
the app version. Feature requests should describe the problem you're
solving, not just the solution.
