# Copied mobile features

Inspected in remote main `ce0977697fb11cb1958773e9568b95742a28d6be`. This inventory describes frontend capabilities found in the source, not a claim that the standalone preview supplies their backend.

| Area | Included interface and behavior | Live dependency |
| --- | --- | --- |
| Home and launcher | Connection/readiness indicators; Remote, Beam and Agents tiles; Files and Assistant shortcuts; searchable app launcher; persistent Home/Apps/Settings navigation; last-opened app | `/app/status`, shared pairing and service readiness |
| Appearance and motion | Five accent palettes, system/reduced/off motion, Home widget visibility, resume-last-app, local fonts, touch-sized controls, focus-contained dialogs, keyboard dismissal | Local browser preferences; no backend required for preferences |
| Computers | Paired computers, add-computer guidance, desktop settings action and ticket-based handoff to another host | `/app/computers`, `/app/computers/add`, `/app/computers/ticket`, OS device trust |
| Remote | PIN pairing, login, full-control request, WebRTC desktop stream, touch/pointer/keyboard controls, quality and display controls, file tools, draft review, k-stream delegation | `/api/*`, desktop approval/authentication, compositor/capture/input and WebRTC |
| Beam | Files/photos/text sharing, incoming items, clipboard, transfer progress/cancel/retry/resume, share links, push and system share-target handlers | `/beam/api/*`, Beam service and shared pairing |
| Files | Shared-folder browser, search/type filters, name/date/size sorting, list/grid layouts, incremental 60-item display, file details, bounded image previews, save/upload | Beam's bounded shared-folder API; not arbitrary filesystem access |
| Agents | Session list and detail, conversation/activity stream, approvals/denials, steering/stopping, workspace/session creation, workspace preparation jobs, host/device management, replies, notification settings, native session discovery and OMP controls | `/agents/api/*`, authenticated Agents relay/connector and installed coding tools; actual controls depend on session capabilities |
| Assistant | Job submission, executor selection, attachments, active-job feedback, stop/continuation actions, history/chats/threads, memory view, handoff to Remote for desktop approvals | `/app/assistant*`, desktop Assistant and full-control permission |
| PWA | Unified install manifest, Android share target, app icons, scoped shell caches, app-specific workers, network-first cached shells | HTTPS/localhost secure context; push/share/installation support depends on browser and device |

Existing performance measures are preserved in source: keyed file rows, incremental rendering, at most 24 animated visible file items, bounded inbox prefetch (64 MiB / 128 entries / three concurrent downloads), hidden-page pauses and uncached API paths. These are implementation limits, not new measurements on physical phones.

## Extraction validation

Run `npm test`. No browser, phone, microphone, live agent, desktop stream or real transfer is exercised by that command. The copied UI is unchanged; design refinement and independent backend development can begin from this local repository.
