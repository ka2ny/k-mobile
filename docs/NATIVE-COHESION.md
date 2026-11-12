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
- Codemagic run `6af4ddb6973779a703f1ec0a` passed with Xcode 27.0: 22 native cases and three UI tests, zero failures. `DesignTests` verified every glyph loads from the compiled asset catalog and adaptive colors resolve in both appearances.
- Twelve original simulator screenshots were inspected: all five tabs in light/dark, empty pairing in light mode, and Settings in dark mode. The default Sage accent was used. No clipped controls or misleading connected/success states were observed in these captures.
- The first rebuild found an ambiguous UI-test query matching both Home and the Connections sheet's “Add connection” buttons. A stable identifier on the sheet action fixed the query; the full suite passed on rerun without skipping tests.
- The Release arm64 IPA is version **0.1.0 (7)** from `6ccbb701513fd88903c4b4e03f18d1faa8323200`. Its checksum, ZIP integrity, executable permissions and physical iOS Mach-O platform were verified. See [build evidence](../ios/REVIEW.md).

## Native verification still required

Extend the simulator coverage to connected/failed/permission flows, decisions, accessory setup, dark Pairing and light Settings. Switch all five accents, relaunch to check persistence, and exercise connecting, connected, view-only and failed states. Check large accessibility text, VoiceOver labels, Reduce Motion, Increase Contrast, narrow phones and iPad layouts. Confirm the physical accessory picker shows its new product glyph. Retest real pairing and commands against supported hardware/services. These checks remain tracked in [issue #2](https://github.com/ka2ny/k-mobile/issues/2).

## Reproduce the component preview

Run `python3 ios/render_design_preview.py` with `rsvg-convert` installed. It generates `artifacts/cohesion/native-theme-board.svg` and `.png` from the recorded palette and actual vector paths. This is an asset/component review, not a simulator screenshot. Check logs are in `artifacts/cohesion/` locally.
