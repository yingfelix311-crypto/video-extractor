# Onboarding, Session Evidence and Clip Sizes Plan

> Use subagent-driven-development for isolated input/clip tasks and targeted reviews. Current task branch: codex/short-video-completeness, baseline 1c42b38.

**Goal:** Explain actual session behavior with evidence, ship accurate novice guidance, clear link inputs quickly, and preview/export source/common video sizes.

**Architecture:** Preserve the native SwiftUI app and local MeTube engine. Keep website-session reading separate from authentication claims; add contextual guidance and explicit one-task session bypass. Share pure canvas geometry between preview and export; preserve original-size export path.

**Tech Stack:** SwiftUI/AppKit, AVFoundation, Swift command-line tests, existing Python yt-dlp backend.

## Global Constraints

- No real Cookie values, personal account data or signed media URLs in diagnostics or fixtures.
- Never infer account login from Cookie existence, key names or extraction success.
- Preserve source media, user history, destination and existing settings.
- Clear input changes only draft text and focus, never active tasks or selected options.
- Original video dimensions are the default. Preview and export use the same selected canvas, aspect-fit with black bars, no stretching or default cropping.
- One final native install after tests/review; no broadening privacy permissions or weakening signing requirements.
- State local runtime dependencies honestly; do not promise standalone distribution.

## Task 1: Session facts and newcomer experience

Files: BrowserSessionStore.swift, Store.swift, DownloadSettings.swift, DownloadPolicy.swift, Submission.swift/SubmissionRow.swift, new QuickStartView.swift; tests BrowserSessionTests.swift/CoreTests.swift; help in ShouxiaApp.swift. Parent owns these.

- [ ] Controlled read-only extraction using a fresh empty jar, imported selected-browser jar, and same request route. Record only counts/flags/outcomes. Check manual global cookie status separately.
- [x] Add failing tests showing that guest Cookie data is described as read-but-login-unverified, and a one-task browser bypass issues no browser read, preserves permanent selection and original request options/destination. Runtime validation must still precede real credential reads.
- [x] Extend submit with optional useBrowserSession override, add retrySubmissionWithoutBrowser, and expose explicit local session-reading check. Never automatically switch browser/profile or claim verified login.
- [x] Rewrite settings and errors; put manual import/proxy/header controls in advanced disclosure. Add QuickStartView and update help to explain paste, formats, saved files, optional site session, errors, clips, dependencies.
- [x] Test normal/empty/permission-denied/bypass/cancel/uncertain states using isolated synthetic defaults.

## Task 2: Clear link inputs

File: MainView.swift. Input implementer owns it.

- [x] Add a conditional clear control to main/QuickPanel drafts, accessible labels, 24pt hit target and restored focus. Preserve captured-input comparisons in submit.
- [x] Add quick-start entry using store.showQuickStart and QuickStartView(store:store,updater:updater). Main/Quick default new-user quality becomes best while existing stored values are unchanged.
- [ ] Typecheck and UI-verify nonempty/empty/active-submit behavior; avoid trivial tests that duplicate assignments.

## Task 3: Clip dimensions

Files: ClipEditor.swift, ClipExporter.swift, new ClipCanvas.swift, clip tests and their scripts. Clip implementer owns these.

- [x] Test source/rotated dimensions, aspect-fit geometry and chosen canvas, then implement.
- [x] Add source default and common size presets, aspect-fit bounded preview, resizable/scrollable editor.
- [x] Preserve original export path; non-original canvas uses AVMutableVideoComposition with normalized source transform, uniform fit and centering. Apply orientation exactly once.
- [x] Test actual landscape/portrait/rotated output dimensions and media preservation with speed changes. Keep temp fixtures isolated.

## Task 4: Review, install, end-to-end

- [x] Review each independent change, fix important findings, then broad final review.
- [x] Run affected full native test suite, native build, backend plugin tests and exact source-vs-installed hashes.
- [ ] Back up current installed app and preferences without dumping secret values; install once. Verify new novice UI, clear controls, source/default/common preview and real clip export.
- [ ] Run real scoped download/metadata checks; handle any required OS authentication by user handoff, without claiming it completed prematurely.
- [ ] Save evidence report and concise user guide with actual state/remaining distribution constraints; commit changes on current task branch.

## 2026-10-18 verified progress

- 11 native test scripts passed; 8 backend-plugin tests passed in actual Python/yt-dlp container runtime. Native optimized build and codesign verification passed. Installed binary matches build, SHA256 bc1055f851710779caf7881844f78b074c092ea933e76dae6b4290e5cbf037fc, version 1.3.0 (5).
- Independent session/runtime/input review: no Important findings; Minor permission hint and inspection target issues fixed. Clip review: asymmetric visual oracle + all six preset real exports added. Whole-change review found cancellation during metadata setup; guard added before session assignment, source/preset cancellation tests passed; rereview approved.
- Isolated new-user QA: fresh quality best, browser helper collapsed, guide->settings handoff, both clear buttons and restored focus verified. Current user browser preference, destination and format/network settings match private pre-update backup.
- Three fresh jars without browser import all failed this exact Douyin video via mobile-share fallback. No Cookie values emitted. Chrome Profile 1 metadata identified one empty-name row rejected by prior serializer. Synthetic downstream loader roundtrip proves valid nameless Netscape behavior. Actual Chrome import vs fresh jar comparison still pending.
- Current UI validation blocker: native startup opens protected Downloads session directory and kernel open remains suspended; tccd confirms old AllFiles code requirement mismatch after ad-hoc update. Under prior user authorization old row removed; system app picker located current app but Open remains disabled via automation. User asked to complete adding current app and any OS authentication. No new signing/security workaround attempted.
- Do not claim end-to-end completion. Installed clip UI/export, actual browser A/B and post-binding download remain unchecked. Public evidence/report maintained at /Users/felix/Documents/ChatGPT/个人工具/stacher-comparison-2026-10-18/implementation.html.
