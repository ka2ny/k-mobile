# Native mobile journeys — 12 November 2026

The native app has five destinations: **Computer · Beam · Agents · Assistant · k-chain**. This work is on PR #8, based on `claude/native-k-hole-app` / PR #3. It improves complete mobile workflows while retaining the theme and icon system. It does not claim full PWA parity or physical accessory qualification.

## First use and connection continuity

Computer owns desktop connection, Remote, quick controls and permission requests. Beam and Assistant let you write a real local draft before pairing; connecting returns to the feature you opened. Cancelling connection setup or changing tabs keeps the draft. Drafts are held in memory per selected computer, survive backgrounding, and clear only after the original computer acknowledges the submitted text. They are not a persistent offline queue.

Each disconnected destination explains its own work. No sample sessions, transfers, battery values or successful connections are presented as live data. The first-use k-chain entry leads to physical accessory setup, separate from desktop authentication.

## Beam and Files

Beam separates Send, Inbox, Files and Clipboard. Shared files have combined name/type filtering; natural name, newest and largest sorting; list/grid layouts; and incremental groups of 60. The sorted collection is recomputed when the query or file data changes, not for every body update. Accessibility text sizes use a single column.

File details show the server's name, type, size and modification date. Save downloads the real file into Files → k-hole → Received. Files up to 32 MiB can open in native Quick Look after downloading; larger files can be saved and shared to another app. Preview does not prefetch the whole folder. Downloads can be cancelled; duplicate concurrent row downloads are refused.

Documents and selected photo/video representations are copied to protected temporary files off the main actor. Videos are no longer loaded into a single Data allocation. Import and send lifetimes are owned, partial selections are cleaned up, and outgoing temporary files are removed after success, failure or cancellation. Upload retry/resume continues using the existing Beam API. Progress remains server/request based; this does not add a durable background transfer queue.

## Assistant

Tasks, executor choice, attachments, questions, queue/steer, history, conversations and desktop approval handoff remain native. The new memory sheet reads `/app/assistant?memory=<persona>` and shows facts, pinned/locked state, how-to notes and lessons. Memory management remains on the desktop, matching the PWA contract.

All reads and actions capture the original gateway and validate the connection generation and request identity before applying results. Leaving/backgrounding invalidates pending responses. A late acknowledgement cannot clear another computer's draft. Attachments are bounded to four files and 20 MiB total; file reads happen off the main actor and stop at the remaining byte limit. Import failures are shown beside the attachment control. Task submission and attachment mutation cannot race.

## Agents and Remote

Agents owns decisions, conversations and changes. Successful diffs show their files. Commands capture a gateway and relay-host revision before asynchronous connector lookup. The session model is owned above the navigation stack: opening a conversation does not stop it. Changing tabs/backgrounding stops polling and pending work; switching computers invalidates the model.

Remote owns its connection/restart task and rejects stale offers and callbacks. “Live” waits for received frames, with a first-frame timeout. The keyboard composes text locally and sends it on an explicit tap, preserving input-method composition and local deletion. Its special-key strip uses the OS router at `k-flow-os` main `eee7c62ac9c87ddd9ae44e2bbd00654a6aeccdb6` (`remote/web/khole-web`) and its atomic `combo` message with browser key codes (`Enter`, `Backspace`, `ArrowLeft`, etc.); the previous `key/k` message was ignored by that router. Typing requires full control. Transport-specific device interoperability remains a release check.

## k-chain setup

Setup introduces the board's **Pair a phone** action, then hands discovery and numeric comparison to AccessorySetupKit. Troubleshooting is expandable. The system picker opens after the introduction dismisses; the progress sheet opens after the system picker dismisses. The current step and primary action stay visible, including at large text sizes.

Selection, connection, numeric confirmation, verified Bluetooth and active TCP relay are distinct. Subscription alone never counts as success. The first valid protected OPEN verifies Bluetooth; TCP connections do not imply desktop authentication. Wi-Fi setup and phone association are optional follow-up journeys. The board continues to own desktop enrollment and certificate confirmation.

The system picker now renders the same neutral device artwork as the app; it no longer uses an illustration containing sample clock/battery values. Button feedback and state transitions are finite and respect Reduce Motion. The discovery halo is limited to visible, active connection work. No uninterrupted background relay or measured battery improvement is claimed.

## Validation and evidence

`ios-review` compiles the app and runs the portable contracts, native models and UI tests without packaging an IPA. The PR records the exact tested commit and Codemagic run. Native regression tests cover stale responses, acknowledged/declined text, file-backed import cleanup, bounded attachment reads, Remote wire keys, file filters/sorting and successful diff rendering.

UI coverage includes disconnected routes in light/dark appearance, cancelled connection setup, draft retention, k-chain introduction and the largest accessibility text size. **Fixture-Files** and **Fixture-Assistant-Memory** images render real SwiftUI views against a test-only URLSession server. They are layout evidence, not live backend/device acceptance. Production has no fixture server or demo-success launch mode.

`npm test` validates the seven extraction checks, including 12 JavaScript syntax checks and 47 worker-cache references. Fifteen CI-helper tests also run. `public/`, `source.json`, scoped workers, fonts and notices are unchanged; baseline hashes/cache IDs need no update.

## Remaining release work

- [Mobile #4](https://github.com/ka2ny/k-mobile/issues/4): share extension, durable transfer/retry history, additional Remote controls and full connected acceptance across the PWA feature matrix. Voice, push and widgets remain outside this pass.
- [Mobile #5](https://github.com/ka2ny/k-mobile/issues/5): real iPhone/board discovery, numeric accept/reject, denied access, timed-out windows, repeated setup, Wi-Fi transitions, bond revocation and recovery.
- [Mobile #6](https://github.com/ka2ny/k-mobile/issues/6): live multi-computer/background stress tests and broader lifecycle qualification. Existing regression tests do not replace those scenarios.
- [Mobile #2](https://github.com/ka2ny/k-mobile/issues/2): physical VoiceOver/large-text use, Release launch time, frame time, energy and Bluetooth throughput. Debug simulator launch samples are not a device performance benchmark.
- Existing backend dependencies remain [firmware #4](https://github.com/ka2ny/k-chain-os/issues/4), [firmware #5](https://github.com/ka2ny/k-chain-os/issues/5), [OS #45](https://github.com/ka2ny/k-flow-os/issues/45) and [OS #46](https://github.com/ka2ny/k-flow-os/issues/46). Their open status does not imply missing implementation: native-iPhone/deployed-service qualification remains required. No firmware or OS files were changed.
