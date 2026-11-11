# k-hole mobile

The installed mobile app has three destinations: **Remote, Beam and Agents**. This is the production interface on main, separate from the sample-data reference in `ui/quiet-glass-ui/examples/mobile.html`.

## Interface ownership

- `remote/app`: Home, searchable app launcher, shared settings, persistent mobile navigation, shared mobile material and locally packaged IBM Plex fonts.
- `remote/web/pwa`: pairing, login, desktop stream and remote controls.
- `remote/share`: Beam send tools, incoming shares, shared folder and transfer feedback.
- `agents/apps/web/remote`: session overview, approvals, conversation, starting sessions and settings.

All three retain their independent routes, workers and standalone fallback. Unified mode loads `/switch.css` and `/switch.js`; the home imports the same stylesheet from `hub.css`. The server deliberately removes switcher tags outside unified mode. Shared typography uses local fonts under the SIL OFL in `FONT-LICENSE.txt`, with system fallbacks. No CDN is involved.

## Mobile shell

Home offers connection status, evenly proportioned app tiles, a shared Files shortcut and the last opened app. App tiles show actual readiness, pairing or control requirements; their gutters stay fixed even on a narrow phone. Home does not duplicate the phone’s clock. The bottom navigation always exposes Home, Apps and Settings; Remote's live stream uses its Apps toolbar control instead, keeping video coordinates and touch gestures unchanged. Agents' tabs and approval pad sit above the shared navigation.

Settings offer named colour swatches with a visible selection mark, and persist an accent, motion preference and Home widget visibility in `khole-mobile-preferences`. Resume-last-app retains the existing `khole-app-remember` preference. No new credentials or app permissions are stored. Launching an app still goes through the original pairing and full-control checks. Switching apps navigates their real routes; it does not create extra background app instances.

The launcher filters the three installed destinations, reports service availability, and offers Home and Settings. Its headings receive initial focus so opening it on a phone does not immediately summon the keyboard. Modal keyboard navigation stays contained and restores the triggering control. Shared shell assets are cached only by unified-mode workers; standalone apps remain independent.

## Shared file browser

Home's Files shortcut opens Beam at `/beam/#folder`. Transfer and Files remain two views of Beam with the same pairing and shared-folder boundary. Only the regular files exposed by Beam's existing API are available; this is not unrestricted access to the computer's filesystem.

Files offers search, type filters, name/date/size sorting, list and 4:3 grid layouts, incremental display of 60 files at a time, file details, saving and adding files. Grid preference is local to the phone. Format labels, two-line filenames and 44px download controls share each grid tile; file details keep size, format and modification date in aligned rows. Details open at the title on short screens. Raster previews load only after opening details, with a 10 MiB preview limit; file content is never embedded as HTML. Failed refreshes explicitly mark retained data as stale. Turning sharing off clears the list and disables upload. Native download and share behavior is preserved.

## Visual rules

Use the current Quiet Glass Graphite palette. The switcher maps existing `--q-*` tokens when present and provides matching fallback values for Remote, Beam and Home. Neutral opaque surfaces carry work; glass is reserved for compact controls over content. Status colors remain separate from the sage accent.

Use a single primary page heading. Computer names describe the destination, not the app brand. Remote pairing occupies the canvas rather than a floating card. Beam's six send tools form one region; incoming content and the shared folder form separate regions. Agents shows state with a colored dot and words, with a narrow attention edge for requests.

Keep controls at least 44px, visible labels, native form behavior and keyboard focus. The app switcher is a modal dialog with explicit Tab wrapping, Escape dismissal and return to its trigger. Fetch results belong to the specific dialog instance that requested them. Remote retains `touch-action: none` on its stream gesture surface while the page viewport permits zoom.

Motion explains opening or interaction: Home arrives once, sheets enter vertically and dismiss in 140 ms, and moving into Settings uses a small horizontal transition. Programmatic switcher close stays immediate so callers can safely replace a sheet. There is no whole-control scaling or decorative loop. File sorting, filtering, paging and grid/list changes animate at most 24 visible items with opacity and translation; background refreshes never replay those movements. New interactions cancel old file movement. Reduced/off settings, OS reduced motion and backgrounding settle JavaScript animations immediately. File dialog close events are guarded against a replacement preview. Honor reduced motion. Service-worker cache versions must change when shell assets change; APIs remain uncached.

## Validation

- `python3 -m unittest discover -s tests/remote -p test_app.py`
- `node tests/remote/app_test.js`
- `node tests/remote/mobile_design_test.js [screenshot-directory]`
- `node tests/remote/mobile_performance_test.js`
- `node tests/remote/pwa_test.js [screenshot-directory]`
- `node tests/share/pwa_test.js [screenshot-directory]`
- Build `agents/`, then `node tests/agents/remote_pwa_test.js [screenshot-directory]`

Browser suites require Playwright and Chromium. They use local stand-ins or local service instances and do not connect to the user's live desktop. Screenshots from these suites contain fixture data. Physical iOS/Android installation, notifications and system share sheets still require device validation.

## Performance boundaries

Shared navigation observes inserted subtrees rather than repeatedly scanning the whole document. Late headers and Remote's Apps control still receive their handlers. File rows are keyed by filename: unchanged refreshes retain controls and focus, updates replace metadata, and removed or filtered rows leave the DOM. Natural-name collation reuses an `Intl.Collator`. File motion measures positions before starting animations, stops measuring below the viewport, and retains the 24-item animation cap.

Beam reserves one 64 MiB inbox prefetch budget across all items, with at most 128 entries and three simultaneous downloads. Hidden pages do not start speculative requests. Missing inbox entries and unpairing cancel queued/in-flight work and release cached files; stale inbox responses cannot restore cleared data. Response streams are checked against their reserved size. Download/share fallbacks remain available for files outside the budget. These are prefetch limits, not a limit on total browser memory or upload size.

The performance fixture uses 500 files (the backend listing cap), displays 60, and performs 20 unchanged refreshes at 390 × 844. In local headless Chromium, the visible-list median changed from approximately 17.3 ms at `188ea0e6` to 3.2 ms after this pass. Row removals fell from 1,200 to zero; five unrelated DOM updates caused zero document-wide navigation scans, down from five. Timings are diagnostic and machine-dependent; tests assert the structural budgets rather than a brittle millisecond threshold. Use `MOBILE_PERF_BASELINE=188ea0e6` with the performance test to serve that revision's scripts for comparison. This is not a physical-phone frame-rate claim.

## Reliability fixes found during this pass

Cancel before a prepare response now cancels the returned request ID as soon as it arrives. The browser test holds that response to verify the desktop approval card disappears. Beam socket binding uses a private 0077 process mask, then explicitly chmods the socket to 0600; the former 0177 mask could leave a concurrently created state directory without owner traversal.
