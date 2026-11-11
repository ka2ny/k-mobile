# k-hole for iOS

Native SwiftUI app for your computer and physical k-chain. Includes Apple accessory selection, BLE Wi-Fi setup, Bluetooth byte relaying and desktop phone association. This is an implementation candidate awaiting full Xcode and physical-device qualification, not a verified shipping build. No WebView, external Swift packages, bundled credentials or simulated successful services are included. The original PWA remains unchanged in `../public/`.

## Review, motion and performance

[Review findings and validation limits](REVIEW.md) record the fixes, event-driven motion, polling/relay changes and outstanding device measurements. GitHub PR #1 is open; the first CI attempt did not reach compilation.

## GitHub CI / IPA packaging

[GitHub Actions + Fastlane setup](ci/README.md) covers simulator checks, distribution signing and downloadable IPA artifacts. The workflow supports Ad Hoc and App Store exports without publishing to Apple. A remote run was attempted but did not reach compilation.

## Open and run

Use a Mac with Xcode 27.1 / Swift 6.4 and an iOS 27 simulator or device. The project uses Swift 6 language mode with complete concurrency checking and targets iPhone/iPad.

1. Open `KMobile.xcodeproj`, choose the shared `KMobile` scheme, and select your development team. Change `app.khole.mobile` if that identifier is unavailable.
2. In Connections, add the actual HTTPS computer address and desktop PIN. The optional **k-chain desktop service** connection uses the dedicated companion listener and its certificate code. These are desktop connections, separate from physical accessory pairing.
3. In the **k-chain** tab, choose **Pair your k-chain**. On the board, open Settings → Bluetooth → Pair a phone. Confirm matching numbers on both devices. Subscription alone is never labelled a successful bond; activity appears when the board opens relay streams.
4. For board Wi-Fi, open the board's setup screen and **Set up board Wi-Fi** in the app. Verify its six-digit Wi-Fi code, select/enter a network and wait for the board's connected response. Desktop enrollment remains on the board.
5. To associate this phone through the desktop, select an online **Computer** connection, open **Link phone on your computer** and redeem the code from the board's **Phone** screen. This requires `companion_link: 1` and grants no control. Approve control separately on the desktop if desired.

No signing identity or distribution settings are embedded. Saved desktop connections refresh while foregrounded. An enabled saved Bluetooth relay restores using CoreBluetooth; disconnecting disables automatic reconnection. No Bluetooth scan runs continuously.

## Validation commands

Portable contracts, on a machine with Swift 6 or newer:

```sh
swift test --package-path ios
```

Full native tests, from the repository root on a Mac:

```sh
xcodebuild -project ios/KMobile.xcodeproj -scheme KMobile -showdestinations
xcodebuild -project ios/KMobile.xcodeproj -scheme KMobile \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=NO test
```

Regenerate the project with `python3 ios/generate_project.py` after adding/removing Swift files. The portable package compiles the same `KMobile/Protocol` sources as the app. The Xcode target separately includes Apple-framework/HTTP tests in `KMobileTests`. XcodeGen/CocoaPods are not required.

## Implemented scope

| Area | Behavior |
| --- | --- |
| Native shell | Home, k-chain, Controls, Assistant, Activity; system navigation/type; adaptive light/dark surfaces; settings/connections sheets |
| Desktop connections | Saved HTTPS origins; phone/companion identities; PIN exchange; Keychain credentials; host switching; local forgetting |
| Home and controls | Authenticated device status; full-control request; media, volume, focus, confirmed lock; server receipts |
| Agent decisions | Current decision summary, explicit review/confirmation, allow/deny with exact IDs, stale-response handling |
| Assistant | Current task, start text task, stop, open desktop Assistant for approval/prompts |
| Accessory selection | AccessorySetupKit with published service IDs; CoreBluetooth reconnect/restoration and GATT rediscovery |
| Board Wi-Fi | Security 1 PoP, X25519/SHA256/AES-CTR, descriptor-based endpoints, scan/manual SSID, configure/apply/status, failed-network reset |
| Bluetooth relay | Six bounded raw TCP streams, credit and Bluetooth backpressure, ordered targets, cancellation and stale-callback guards; board owns TLS/authentication |
| Desktop phone link | Capability-gated S6 link/list/unlink, empty grants, HTTP Retry-After cooldown; no automatic code retries |
| Activity | Last 60 desktop action responses in memory; not an OS audit log |
| Existing workspace | Remote, Beam/Files and full Agents open the external browser with separate browser pairing |

Native WebRTC streaming, file transfer/share extensions, Assistant attachments/history/executor selection, voice, push, widgets, native SoftAP/USB setup, SSID hints and firmware updates are not implemented. SoftAP/USB fallback is explained in the board setup screen. Optional SSID hints are omitted; no location or Wi-Fi-information entitlement is requested. Bluetooth relay needs actual network reachability to the board's advertised desktop targets; [OS #46](https://github.com/ka2ny/k-flow-os/issues/46) tracks away-from-home support.

