# Product Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the approved usability improvements, quality options and installable native GitHub release.
**Architecture:** Keep SwiftUI and the loopback MeTube service; add a client archive for URL-keyed backend records. Extend the existing native installer to carry the current plugin and supported configuration.
**Tech Stack:** Swift 5/macOS 14+, Python packaging/tests, bash, Colima/Docker/Lima, yt-dlp/FFmpeg.

## Global Constraints

- macOS 14+, Apple Silicon only; preserve clipping behavior and do not run clipping validation.
- Cookie values, private URLs, user history and credentials never enter logs, source or release files.
- Cookie reading remains opt-in and selected-profile only; do not claim logged in based on read success.
- Source quality ceilings 1440/2160 never upscale; MP3 ignores video quality.
- Archived records never remove a newer backend task with the same URL; clearing history preserves files.
- Reuse current feature branch; do not overwrite unrelated local work or runtime components.
- Final package must be checksum/signature checked and downloadable in the existing private repository; signing/notarization limits must be stated accurately.

### Task 1: Download model, archive and failure/health behavior

**Files:** Models.swift, Store.swift, DownloadPolicy.swift, RuntimeSupport.swift, new DownloadArchive.swift and related non-clipping tests/scripts.
**Interfaces:** DownloadItem.id becomes durable per occurrence while url remains backend key. Preserve BackendServing protocol and existing retry/cookie lifecycle. ExportRegistry mapping uses URL+folder already; use an archive marker/source field to separate local records. Quality choice constants should live in DownloadQuality with values/label helpers consumed by UI.
- [ ] Add failing behavioral tests for same URL video then audio preserving both records across reload; removal of archive never removes current backend record; latest same-URL item remains target of retry. Read existing Store and registry before choosing storage.
- [ ] Implement minimal durable archive with Codable records and an injected UserDefaults store; archive terminal snapshots before overwritten backend entries. Preserve older JSON decoding.
- [ ] Add failing quality tests: payload 1440/2160 video accepted, audio remains best, unsupported quality rejected. Define shared labels and values.
- [ ] Add tests for 404/410, empty source formats vs selected format errors, and dependency summary where Deno is available but Node absent. Implement concise distinct classifications and health summary.
- [ ] Handle notice lifecycle after removal/errors; retain session cleanup, uncertain submission and export recovery behavior. Run relevant tests and commit only owned changes. Report commands/results.

### Task 2: Interface and settings

**Files:** MainView.swift, DownloadSettings.swift, QuickStartView.swift, RetryEditor.swift, SubmissionRow.swift; Store settings API if necessary coordinate explicitly.
**Interfaces:** Consume DownloadQuality labels/values from Task 1, DownloadItem.id for selection. Stage browser/options/automatic update edits and save through existing methods only after all drafts validate.
- [ ] Remove mascot button, retain labeled quick input. Use IDs for history selections and canonical URL for backend pending checks.
- [ ] Update quality choices and retry labels consistently; show concise fallback help in picker.
- [ ] Replace separate save buttons with one Save and Close, Cancel preserves saved settings. Avoid partial saved configuration when later validation fails; validate all drafts before mutation and disable dismissal while saving. Folder and maintenance controls explicitly immediate.
- [ ] Shorten website assistance text and move privacy/cleanup to disclosure. Clarify Safari local permissions and one-time bypass. Exclude Kuaishou from supported list; avoid top/recent error duplication.
- [ ] Reduce guide to three steps; show recovery only when service offline. Use runtime summary plus disclosure details. Quick view shows View Tasks instead of referencing a nonexistent list.
- [ ] Build/typecheck and verify UI through accessibility/screenshots without exercising clipping. Commit and report.

### Task 3: Turnkey installer, docs and publication

**Files:** distribution/macos scripts/runtime.env/package_native.py, distribution tests, README.md, Shouxia/README.md, docs/INSTALL-MAC.md, release metadata.
- [ ] Add installer test fixtures for plugin/config delivery and version-derived naming/HEAD manifest. Run to observe missing behavior.
- [ ] Package current built native app, custom Douyin plugin and license information. Install plugin only after validating target, compare deployed bytes; enable per-task overrides on new backend. Existing environment changes must be safe/idempotent and recoverable.
- [ ] Preserve hash verification and recovery ownership; pin current compatible engine; ensure curl_cffi dependency and JS runtime are available before readiness. Keep existing compatible user backend and histories.
- [ ] Rewrite docs with one recommended native installation path, user vs developer requirements, optional browser use, actual sample evidence and platform/signing limitations.
- [ ] Run non-clipping regression suites/build/signature; installer fixture/recovery tests; package verify-only/check; real native backend download/quality smoke without browser data. Keep new artifacts private and delete only own temporary fixtures.
- [ ] Review complete branch, resolve findings, commit/push and open/attach PR. Publish versioned prerelease with checksums and verify GitHub assets/commit. Update release docs to exact URL.
