# Build an IPA with GitHub Actions and Fastlane

The workflow is `.github/workflows/ios.yml`. Pushes to `main` and pull requests run PWA checks, portable Swift tests and native simulator tests. A manual run on the repository's **default branch** runs those tests, then archives and exports a signed IPA through Fastlane. It does not upload to TestFlight, App Store Connect or GitHub Releases.

This repository still has no remote. The workflow files are prepared locally; no GitHub run or IPA has been produced here. Add this mobile repository to the intended GitHub repository when ready. Firmware and OS repositories are not build targets.

## GitHub configuration

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

1. Open **Actions → iOS checks and IPA → Run workflow**, select the default branch and choose `ad-hoc` or `app-store`.
2. Optionally override the marketing version, such as `0.1.0`. The build number is `<GitHub run number>.<run attempt>` so a retry produces a distinct build number.
3. Wait for the simulator tests and signed archive/export to finish.
4. Download artifact **KMobile-<method>-<run>-<attempt>**. It contains `KMobile.ipa`, generated symbol ZIPs, `build.json` with the source commit/toolchain/checksums, and the resolved `Gemfile.lock`. Test results are a separate artifact. Retention is 14 days.

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

Fastlane lane commands on a configured Mac are `bundle exec fastlane ios test` and `bundle exec fastlane ios ipa`, run from `ios/`. The test lane needs `SIMULATOR_UDID`. The IPA lane uses the metadata produced by `signing.py install`; the workflow scopes certificate secrets to that installation step. Never run the signing helper on your personal keychain without adapting its ephemeral-runner assumptions.

A successful CI build validates compilation/tests and produces an IPA. Bluetooth bonding, Wi-Fi provisioning, board interoperability and locked-phone relay reliability still require physical-device checks in `../README.md`.

References: [Fastlane build_app](https://docs.fastlane.tools/actions/build_app/), [GitHub signing certificates](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications), [official Xcode 27 runner announcement](https://github.com/actions/runner-images/issues/14404).