## Security and lifecycle

- Computer connections use system HTTPS trust. Dedicated companion enrollment checks the desktop's `XXXX-XXXX` code (base32 of the first five SHA-256 certificate bytes), then stores the full certificate digest with its token in Keychain. Certificate changes fail closed. Board-side certificate words are a different enrollment flow.
- Tokens use device-only Keychain accessibility while unlocked. Preferences store connection metadata and the relay peripheral ID/enabled flag, never tokens, setup codes or Wi-Fi passwords. Transient Wi-Fi secrets clear after use, cancellation and backgrounding.
- Each desktop connection uses an ephemeral URLSession. In-memory HttpOnly cookies preserve gateway semantics; redirects and API caching are disabled. No tokens/cookies are passed to browser links or to the board.
- Desktop controls require authenticated permissions. Pairing, control requests, Bluetooth authorization and S6 association do not imply control approval. Unsupported link versions/grants fail closed.
- Wi-Fi credentials follow successful Security 1 device-proof verification. One CTR context spans handshake and both directions. Interruptions terminate the session; no insecure fallback or automatic PoP retries. Only a board-reported connected state with an address means success.
- Foreground desktop polling runs every five seconds on interactive tabs, every fifteen seconds on idle tabs, and backs off to thirty seconds on connection failures; Assistant polls every three seconds while selected. Backgrounding invalidates live controls and stops Wi-Fi setup. Relay callbacks and TCP buffers are bounded and connection-scoped.
- Bluetooth background mode and restoration are configured, but sustained background TCP is not guaranteed by that configuration. The UI recommends keeping the app open. Locked/suspended/restored iPhone behavior requires measurement before any background-reliability claim.
- Actions are not automatically retried. A lost response may follow actual execution; errors ask the user to check before retrying. Local desktop forgetting does not revoke access on the computer. Accessory forgetting and S6 unlinking are independent.

## Evidence and release gates

Latest firmware/OS contracts, ticket status and exact source hashes are in [provenance.json](provenance.json) and the [accessory integration audit](../docs/NATIVE-ACCESSORY.md). No firmware or OS files were modified. Source implementation is not evidence of deployment: #45 says the new desktop link contract is built/tested but not shipped. The app checks capability at runtime.

Executed in this Linux workspace on 2026-11-11:

- Portable Swift 6.2.4 package: 22 protocol and gateway contract tests compiled and passed. Includes malformed/oversized messages, unsafe destinations, credit limits, known protobuf bytes, connected-state requirements, capability/grant validation and unsafe origins.
- Swift compiler frontend parsed every app and native-test source. This is syntax validation, not Apple SDK type-checking.
- Generated Xcode project, source/resource references, plist, scheme and icon metadata checked.
- `npm test`: four extraction tests passed, including 12 JavaScript syntax checks and 47 cache references. Original PWA hashes remain unchanged.

Not executed: full iOS build/tests, Security 1 vector against CommonCrypto, simulator/UI/accessibility checks, physical board/iPhone, live gateway or App Store qualification. The Xcode tests include a synthetic interoperability vector independently generated with Python cryptography, certificate vectors, permission checks, HTTP/cache behavior and Retry-After.

Before release, record results for:

- Xcode build/test and device signing; iPhone/iPad, light/dark, large text, VoiceOver and landscape.
- System picker permission/cancel/remove; SMP accept/reject; bond revocation; switching setup/relay services on the same board; board reboot and repeated setup without reboot.
- Correct/wrong PoP, the board's lockout, incorrect Wi-Fi password, unknown SSID, reset-before-retry, timeout, cancellation and app suspension. Verify that no failure reports success.
- Relay credit exhaustion, six simultaneous streams, TCP failure, board CLOSE during dialing, cellular/VPN changes, local-network denial, locked screen, OS suspension/termination and state restoration. Observe throughput, battery and background continuity on a physical phone.
- Desktop capability absent/present/future, unknown/expired/used codes, privacy stop, 429 cooldown, unlink/revocation, changed certificates, stale agent decisions and host changes during requests.

## Design and sources

Warm neutral surfaces, violet accents and native system controls provide a restrained visual foundation. Finite page entrances, control press feedback and confirmed-action haptics respect accessibility settings. No decorative bitmap assets or perpetual animations are used. The unchanged k-hole SVG mark is rasterized at 1024 × 1024 for the app icon; hashes and the original notice are preserved. Native text uses system fonts and SF Symbols; PWA fonts/notices are intact.

Guidance was consulted from [Swift Agent Skills](https://github.com/twostraws/swift-agent-skills) and [SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill/blob/main/swiftui-pro/SKILL.md). No skills were globally installed. Apple framework documentation and ESP-IDF v5.5.5 protocol definitions informed the independent implementation; no third-party framework is bundled.
