# Native review — 11 November 2026

Review scope: native SwiftUI app, accessory/gateway lifecycle, motion, accessibility, request load and IPA pipeline. Existing PWA assets and their extraction baseline remain unchanged. This is a source review with local tests, not a completed visual/device qualification.

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
- A 180 ms control press response with a small scale change and tint shift. Disabled controls remain visibly distinct; Increase Contrast strengthens their border. Reduce Motion removes the spring/scale.
- A scoped 200 ms connection/receipt transition. No global animations on polling data and no perpetual symbol, glow, shimmer or background loops.
- Success haptics only after a confirmed desktop action receipt. Pairing/authorization selection and network requests are never optimistic success events.
- Native navigation/sheets retain their system transitions. Interactive keyboard dismissal is available in Assistant. Explanatory copy distinguishes physical k-chain pairing from the dedicated desktop listener.

## Performance work and limits

The foreground monitor fetches companion snapshots only on Controls. Healthy Home requests fall from three to two per cycle (roughly 36 to 24 per minute, excluding manual refreshes and request latency). k-chain and Activity use a 15-second interval instead of five seconds (roughly eight desktop requests/minute for Computer connections). Failed connections back off to 30 seconds. Assistant remains tab/scene scoped with coalesced reads.

Relay reads can batch up to 4096 bytes within the available credit, then split into the actual BLE write limit. This reduces opportunities for socket callback overhead when the network provides larger reads; it is not a measured throughput claim. At most six streams exist, each with one bounded read, at most 4 KiB pending phone-to-board data and 64 KiB queued board-to-TCP data. Flush work yields after 16 writes and cannot recurse through close/enqueue. Status observation updates only when the stream count changes.

Added XCUITest navigation checks, disconnected-state assertions, screenshot attachments for every main tab/pairing, and an application-launch metric. These run as part of the shared Xcode scheme and publish evidence with the test result bundle. They have **not run yet**. No FPS, launch-time, energy, BLE-throughput or physical-device measurements are claimed.

## Validation and release blockers

- Passed locally: 22 portable Swift tests; eight CI helper tests; four extraction tests (12 JavaScript syntax checks, 47 cache references); Swift compiler syntax parsing; actionlint; project/plist/scheme consistency.
- GitHub PR #1: <https://github.com/ka2ny/k-mobile/pull/1>.
- GitHub execution did not reach compilation. No Apple SDK or simulator results are available from this review. Resolve CI availability before retrying checks.
- Unsigned IPA packaging now needs no Apple signing configuration. Use `ci/README.md` for the default pack-now/sign-later path; configure signing only for optional signed exports.
- Native build/API/concurrency correctness, UI screenshots, Dynamic Type/VoiceOver, Reduce Motion and measured launch performance remain gates. The new XCUITest suite must run successfully, and screenshots must be inspected before calling the visual pass verified.
- Physical iPhone/board bonding, wrong-code/reset/reconnect flows, TLS relay interoperability and locked/suspended background reliability remain unverified. Native SoftAP, streaming, files and voice remain outside the implemented native scope.

No IPA was packed, no PR was merged and no firmware/OS source was modified.
