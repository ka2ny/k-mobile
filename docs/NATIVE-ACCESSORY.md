# Native k-chain accessory integration

## Scope and reviewed updates

The mobile repository is local and unpublished. Firmware and OS code, configuration, branches and deployments are unchanged. Backend work remains ticket-only.

Reviewed on 2026-11-11:

| Contract | Source snapshot | Tracking |
| --- | --- | --- |
| BLE Wi-Fi provisioning | k-chain-os `board-pass`, `6147f46b1da23b807af18c539367c52e2150b118`, `k-moon/docs/phone-setup.md` | [#4](https://github.com/ka2ny/k-chain-os/issues/4) |
| Bluetooth byte relay v0 | Same firmware snapshot, `k-moon/docs/phone-link.md` | [#5](https://github.com/ka2ny/k-chain-os/issues/5) |
| Desktop phone association v1 | k-flow-os `main`, `444ebf11eede6163addded8dd76f633a400de659`, `remote/web/khole-web` | [#45](https://github.com/ka2ny/k-flow-os/issues/45) |
| Away-from-home companion reachability | Existing OS dependency, not assumed available | [#46](https://github.com/ka2ny/k-flow-os/issues/46) |

The earlier main-only audit was incomplete. Active firmware implements provisioning, repeatable BLE setup and persistent phone bonds. The latest OS source implements `phone.code` redemption; #45 describes it as built/tested but not shipped. The app therefore checks `companion_link == 1` at runtime. Historical inspections remain in `ios/provenance.json` and are not the current capability assessment.

## Mobile implementation

The native **k-chain** tab separates these flows:

1. **System accessory selection and Bluetooth relay.** AccessorySetupKit uses the published name prefix and service IDs. CoreBluetooth retrieves the selected peripheral without continuous scanning, rediscovers services on reconnect, and restores saved relay connections. Subscribing is not reported as proof of a successful bond. The user confirms the same SMP numbers on the board and iPhone. Raw TCP sockets carry opaque board TLS bytes; phone credentials never become board credentials.
2. **BLE Wi-Fi setup.** Discover endpoints by their 0x2901 User Description descriptors. Require Security 1 and proof of possession. CryptoKit X25519/SHA256 and CommonCrypto AES-CTR implement the documented session; one CTR cursor spans proofs and both directions. Credentials follow successful board verification only. Scan/select or manually enter an SSID, configure/apply, then poll until the board reports connected with an address. Reset the provisioning state before retrying a rejected network. Cancel and disconnect on timeout, suspension or interrupted crypto exchange; no automatic PoP retries or insecure downgrade.
3. **Desktop phone association.** Use the phone's Computer connection, six-digit S6 code, version-gated link/list/unlink endpoints, empty grants and HTTP Retry-After cooldown. This association grants no control or Bluetooth authority. Unknown capabilities and grant schemas fail closed. Desktop control approval remains separate.
4. **Board desktop enrollment.** Remains on the board. This app does not provision a desktop bearer token or replace the board's certificate confirmation.

Relay v0 is limited to six streams and an 8192-byte credit window per stream. Each stream has at most one bounded socket read pending; CoreBluetooth write backpressure pauses reads. TCP-bound buffering is capped at 64 KiB per stream. Incoming lengths, frame kinds, credits and IPv4 destinations are validated. Stream object and connection identities discard callbacks from cancelled/reused streams. Ordered dial attempts use six-second deadlines and stop when the board closes the stream. The board's shorter overall open deadline can cancel a later attempt; the client does not extend it.

No network-name HINT is sent: SSID access is optional in the contract, and this implementation requests no location or Wi-Fi-information entitlement. The board must use its documented fallback behavior. Native SoftAP setup, USB transport, firmware updates and benchmark frames are not implemented. SoftAP/USB fallback is explained in the setup screen. The Bluetooth relay does not invent an away-from-home route; #46 covers desktop listener/reachability.

## Validation and remaining release gates

Executed here:

- Swift 6.2.4 compiled and ran the dependency-free protocol package: 18 Swift Testing tests passed, including parameterized malformed packets/destinations, desktop capability/grant checks and a deterministic input sweep.
- The Swift compiler parsed all app/test source files. This does not type-check Apple-framework calls or compile an iOS application.
- `npm test` passed all four extraction checks: original hashes, HTTP backend boundary, 12 JavaScript syntax checks and 47 worker cache references. PWA source/cache IDs are unchanged.

The native Xcode tests include an independently generated Security 1 interoperability vector, certificate checks, origin/permission validation and HTTP errors/rate limits. **They were not executed here.** No Mac, Xcode SDK, simulator, attached iPhone or board is available in this workspace.

Before release, run the full Xcode suite and physical matrix in `ios/README.md`: picker authorization and mode changes, SMP accept/reject, revoked bonds, service changes, repeated setup, wrong PoP/password, cancellation and privacy stop. Critically, verify relay behavior while the phone is locked, suspended, killed/restored, moving between Wi-Fi and cellular, and losing its VPN. A PC phone-peer test in the firmware ticket is not evidence that iOS sustains background TCP. Do not advertise uninterrupted background connectivity until measured.

Apple references: [AccessorySetupKit](https://developer.apple.com/documentation/accessorysetupkit), [accessory discovery](https://developer.apple.com/documentation/accessorysetupkit/discovering-and-configuring-accessories), [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth). Security message definitions and the independent reference were read from [ESP-IDF v5.5.5](https://github.com/espressif/esp-idf/tree/v5.5.5/components/protocomm/proto) and its provisioning schemas. No third-party framework or downloaded source is bundled in the app.
