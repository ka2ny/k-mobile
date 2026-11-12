# Mobile workflow foundation — 2026-11-12

This branch starts the product work in [#4](https://github.com/ka2ny/k-mobile/issues/4) on top of PR #3 (`81e06ae`). It does not claim complete PWA parity. Firmware and OS repositories are unchanged.

## Navigation and ownership

Five stable destinations: **Computer · Beam · Agents · Assistant · k-chain**. All are visible before pairing and have actionable connection states. The toolbar identifies the selected computer. A temporary offline response does not discard an already-open feature; selecting a different computer invalidates its feature identity.

- Computer owns Remote, media/focus/lock and the control-permission request. Activity and computer discovery are secondary destinations here.
- Beam owns Send, Inbox, Files and Clipboard. Shared files support search and name/date sorting with lazy rows. Text clears only after a successful server acknowledgement; drafts are held per computer while the app remains open, including across backgrounding.
- Agents owns decisions, conversations and changes. Companion-only connections retain their decision cards in this tab. Successful diffs show files rather than an error/retry branch.
- Assistant retains the native task/history/thread flows. Successful desktop approval/continuation handoffs offer a direct route to native Remote.
- k-chain owns physical accessory setup. Desktop pairing and phone association remain distinct.

## Accessory evidence and presentation

An introductory sheet explains the board pairing window, system discovery, numeric comparison and missing-device recovery. The iOS picker opens after this sheet dismisses. The follow-up sheet opens only after `pickerDidDismiss`, even if GATT discovery has already begun.

The typed relay state separates selection, connection, subscription/confirmation, verified Bluetooth and active TCP relay. Subscription is **not** success. The current firmware transmits a valid protected OPEN only after bonding; that event verifies Bluetooth. Active TCP connections do **not** assert authenticated desktop reachability. Firmware version comes from the advertised info response; no battery, numeric codes, clock or desktop certificate words are invented in the artwork.

Setup content scrolls at large text sizes. Idle artwork is static; the connection halo runs only while its view is visible, the scene is active, connection work is pending and Reduce Motion is off. In-progress setup offers explicit cancellation or continuation in the foreground. Wi-Fi and desktop phone association remain optional follow-up actions.

## Lifecycle changes

- Remote invalidates pending offers and callbacks on disconnect, host change and backgrounding; restart tasks are owned and canceled. A late offer cannot reopen a dismissed screen. “Live” waits for received media; a missing first frame times out.
- Beam binds sends, downloads and cancellation to its original gateway/generation. Late preparation responses cannot initiate an acceptance poll on a newly selected computer. Leaving the feature stops its outgoing send.
- Agents stamps and dispatches each command through one captured gateway/relay-host revision. Host switching cancels delayed sends/creation, scopes drafts by relay host and ignores stale reads/results.

## Validation

The tests-only Codemagic workflow `ios-review` compiles the app and runs portable, native and UI checks without packaging an IPA. Native regression tests use real feature models and URLSession with a test-only server stub: successful diff rendering state, acknowledged/declined text, stale Beam preparation, a host switch during connector lookup, and a late Remote offer after disconnect. UI checks cover disconnected routes, light/dark appearance, introductory pairing cancellation and large text.

Local PWA extraction checks: **7 passed**, including 12 JavaScript syntax checks and 47 worker-cache references. CI helper tests: **15 passed**. These changes do not modify `public/` or `source.json`; extraction provenance and cache IDs remain unchanged. All **36 portable Swift tests** passed on Xcode 27. Native app/UI results are recorded in the PR after the run completes.

## Remaining work

[#4](https://github.com/ka2ny/k-mobile/issues/4) remains the parity backlog: Assistant memory, richer Remote input, file previews/share extension, media import/progress improvements, persistent transfer/history workflows and connected acceptance scenarios. This foundation does not complete those items.

[#5](https://github.com/ka2ny/k-mobile/issues/5) still needs real iPhone/board numeric comparison, denied access, timeouts, Wi-Fi transitions, reconnection and restored/background relay qualification. Simulator screenshots cannot establish those results. Phone links continue to require the deployed desktop capability.

[#6](https://github.com/ka2ny/k-mobile/issues/6) remains open for the wider Assistant/import/download lifecycle audit and live multi-computer tests. The regressions covered here are a bounded subset. [#2](https://github.com/ka2ny/k-mobile/issues/2) retains physical accessibility and performance qualification; no measured device battery or frame-time improvement is claimed.
