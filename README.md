# k-hole mobile

k-hole for iPhone: a native app around the phone app your computer serves, so its screens are k-hole's own (Home,
Remote, k-beam, Agents, Projects, Assistant, Wallpaper), with what only a native app can do: setting up a k-chain over
Bluetooth, Home Screen and Lock Screen widgets, and the Share Sheet to k-beam. See [ios/README.md](ios/README.md) and
[docs/PWA-HOOKS.md](docs/PWA-HOOKS.md).

Build: Codemagic (`codemagic.yaml`, workflow k-hole-ios: simulator screenshots and an unsigned IPA), or on a Mac with
XcodeGen and Xcode (`cd ios && xcodegen generate`).

The earlier SwiftUI app (KMobile) and its README are kept on the branch `old/main` and on its PR branches.
