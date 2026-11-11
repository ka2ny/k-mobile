# Extraction verification — 2026-11-10

Source: remote OS `main`, commit `ce0977697fb11cb1958773e9568b95742a28d6be`.

Command: `python3 -m unittest discover -s tests -p 'test_*.py'`.

Passed all four extraction tests:

- All 48 copied files match their recorded upstream SHA-256 hashes.
- HTML, CSS and manifest asset references resolve locally.
- All 12 frontend JavaScript files pass syntax checks; all 47 references across the four service-worker caches resolve.
- All five page routes serve successfully; API/mutation requests explicitly report preview-only; directory traversal and repository-file requests are rejected; HEAD works for assets.

No Playwright/Chromium installation was available in this environment, so the optional copied browser performance suite was not run. No claim is made about live backend integration, physical-phone installation, WebRTC streaming, agent execution, file transfers or push notifications. No live host services were contacted during preview tests.
