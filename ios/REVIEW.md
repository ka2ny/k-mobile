# Native review — 11 November 2026

Review scope: native SwiftUI app, accessory/gateway lifecycle, motion, accessibility, request load and IPA pipeline. Existing PWA assets and their extraction baseline remain unchanged. The source review and subsequent theme/icon pass are backed by a successful Xcode archive, 25 native/UI tests and inspection of twelve light/dark simulator screenshots. Physical-device and live-backend qualification remains outstanding.

## Findings addressed

| Severity | Finding | Change |
| --- | --- | --- |
| High | Phone controls accepted full device permission even when hub permission/status was missing. | Require the phone identity and current paired, full-control, unpaused hub state. Dedicated companion identities retain their separate contract. Portable regression tests cover both. |
| High | A foreground/manual request could complete after suspension and restore live-looking state. | Suspension advances the response generation, clears hub/companion/Assistant state and releases refresh guards. Late responses cannot re-enable controls. |
| Medium | Pairing errors could race between a sheet and a global alert. A network request also disabled Cancel. | Sheet-local pairing error, cleared PIN after failure, cancellable pairing task, cancellation check before credential persistence. |
| Medium | A previous successful command receipt remained visible while a later action was pending/failed. | Clear the receipt before sending; scope it to the originating feature. Success feedback only follows an accepted server response. |
| Medium | Assistant manual refresh could overlap its polling task. Text edits during submission could be lost. | One Assistant read at a time; invalidate older reads on actions and disable the composer while a request is active. |
| Medium | A phone-link cooldown depended on unrelated view redraws to enable the button. | One cancellable deadline task updates cooldown state; no frame/timer loop. |
| Medium | Lock state and connection-switch controls did not consistently explain or respect shared busy state. | Surface desktop privacy pause; block host changes consistently during linking/actions; title matches Controls tab. |
| Medium | Immediate Bluetooth reconnect failures could loop without delay. | Reconnect backoff from one to 30 seconds; disconnect cancels the pending retry. No repeated scan. |
| Medium | Relay close paths could reenter the flushing loop. Socket reads were restricted to one tiny BLE packet. | Non-reentrant flush, up to 4 KiB bounded reads, credit-preserving BLE segmentation, at most 16 writes per UI-actor turn before yielding. Existing 64 KiB per-stream TCP-bound cap remains. |
| Low | First launch initialized accessory APIs even for computer-only users. | Activate the accessory session on explicit use or when restoring a saved accessory. |
| Low | Large text made control grids too dense; Home status confused unconfigured, connecting and offline. | Wider accessibility-size grid columns, wrapping status pill, distinct state labels and no continuously updating relative timestamp. |
| Low | Displayed Settings version ignored CI's version override. | Read the app bundle's exported marketing version. |

## Motion and interaction

- A finite 280 ms, eight-point page entrance on Home, Controls and Assistant. Reduce Motion removes the displacement and entrance animation.
- A finite 140 ms control press tint/border transition, with no scaling. Disabled controls remain visibly distinct; Increase Contrast strengthens their border. Reduce Motion removes the animated transition.
- A scoped 200 ms connection/receipt transition. No global animations on polling data and no perpetual symbol, glow, shimmer or background loops.
- Success haptics only after a confirmed desktop action receipt. Pairing/authorization selection and network requests are never optimistic success events.
- Native navigation/sheets retain their system transitions. Interactive keyboard dismissal is available in Assistant. Explanatory copy distinguishes physical k-chain pairing from the dedicated desktop listener.

## Performance work and limits

The foreground monitor fetches companion snapshots only on Controls. Healthy Home requests fall from three to two per cycle (roughly 36 to 24 per minute, excluding manual refreshes and request latency). k-chain and Activity use a 15-second interval instead of five seconds (roughly eight desktop requests/minute for Computer connections). Failed connections back off to 30 seconds. Assistant remains tab/scene scoped with coalesced reads.

Relay reads can batch up to 4096 bytes within the available credit, then split into the actual BLE write limit. This reduces opportunities for socket callback overhead when the network provides larger reads; it is not a measured throughput claim. At most six streams exist, each with one bounded read, at most 4 KiB pending phone-to-board data and 64 KiB queued board-to-TCP data. Flush work yields after 16 writes and cannot recurse through close/enqueue. Status observation updates only when the stream count changes.

