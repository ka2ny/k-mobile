# What the app needs from k-hole OS

The app (`ios/`, XcodeGen) is a native shell: it doesn't carry the phone app's pages. It loads them from the paired
computer's khole-web (`https://<computer>:<port>/`, the address in the pairing code Settings > Remote > Pair a phone
shows), so the screens are always the computer's current phone app (Home, Remote, k-beam, Agents, Projects, Assistant,
Wallpaper, the floating menu).

It relies on these pieces in ka2ny/k-flow-os, branch `ios-native` (on top of `phone-final`):

- `remote/web/khole-web` `GET /app/companion/setup`: the home-network addresses and port boards reach, the companion
  PIN and the certificate's code and words, for a paired phone with full control only (k-chain setup).
- `remote/app/switch.js`: with `window.kholeNative` present, Settings and the floating menu offer Set up a k-chain.
- `remote/app/hub.js`: Home posts its readings (`readings`) after `/app/widgets`, for the widgets.
- `remote/share/app.js`: `window.kholeBeamReceive(item)` and `share-ready`, for the Share Sheet.
- `remote/web/pwa/app.js`: Unpair posts `unpaired`.

The k-chain's half (BLE provisioning with Security 2 and a `khole-pair` custom endpoint) belongs in ka2ny/k-chain-os
`k-moon/main/link/link.c`, where it is still a TODO.
