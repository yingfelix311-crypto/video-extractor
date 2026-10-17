# Short-video Completeness Implementation Plan

> Execute in this session; the user authorized the preceding audit recommendations. Use focused implementation and review agents, preserve current native product.

**Goal:** Complete the eight audited gaps, network/header controls and dependency diagnostics without replacing the app.
**Architecture:** Pure Foundation link/options/diagnostic models; injectable HTTP backend; main-actor store for durable submissions; SwiftUI controls; optional transactional local Docker integration.
**Tech Stack:** Swift 5 app, Swift 6 core tests, SwiftUI/AppKit, MeTube HTTP, Docker/Colima.

## Global Constraints
- Preserve user downloads, history, export registry and native clip editor.
- Do not read browser cookies or log credentials; cookie files only from explicit file selection.
- Keep service bound to 127.0.0.1:8081; network parameters must not cause shell interpolation.
- No fake download success: verify API, file bytes, installed bundle and UI.

## Tasks
- [ ] 1. Models: tests first for Douyin modal ID canonicalization, invalid/ambiguous values, foreign domains, original link preservation, any/MP4 format policy, failure categories, separate media/status filtering. Implement pure models. Core tests red then green.
- [ ] 2. Backend: injectable URLSession/baseURL; Cookie status/upload/delete, Netscape validation/size limit, version/cancel-add, structured HTTP errors. URLProtocol integration tests exercise exact requests and cancellation. Add transactional optional loopback-only backend override setup with preservation and rollback tests.
- [ ] 3. Store: persistent operation IDs/folders and submit intent; immediate stages, reconciliation on timeout/cancel/startup, cancel-add, corrected retry with selected parameters/destination, mutation gates, settings/diagnostics. Exercise race boundaries with HTTP stub tests.
- [ ] 4. UI: separate task filters, failed count, optimistic operation row/cancel, original/canonical diagnostics, retry editor, cookie import/remove/status, proxy/header inputs and backend diagnostics. Quick input keeps success state and explicit choices. Preserve established theme and clip UI.
- [ ] 5. Verify core/store/clip/timeline/updater, broad diff review, build and backup installed bundle, install updated native app, inspect main/settings/error flows, actual public media save. Write concise release notes with remaining platform conditions.