Added XCUITest navigation checks, disconnected-state assertions, light/dark screenshot attachments and an application-launch metric. These run as part of the shared Xcode scheme and publish evidence with the test result bundle. They passed in Codemagic. The latest debug simulator launch metric averaged **11.390 seconds** across five recorded values, with **23.201% relative standard deviation** and no regression baseline. The earlier build measured 10.158 seconds with 15.771% relative standard deviation. These noisy CI samples do not establish a regression, improvement or device performance target. Release launch time, FPS, energy and BLE throughput still need physical-device profiling.

## Validation and release blockers

- Passed locally: 24 portable Swift tests (after the second pass below); 15 CI helper tests; seven extraction/design tests (12 JavaScript syntax checks, 47 cache references); Swift compiler syntax parsing; actionlint; project/plist/scheme consistency.
- GitHub PR #1: <https://github.com/ka2ny/k-mobile/pull/1>.
- Codemagic passed the Xcode 27.0 device archive and simulator suite: 22 native cases plus three UI tests, zero failures. The Mac also passed 24 portable Swift tests, 15 CI helper tests and seven extraction/design tests.
- Unsigned IPA packaging now needs no Apple signing configuration. Use `ci/README.md` for the default pack-now/sign-later path; configure signing only for optional signed exports.
- Inspected twelve actual screenshot attachments: Home, k-chain, Controls, Assistant and Activity in light/dark, empty pairing in light mode and Settings in dark mode. No clipped controls or misleading connected/success states were observed in these captures. Accent switching/persistence, iPad, landscape, Dynamic Type, VoiceOver, Increase Contrast, Reduce Motion and connected flows still need broader qualification.
- Physical iPhone/board bonding, wrong-code/reset/reconnect flows, TLS relay interoperability and locked/suspended background reliability remain unverified. Native SoftAP, streaming, files and voice remain outside the implemented native scope.

## Second pass before packaging — 11 November 2026

Source review of every Swift file, the project generator, plist and packaging path. At the time of this second pass, the GitHub run had not reached compilation. The later Codemagic verification below covers the Apple SDK build and disconnected simulator flows; physical accessory behavior remains unverified.

| Severity | Finding | Change |
| --- | --- | --- |
| High | Any transient inactive phase (system alert, the accessory picker itself, Control Centre, app switcher) ran `suspend()` and wiped connection state, so pages flashed to “offline”. | Only backgrounding invalidates live state. Inactive stops polling and keeps what is shown. |
| High | Cancelling Wi-Fi setup, or a board disconnect during it, surfaced a raw `CancellationError` string and overwrote the specific message already shown. | Cancellation is silent in authenticate/scan/join; the path that reset the transport owns the message. |
| High | Reconnecting the same board waited indefinitely for a disconnect callback. Cancelling a still-pending connection is not guaranteed to deliver one, leaving every later connect blocked. | Three-second bound on the wait, then reconnect. |
| High | A restored peripheral that was no longer connected was adopted and never reconnected; discovery was also issued before the central reported powered-on. | Adopt only connected/connecting peripherals; start discovery from the powered-on callback; drop stale peripherals after a Bluetooth reset. |
| Medium | A cancelled poll that had not unwound blocked the next tab’s first refresh, so Controls stayed disabled for up to five seconds and claimed “Agent status is unavailable”. | Latest refresh wins; loading and unavailable are separate states. |
| Medium | Agent decision failures raised a global alert underneath the review sheet, which then dismissed itself regardless of outcome. | The sheet stays open on failure and shows the error inline; it closes only after an accepted receipt. |
| Medium | White label on the dark-mode accent (`borderedProminent`) measured 2.1:1. | `QuietProminentStyle` uses the canvas colour for its label: 5.3:1 light, 8.7:1 dark. |
| Medium | Every key press disabled and restyled the whole control grid and inserted/removed rows beneath it. | Permission alone styles the keys; one fixed status row carries progress and receipts. |
| Medium | `accessoryRemoved` compared two optionals (nil == nil disconnected an unrelated session) and left the saved accessory behind. Forget did nothing, silently, when the session was not active. | Compare with the saved identifier and clear it; report why Forget cannot run. |
| Medium | Setup required `sec_patch_ver` in `proto-ver`; firmware built without that field would fail to decode. | Optional; absent or 0 accepted, anything else still refused. |
| Low | Addresses needed a typed `https://`; certificate codes needed exact case and dash. | Bare hosts assume HTTPS only (explicit non-HTTPS schemes still refused); codes are normalized. Portable tests added. |
| Low | Two competing calls to action on an empty Home; revoked tokens showed “Unauthorized (401)”; “1 active connections”; raw `full`/`view`; iPhone wording on iPad; grouped-grey lists beside warm pages; a launch screen in the system background rather than the canvas. | One action; a pair-again message; plural; labels; device-neutral copy; shared canvas on lists, forms and the launch screen; error haptic on a refused action. |
| Low | Release built per-file; delegate completion handlers omitted `@Sendable`; a test helper shadowed its own result; key paths to actor-isolated state. | Whole-module Release, exact delegate signatures, `makeClient()`, closures. |

