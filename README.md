# k-hole mobile

Clean local extraction of the production mobile PWA from `ka2ny/k-flow-os`, remote `main` at **ce0977697fb11cb1958773e9568b95742a28d6be** (10 November 2026). This is the real mobile interface, including its new Assistant page, not the design-system example.

## Preview locally

Requires Python 3.10+; no installation or build step:

```sh
cd ~/Projects/k-mobile
python3 scripts/serve.py
```

Open **http://127.0.0.1:4173**. Alternative: `npm start`. Use `--port 4174` to change the port. Home, navigation, launcher, preferences and all page assets are local. The server deliberately reports live services as unavailable: it cannot pair a phone, stream a desktop, transfer files, approve agents or execute Assistant jobs. It neither fabricates sessions nor connects to your computer services. Open app routes directly to inspect their disconnected/pairing states:

- `/` — Home, searchable launcher, shared settings and computer switching interface.
- `/remote/` — desktop connection, pairing and controls.
- `/beam/` and `/beam/#folder` — sharing and Files.
- `/agents/` — coding-agent sessions and controls.
- `/assistant/` — computer Assistant, jobs, conversations and memory views.

## Repository

`ios/` contains a separate native SwiftUI client for Computer and k-chain companion connections. Open `ios/KMobile.xcodeproj` on a Mac; see [native iOS setup and implementation scope](ios/README.md). Native accessory pairing, BLE Wi-Fi setup, encrypted-traffic relay and version-gated phone linking are implemented. Portable Swift protocol tests pass; full Xcode, simulator, physical-device and live-backend checks have not been run. The extracted PWA remains unchanged. [GitHub Actions and Fastlane](ios/ci/README.md) provide simulator checks and manual signed IPA exports after the GitHub account billing lock is resolved and signing settings are configured.

`public/` contains browser-ready sources with the original route structure, fonts, icons and four service workers. `docs/FEATURES.md` inventories the copied features and their backend dependencies. `docs/INTEGRATION.md` explains production routes and extraction boundaries. `source.json` records upstream paths and SHA-256 hashes; copied production files are byte-identical. `docs/UPSTREAM-DESIGN.md` preserves the original design/performance notes, which predate some Assistant additions.

The local extraction retains its own Git history. The user-authorized native app review is published separately in `ka2ny/k-mobile` on PR #1. No OS build products, model weights, credentials or node_modules are included. Source notices and font licenses are retained. Desktop Agents and host services stay in the OS repository.

## Verify

Python 3.10+ and Node.js are needed for extraction checks:

```sh
npm test
# or: python3 -m unittest discover -s tests -p 'test_*.py'
```

Checks cover source hashes, HTML/CSS/manifest dependencies, JavaScript syntax, all service-worker cache entries, HTTP routes and the preview/backend boundary.

`tests/mobile_performance.cjs` retains the upstream mobile performance assertions with asset paths adapted to this repository. To run it separately, provide Playwright and its Chromium browser (`npm install --no-save playwright`, `npx playwright install chromium`, then `npm run test:performance`). It uses synthetic intercepted browser requests, not your desktop. The OS git-history baseline mode is deliberately disabled because this is a fresh repository. Browser/device/live-backend qualification is separate from extraction checks.
