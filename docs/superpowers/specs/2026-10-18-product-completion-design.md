# Product completion: approved audit improvements and installation

The user approved implementing the eleven findings in the 2026-10-18 non-clipping audit, then requested 2K/4K extraction and publishing the complete product to the existing GitHub repository. This specification records that approved direction. Keep the native macOS product; do not replace it with the separate Electron prototype. Keep existing clipping behavior and do not run clipping validation.

## Product behavior

- One labeled quick-input entry; mascot is decorative. Quick input links to the task window. Success notices disappear when their task disappears or a new error supersedes them.
- Quality choices: best, 2160 (4K), 1440 (2K), 1080, 720, 480. They select available source formats at or below the ceiling, never upscale. MP3 disables video quality. Main/quick/retry use the same labels and values. Preserve backward compatibility with saved values.
- Preserve separate finished video/audio downloads of the same URL using durable local task identities. URL remains the backend operation key; archived records must not delete a newer backend record. Preserve export file mapping and recover after restart. Removing history keeps media files.
- Settings have one Save and Close action for browser/format/network/update preferences, with Cancel discarding draft edits. Immediate maintenance actions are clearly separate. Display a concise browser role/source explanation and collapse privacy/maintenance details. A source selection reads only that browser profile; it is unrelated to where a URL was copied or the system default browser.
- Start guide: paste link, choose save folder, extract/open result. Show service recovery only when unavailable. Runtime summary is ready if required tools and either Deno or Node exist; missing optional Node is not an error.
- Failure titles remain simple. 404/410 indicate unavailable video; no-source-formats differs from requested-format mismatch. Local Safari failure offers system settings or one-time retry without browser information, with no duplicated long reason. Do not infer login from Cookie rows.
- Platform documentation reports actual sample evidence. Kuaishou is currently unsupported by the shipped extractor; a Cookie source list must not claim it is supported. Do not promise a new extractor without validation.

## Distribution

Integrate existing native distribution scripts with the current application. Fixed official runtime dependencies and backend image; include the custom Douyin plugin, verify deployment and enable per-task overrides. Installer prepares dependencies and service before copying/opening the app, can retry safely, preserves user data and conflicting environments. First installation requires internet. End users do not manually install Python/Node/Docker/Homebrew. macOS 14+, Apple Silicon only. Ad-hoc signature is not Apple notarization; document the real limitation. Never disable OS protections.

The release name/version derives from Info.plist and sourceCommit from HEAD. Include checksums, licenses, installation steps, development dependencies, browser setup, tested sample matrix and troubleshooting. Publish source and versioned installer to yingfelix311-crypto/video-extractor, retain privacy. No cookies, keys, user history, private preferences, VM disk or downloaded media enter the repository/package.

## Validation

Meaningful regression tests for quality payload, history identity/lifecycle, failure classification, dependency summary and installer recovery. Build native app and verify signature/package integrity. Exercise real local video/audio downloads and 1440/2160 selection with the installed backend. Do not rerun the full eight-platform matrix already completed. Validate clean installation mechanics with isolated fixtures; clearly distinguish this from an unperformed physical clean-Mac installation. Review implementation before publishing and verify remote commit/assets.