First-build preparation: the pinned action commits and the `xcode-27` runner label were checked against GitHub and resolve; `Gemfile.lock` includes `arm64-darwin`. The evidence script no longer needs Python 3.11 (`hashlib.file_digest`), which would have failed after a successful archive on an older runner `python3`. Standard runpath settings were added to all three targets, and the pairing button’s decorative arrow is hidden from accessibility so the UI test finds “Pair securely” by its exact label.

Not changed, still open: connections other than the selected one cannot be forgotten without selecting them first; notices raised while Settings is open still use the root alert; `ITSAppUsesNonExemptEncryption` is not declared (an export-compliance statement for the owner to make); AccessorySetupKit with state restoration and `canSendWriteWithoutResponse` stalls need a physical board.

No IPA was packed during that source-review pass. The subsequent build below produced the IPA. No PR was merged and no firmware/OS source was modified.

## Initial verified unsigned build

- Source: `444811c9d4ef479d22c36240f06f617dd16a76ee`, incorporating app changes through `8018349` and the Codemagic setup fixes.
- Codemagic run: `6af4c9a0f5bbc9e274e0ac57`, completed successfully on 11 November 2026. Xcode 27.0 (27A266a), Mac mini M2, Ruby 3.3.12 and frozen Fastlane 2.241.2 dependencies.
- Artifact: `KMobile-unsigned.ipa`, 614,582 bytes, version **0.1.0 (5)**, bundle ID `app.khole.mobile`, minimum **iOS 27.0**.
- SHA-256: `9a7557416b42909b862f631a64cc529581b8f9c5b7dba1b36755b7fbd826ee07`. The downloaded file matches `build.json`; ZIP CRC, executable permissions, arm64 Mach-O and physical iOS platform were verified. No provisioning profile is embedded; external signing is required.
- The test result bundle, six original screenshot attachments, JUnit report, archive log and dependency lockfile are retained with the build artifacts. Tests and screenshots exercise disconnected app behavior and synthetic protocol/HTTP vectors, not real accessory pairing or desktop actions.
- This initial artifact predates the theme/icon pass. Its source and checksum remain recorded for comparison; the current build is below.

## Verified theme and icon rebuild

- Source: `6ccbb701513fd88903c4b4e03f18d1faa8323200`, including the graphite/sage theme, five accent choices, twelve outline glyphs, 140 ms tint-only press feedback and light/dark UI coverage.
- Codemagic run: `6af4ddb6973779a703f1ec0a`, completed successfully at 21:41 UTC on 11 November 2026 with Xcode 27.0 (27A266a), Mac mini M2, Ruby 3.3.12 and frozen Fastlane 2.241.2 dependencies.
- Artifact: `KMobile-unsigned.ipa`, **664,488 bytes**, version **0.1.0 (7)**, bundle ID `app.khole.mobile`, minimum **iOS 27.0**.
- SHA-256: `8efca07b0028aa7f4122b2779ac3595f53a0f48f42d06126a70b45c6916c9a4b`. The downloaded file matches `build.json`; ZIP CRC, executable permissions, arm64 Mach-O and physical iOS platform were verified. No provisioning profile is embedded; external signing is required.
- All 25 native/UI cases passed, including compiled glyph loading, adaptive color resolution, disconnected navigation, empty-pairing cancellation, dark navigation/Settings and launch measurement. The Mac also passed 24 portable Swift tests, 15 CI helper tests and seven extraction/design tests.
- Twelve original screenshot attachments were retained and inspected. Coverage and remaining display/device checks are recorded in [the cohesion pass](../docs/NATIVE-COHESION.md).
- The first theme run (`6af4d8a4eb9310aa963cc5d0`) compiled successfully but one UI test matched both “Add connection” buttons in the accessibility hierarchy. A stable identifier on the Connections sheet action fixed the selector; the full suite passed on rerun. That failed run produced no IPA.
- The test result bundle, screenshots, JUnit report, archive/test logs, dependency lockfile and checksum are retained with the artifact. Documentation updates after this successful run do not change its compiled application or workflow. Physical accessory/backend qualification remains open in [issue #2](https://github.com/ka2ny/k-mobile/issues/2).
