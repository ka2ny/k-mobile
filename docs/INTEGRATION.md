# OS integration boundary

## Source mapping

| Remote OS source | Local destination | URL |
| --- | --- | --- |
| `remote/app/*` | `public/*` (design notes moved to docs) | `/` and `/assistant/` |
| `remote/web/pwa/*` | `public/remote/*` | `/remote/` |
| `remote/share/*` | `public/beam/*` | `/beam/` |
| `agents/apps/web/remote/*` | `public/agents/*` | `/agents/` |

Beam's four icon URLs were served by the upstream share backend from `remote/web/pwa`. This extraction materializes those assets in `public/beam/`; omitting them would break manifests and worker installation. Agents' OMP module is included, matching its current `files.json` and cache manifest. Local fonts and applicable notices travel with the frontend.

The preview server mirrors unified-mode manifest rewriting for subapp HTML and substitutes Beam's `{{NAME}}` placeholder with `Local preview`. Source files themselves are unchanged. The preview binds to loopback, serves only `public/`, does not list directories, and returns explicit HTTP 503 JSON for backend routes and mutation requests. It is a development viewer, not a production gateway or authentication implementation.

## Required services

A live deployment needs the existing OS gateway (`remote/web/khole-web`), Beam (`scripts/khole-share`) and the Agents server/connector. The gateway owns pairing, control approval, trusted-host tickets and same-origin routing. Remote's token and the gateway's HttpOnly app cookie must retain their original authentication semantics. Merely hosting these files on a different origin does not connect the services.

Route `/api/*` to Remote, `/app/*` to the mobile gateway/Assistant controller, `/beam/api/*` and transfer/share routes to Beam, and `/agents/api/*` to the authenticated Agents proxy. Preserve streaming/SSE, WebRTC negotiation, uploads, CSRF/origin/auth checks, desktop consent, and per-host/session capabilities. Do not replace these boundaries with a blanket permissive CORS proxy.

The OS gateway currently uses `app_dir` for the mobile shell and `static_dir` for Remote assets. Its Beam and Agents proxy routes are backed by their own services, which also serve their UI assets. Integrating this extraction therefore requires mapping all four asset roots; changing only the gateway's root directory is insufficient. Backend scripts, system services, native capture/input dependencies and desktop Agents UI are intentionally outside this clean frontend repository.

## Cache/versioning

Root, Remote, Beam and Agents workers retain their original scopes and cache IDs. Assistant is deliberately live rather than cached by the root worker. Keep APIs out of shell caches. Bump the relevant cache versions when modifying copied frontend assets. Use a dedicated localhost port for preview; existing service workers can continue controlling an origin until updated/unregistered.

## Provenance and updating

`source.json` pins the inspected upstream commit and every exact copied file. Its hashes are extraction-baseline evidence; intentional future source edits require documenting the change and updating the associated provenance/test expectation. Do not attach this repository's `main` to OS `main` or carry over OS Git history. Compare upstream changes against the recorded source paths when importing later mobile updates.

## Native iOS client

`ios/` adds an independently authored SwiftUI client without modifying extracted assets or their baseline hashes. Its [implementation notes](../ios/README.md) separate native functionality from browser handoffs and unimplemented features. The new app icon is rendered from the existing vector mark; its separate provenance is in `ios/provenance.json`.

The client pairs through `/api/pair`, checks `/api/hello`, and preserves the gateway's ephemeral HttpOnly cookie for `/app/status` and `/app/assistant*`. Native tokens are stored per origin in Keychain and are never passed to browser links. Phone full-control requests use `/api/ask-control`; approval still happens on the computer.

k-chain integration means compatibility with the desktop companion v1 API: `/api/companion/events`, `/api/companion/command`, `/api/companion/agent`. Its dedicated LAN listener (normally HTTPS 8445) has a distinct PIN, certificate and restricted companion identity. The native client supports both the phone gateway and this listener; it does not impersonate an existing board. The separate k-chain tab now implements direct accessory pairing, BLE Wi-Fi setup and the board’s opaque Bluetooth/TCP relay. Initial certificate-code verification is followed by full certificate pinning. The companion source was read from a different local OS revision than the extracted PWA, recorded explicitly in `ios/provenance.json`; deployed compatibility has not been tested.

No OS source, service configuration, remote repository or publication target was changed. The standalone HTTP preview still supplies no backend and cannot serve as a successful native pairing endpoint.

Physical accessory integration and the latest ticket audit are documented in [NATIVE-ACCESSORY.md](NATIVE-ACCESSORY.md). Desktop phone association requires `/api/hello` capability `companion_link: 1` and uses `/api/companion/link`, `/api/companion/links`, `/api/companion/unlink` with the phone’s own identity. The association grants no control. Bluetooth relay, Wi-Fi provisioning and desktop association remain separate states; none creates a simulated successful backend. Away-from-home reachability remains tracked in OS #46.
