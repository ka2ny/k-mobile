# k-hole mobile extraction

Work in this standalone mobile frontend repository. Read README.md, docs/FEATURES.md, docs/INTEGRATION.md and source.json first.

- This repository was requested as a local copy. It has no remote. Do not publish it or mutate the OS repository without an explicit user request.
- Keep native mobile routes, shared shell, scoped workers, local fonts and notices intact. This is the real PWA, not the design-system example.
- The local preview intentionally does not implement OS services. Do not fake successful pairing, control approval, transfers, sessions or Assistant execution.
- Before changing behavior, distinguish frontend work from OS gateway/Beam/Agents backend dependencies documented in docs/INTEGRATION.md.
- Run npm test after extraction or asset changes. The source hashes are baseline provenance: document intentional edits and update the baseline explicitly when needed.
- Optional browser tests require Playwright and Chromium; never describe unrun device/backend checks as passed. Keep API responses out of service-worker caches; bump relevant cache IDs when modifying shell assets.
