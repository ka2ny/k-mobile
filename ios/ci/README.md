# Build an IPA with Codemagic or GitHub Actions and Fastlane

## Codemagic: unsigned IPA

The root `codemagic.yaml` defines workflow **ios-unsigned** on Mac mini M2 with Xcode 27.0, Ruby 3.3.12 and locked Fastlane dependencies. Select `codex/native-ios-review` while the native app remains on PR #1. Builds are started manually or through the Codemagic API; there are no automatic triggers or store uploads. No Apple signing credentials or Codemagic API token belongs in the repository or workflow.

The workflow checks the SDK, PWA assets and portable contracts, runs native unit/UI tests, then archives and packages the unsigned device IPA. It stops on a failing check and is limited to 60 minutes. Download `KMobile-unsigned.ipa`, `build.json` and `Gemfile.lock` from the successful build's artifacts. Test results and archive logs are also retained. Build identity records the Codemagic commit and build ID; the app build number uses the project build counter plus one. Physical iPhone/board checks remain separate.

## GitHub Actions

The workflow is `.github/workflows/ios.yml`. Pushes to `main` and pull requests run PWA checks, portable Swift tests and native simulator tests, then package an **unsigned IPA**. Manual runs default to unsigned packaging too. Optional signed exports remain available on the default branch. It does not upload to TestFlight, App Store Connect or GitHub Releases.

The app is on the review branch in `ka2ny/k-mobile` (PR #1). The first GitHub run did not reach compilation. Codemagic subsequently passed the native checks and produced the unsigned IPA, version 0.1.0 (5), from commit `444811c9d4ef479d22c36240f06f617dd16a76ee`; see [build verification](../REVIEW.md). Firmware and OS repositories are not build targets.

## Default: pack now, sign later

No Apple account, team ID, P12, profile, secrets or `ios-signing` environment is required for **unsigned** builds. After tests, Fastlane archives a Release **arm64 iPhoneOS device** build with signing disabled. A separate packer validates the Mach-O platform and executable permissions, then writes `Payload/KMobile.app` into `KMobile-unsigned.ipa`. It preserves framework symlinks and Unix permissions and rejects links outside the app bundle.

Download **KMobile-unsigned-<run>-<attempt>** from the successful run's artifacts. It contains `KMobile-unsigned.ipa`, checksums/build identity and the dependency lockfile. Sign this IPA using your own signing tool afterward. No Apple export or upload happens in this mode. A working macOS CI runner is still needed to compile the application; changing packaging mode does not fix unavailable Actions execution.

On a Mac with Xcode 27+, from `ios/`:

```sh
bundle install
bundle exec fastlane ios unsigned_ipa
```

Output: `ios/build/ipa/KMobile-unsigned.ipa`. Optional `IOS_BUNDLE_ID`, `IOS_BUILD_NUMBER` and `IOS_MARKETING_VERSION` override bundle/version metadata before compilation.

## Optional signed export configuration

Create a GitHub environment named **ios-signing**. Add these secrets directly in GitHub settings; do not commit them or paste them into chat:

| Environment secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | Base64 Apple Distribution certificate **with its private key**, exported as password-protected `.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `IOS_PROFILE_BASE64` | Base64 distribution `.mobileprovision` for the app, team and chosen export type |

Add these variables:

| Variable | Where | Value |
| --- | --- | --- |
| `IOS_TEAM_ID` | `ios-signing` environment | Ten-character Apple Developer team ID |
| `IOS_BUNDLE_ID` | `ios-signing` environment | Registered explicit app ID; defaults to `app.khole.mobile` |
| `IOS_DEVELOPER_DIR` | Repository, optional | Installed Xcode developer directory; defaults to `/Applications/Xcode.app/Contents/Developer` |

Create/register the app ID and distribution profile in the Apple Developer account. The P12 identity must be valid and included in the profile. No Apple login, App Store API key, match repository or certificate-creation permission is needed by this export-only workflow. Existing Apple account signing assets are supplied by the owner.

For **ad-hoc**, use an Ad Hoc distribution profile containing the intended iPhone/iPad UDIDs. Only those registered devices can install the resulting IPA. For **app-store**, replace `IOS_PROFILE_BASE64` with an App Store Connect distribution profile before choosing that method. That IPA is for a later Apple distribution upload, not direct installation. The helper rejects a mismatched profile instead of silently changing methods.

On a Mac, encode each file without printing it into a terminal log:

```sh
base64 -i Distribution.p12 | pbcopy
base64 -i KMobile.mobileprovision | pbcopy
```

Paste each clipboard value into its respective GitHub secret. The temporary keychain password is generated on the runner; it needs no separate secret.

## Run and download

1. Open **Actions → iOS checks and IPA → Run workflow**, choose `unsigned` (default). Choose `ad-hoc` or `app-store` on the default branch only if you want CI to sign too.
2. Optionally override the marketing version, such as `0.1.0`. The build number is `<GitHub run number>.<run attempt>` so a retry produces a distinct build number.
3. Wait for the tests and device archive/packaging to finish.
4. Download artifact **KMobile-<method>-<run>-<attempt>**. It contains `KMobile-unsigned.ipa` in unsigned mode, or `KMobile.ipa` and generated symbol ZIPs for signed mode, `build.json` with the source commit/toolchain/checksums, and the resolved `Gemfile.lock`. Test results are a separate artifact. Retention is 14 days.

The profile's expiration, explicit app ID, team, distribution type and matching private-key identity are checked before archiving. Signing material is imported into a temporary keychain; the cleanup step always runs and restores the original search list. Only dedicated temporary files/profiles are removed. Use the configured ephemeral GitHub-hosted runner; these scripts are not designed for a shared persistent signing machine.

## Toolchain

The app requires iOS SDK 27+. GitHub documents the **xcode-27** hosted image as a preview, while the ordinary macOS image may default to an older Xcode. The workflow checks the selected SDK and finds an installed iOS 27+ iPhone simulator dynamically. A missing SDK/runtime is a build failure, not a skipped test. Configure `IOS_DEVELOPER_DIR` if an image has multiple Xcode installations. The exact Xcode version is recorded in the IPA artifact.

Ruby 3.3 and Bundler 2.5.22 use the committed Gemfile.lock. Frozen installs refuse dependency drift. Update the lockfile deliberately when changing Fastlane or its dependencies. GitHub Actions are pinned to commit hashes. The actionlint configuration adds the officially documented `xcode-27` preview label because the linter does not yet recognize it. This does not change the runner to self-hosted.

Useful local checks (no signing credentials required):

```sh
python3 -m unittest discover -s ios/ci -p 'test_*.py'
ruby -c ios/fastlane/Fastfile
actionlint .github/workflows/ios.yml
python3 ios/generate_project.py
git diff --exit-code -- ios/KMobile.xcodeproj
```

Fastlane lane commands on a configured Mac are `bundle exec fastlane ios test`, `bundle exec fastlane ios unsigned_ipa` and optional `bundle exec fastlane ios ipa`, run from `ios/`. The test lane needs `SIMULATOR_UDID`. The IPA lane uses the metadata produced by `signing.py install`; the workflow scopes certificate secrets to that installation step. Never run the signing helper on your personal keychain without adapting its ephemeral-runner assumptions.

A successful CI build validates compilation/tests and produces an IPA. Bluetooth bonding, Wi-Fi provisioning, board interoperability and locked-phone relay reliability still require physical-device checks in `../README.md`.

References: [Fastlane build_app](https://docs.fastlane.tools/actions/build_app/), [GitHub signing certificates](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications), [official Xcode 27 runner announcement](https://github.com/actions/runner-images/issues/14404).
