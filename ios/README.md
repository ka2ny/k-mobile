# k-hole for iPhone

The native app around the phone app. Its screens are the phone app's own (Home, Remote, k-beam, Agents, Projects,
Assistant, Wallpaper, the floating menu: served by the computer's khole-web, one design for both); the app adds what a
web page can't do on an iPhone:

- **Pairing by one scan** of the code Settings > Remote > Pair a phone shows (`https://<computer>:<port>/#ticket=…`).
- **Setting up a k-chain** (the companion board) over Bluetooth: scan the setup code on the board's screen (Espressif's
  provisioning QR, Security 2 with its proof of possession), the phone hands it the computer's pairing details
  (`GET /app/companion/setup` → the board's `khole-pair` endpoint) and your Wi-Fi. Needs the firmware's half
  (ka2ny/k-chain-os `k-moon/main/link/link.c`: BLE provisioning and the `khole-pair` endpoint, still a TODO there).
- **Widgets** on the Home Screen and the Lock Screen (agents that need you, the computer's battery or free space), from
  the readings the phone app's Home already took: a widget never asks the computer.
- **The Share Sheet's k-beam**: anything shared from another app goes to the computer through k-beam.

## Build

A Mac with Xcode 16 (the PX13 can't build iOS):

```sh
brew install xcodegen
cd ios && xcodegen generate && open KHole.xcodeproj
```

To run it on an iPhone, set your team in `project.yml` (`DEVELOPMENT_TEAM`): an Apple Developer account for TestFlight;
a free Apple ID installs from Xcode for seven days.

Without a Mac: the `ios` workflow (Actions > ios > Run workflow) builds it for the simulator and keeps screenshots.

## How the page and the app talk

The page sees `window.kholeNative` (`{version, features, post(message)}`) and posts: `readings` (hub.js, after
`/app/widgets`), `kchain` (Settings and the floating menu's Set up a k-chain), `unpaired` (Remote's Unpair),
`share-ready` (k-beam opened for the Share Sheet), `haptic`. Only the paired computer's own pages are heard; any
other address opens in Safari.
