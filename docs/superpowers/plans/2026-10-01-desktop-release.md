# Video Extractor desktop release implementation plan

> Execute with subagent-driven-development, independently owned files and final review.

**Goal:** Ship approved native macOS UI, click-open compact input, persistent per-task destination, idle-only automatic engine updates, and measured social-platform tests.

**Architecture:** Existing SwiftUI app and MeTube Docker backend retained. Native directory picker captures destination at submission; finished files copied atomically from protected staging folder to selected destination without overwriting existing files. Local task manifest retains exported paths. Update coordinator checks once per day while app is running, defers until backend idle, blocks local new submissions while upgrading, verifies engine and restarts service. Rollback/retry status surfaced.

**Constraints:** Name Video Extractor; #141514/#4C2A71/#ADCF37; Sora/Manrope with Chinese native fallback; zongzi icon; no global hotkey; no browser cookies/login; no fake pause; preserve existing downloads and records. MenuBarExtra label constant and single URL-deduplicated ForEach retained. Desktop test directory contains test outputs/report. Exact platform failures reported, never claim all supported from a single success.

- [x] Native UI: MainView, Theme, TaskRow, ShouxiaApp; register bundled fonts; update resource copying and icon. Menu bar and main-window compact-input button open focused quick panel, configurable format/quality/destination; settings exposes update status.
- [x] Destination: new destination manifest and export utility, Store submit captures destination; refresh exports newly completed owned tasks; safe collision handling and export retry; FileActions uses stored exported paths. Validate with local temporary files and a real app download.
- [x] Updates: new EngineUpdater and command runner; tests for due/idle gating and reporting. Default automatic, daily launch/resume checks, manual action, queue deferral, bounded commands, verified version; no engine service stop during active downloads.
- [x] Integration: compile/test/install under ~/Applications and Desktop symlink; native UI screenshot and quick panel interactions verified.
- [x] Live test: create Desktop/Video Extractor测试-2026-10-01; use public links from YouTube/Bilibili/Douyin/X/Instagram/TikTok; constrain size/duration, retain metadata/log and real video outputs where successful; verify downloaded media not just extracted metadata. Actual YouTube/Bilibili/TikTok/X files validate the save pipeline; Instagram/Douyin failures retained.
- [x] Final review: inspect full diff for cancellation, queue races, file destination safety, regressions and UI state; resolve material findings; record final report and test limitations.
