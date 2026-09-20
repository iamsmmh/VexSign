# Contributing

VexSign is a modern on-device iOS signer and installer built with SwiftUI and open source components.

Any contributions should follow the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Rules

- **No usage of any exploits of any kind.**
- **No contributions related to retrieving any signing certificates owned by companies.**
- **Modifying any hardcoded links should be discussed before changing.**
- **If you're planning on making a large contribution, please [make an issue](https://github.com/iamsmmh/VexSign/issues) beforehand.**
- **Your contributions should be licensed appropriately.**
  - VexSign: GPLv3
  - AltSourceKit / NimbleKit / Zsign / IDeviceKitten: MIT
  - ElleKit: BSD-3-Clause
- **Typo contributions are okay**, just make sure they are appropriate.
- **Code cleaning contributions are okay.**

## Building from source

#### Requirements

- Xcode 16.0+ (synchronized groups, `objectVersion 77`)
- Swift 6.0
- iOS 16.0 deployment target

1. Clone the repository with submodules:
    ```sh
    git clone https://github.com/iamsmmh/VexSign --recursive
    ```
    - `Zsign` and `IDeviceKitten` are submodules — `--recursive` is required.

2. Fetch the local-server SSL pack:
    ```sh
    cd VexSign && make deps
    ```

3. Open with Xcode:
    ```sh
    open VexSign.xcworkspace
    ```

#### Signing for development

Set your own team / enable automatic signing in Xcode's target settings, or use the unsigned CLI path (`make`, which builds with `CODE_SIGNING_ALLOWED=NO`).

#### Localizations

- Localizations live in `VexSign/Resources/Localizable.xcstrings` (String Catalog). You need Xcode 15+.
- **Do NOT edit the catalog by hand** — use Xcode's String Catalog editor.
- After localizing, please have another native speaker review your work.

#### Making a pull request

- Keep contributions in their own branch, not `main`.
- Don't be afraid of reviewers requesting changes.
- Every PR is compiled by the `Release` workflow; the resulting unsigned IPA is attached to the run as an artifact if you want to try it on a device.
- PRs also get a one-minute **Quick check** (syntax, duplicates, broken resources), a Debug **Build check** and automatic **SwiftLint** fixes. Features from related projects are collected by the **Upstream feature radar**; see [docs/AUTOMATION.md](docs/AUTOMATION.md).

## Releasing

Releases are cut by pushing a tag (`vX.Y.Z`, matching `MARKETING_VERSION`); CI builds, verifies and publishes automatically. To try a build from any branch without publishing, run the `Release` workflow manually with `build_only` left ticked. See [docs/RELEASING.md](docs/RELEASING.md).

## Contributing to Zsign

Zsign is maintained upstream at [claration/Zsign-Package](https://github.com/claration/Zsign-Package/tree/package).
