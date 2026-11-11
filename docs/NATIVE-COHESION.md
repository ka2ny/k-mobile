# Native mobile cohesion pass

This pass aligns the native SwiftUI app with the k-hole mobile shell. The extracted PWA, its routes, service workers and source hashes are unchanged. No gateway, pairing, permission or command contracts were changed.

## Design contract

- Adaptive graphite surfaces with sage as the default accent. Settings offers System, Light and Dark appearance, plus Sage, Ice, Lilac, Rose and Amber accents. Preferences persist locally; this does not synchronize the computer’s appearance.
- Twelve 24-unit outline glyphs use a 1.5-unit rounded stroke. Seven derive from the existing mobile shell; five matching native glyphs cover activity, accessory, controls, computer and connection. See `ios/design-provenance.json` for exact sources and hashes. The existing app icon and mark are retained.
- System typography supports Dynamic Type. Shared headings, empty states, row surfaces and controls replace competing treatments. SF Symbols remain for conventional actions with outline, monochrome rendering.
- Success, caution and failure colors stay independent of the selected accent. State is also expressed in text or shape.
- Primary controls have a 50-point minimum height; secondary controls use 48 points. Press feedback is a finite 140 ms transition, with no scaling or repeating effects. Motion respects Reduce Motion; surfaces respect Increase Contrast.
- Home provides one setup action with concrete pairing instructions. Existing disabled states and permission boundaries remain intact.

## Verification recorded for this pass

- `npm test` / Python discovery: 7 passing extraction and design tests, including 12 JavaScript syntax checks and 47 service-worker cache references.
- Portable Swift package: 24 passing protocol tests in 3 suites.
- Native Swift source syntax parse: passed. This is not an Apple SDK type-check or build.
- Native asset checks enforce 4.5:1 contrast for normal text, status colors and accent control labels across both appearances, including pressed tint states. SVG geometry, template flags and provenance hashes are checked.
- Existing pending CI/documentation edits were preserved byte-for-byte.

## Native verification still required

Run the existing Xcode build and test pipeline on a supported Mac. New `DesignTests` verify every glyph loads from the compiled asset catalog and adaptive colors resolve; these tests are registered in the generated project but have not been run here.

Review all five tabs, Connections, Pairing, Settings, decisions and accessory setup in light and dark mode. Switch all five accents, relaunch to check persistence, and exercise empty, offline, connecting, connected, view-only, failed and disabled states. Check large accessibility text, VoiceOver labels, Reduce Motion, Increase Contrast, narrow phones and iPad layouts. Confirm the accessory picker shows its new product glyph. Retest real pairing and commands against supported hardware/services.

Prior simulator screenshots predate this pass and do not qualify these changes. This Linux environment cannot run Xcode or capture new native screenshots.

## Reproduce the component preview

Run `python3 ios/render_design_preview.py` with `rsvg-convert` installed. It generates `artifacts/cohesion/native-theme-board.svg` and `.png` from the recorded palette and actual vector paths. This is an asset/component review, not a simulator screenshot. Check logs are in `artifacts/cohesion/` locally.
