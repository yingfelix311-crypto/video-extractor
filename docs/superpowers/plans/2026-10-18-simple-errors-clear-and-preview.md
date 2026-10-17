# Simple errors, visible clear and preview zoom plan

> Continue the authorized current-session implementation on codex/short-video-completeness. Use one integrated UX change and one independent code review. Do not perform further clip verification or export experiments per user request.

**Goal:** Make failures readable, drafts easy to clear and the clip preview continuously resizable.

**Architecture:** Keep raw failure data internally while presenting one concise classified title. Share the visible clear control across main and quick inputs. Bound preview display height using current viewport and canvas geometry; retain export settings.

**Tech Stack:** SwiftUI/AppKit, existing Swift core tests and native build.

## Global Constraints

- No Cookie values or signed media URLs in reports; no login inference.
- Clear only drafts, never downloads/options/destination.
- Preview scale changes display size only, retains aspect and output canvas.
- No further clip verification/export experiments; compile changes only.
- Preserve existing prefs/media/history and use current authorized branch.

## Steps

- [x] Update existing CoreTests with concise extractor/403/local-reader expected reasons; run test.sh and observe old behavior fail.
- [x] DownloadPolicy.swift: classify precise short reasons. SubmissionRow.swift: render title only, no raw/long guidance; failed browser read must not auto-open settings in Store.swift. TaskRow.swift: concise save failure. MainView.swift: suppress duplicate visible row/banner errors.
- [x] MainView.swift: shared ClearLinkButton, always-visible disabled-empty control, clear+focus callback. Main TextField handles Esc; QuickPanel Esc clears nonempty text and only hides when empty. Use same control in RetryEditor.swift for editable retry URL.
- [x] ClipEditor.swift: wrap viewport GeometryReader; retain canvas fit geometry, add bounded height state and slider/-/+/fit. Keep export/model untouched; concise clip error display only. Do not invoke clip tests or export.
- [x] Run core and submission/session/store tests relevant to presentation/routing. Typecheck/build all native sources, no clipping tests. Read-only code review for regressions.
- [x] Back up 1.3.0, install 1.3.1 (6), verify visible clear and Esc in main/quick using dummy unsent text; preserve task/user prefs. Update evidence/report to actual completed A/B and current UI behavior, with clip changes marked compiled only.

## Completion record

- Core test proved RED for old generic extractor wording, then GREEN for precise short reasons including 403, local browser read and missing backend configuration.
- Browser-session, submission and store suites passed; local reader failure asserts settings do not open automatically. Native full typecheck and optimized build passed. Independent review approved after early configuration guards also stopped auto-opening settings.
- Installed 1.3.1 (6); main/quick visible clear, button clear+focus, Esc clear and quick empty-Esc close observed. Invalid unsent input displayed only “链接格式不正确”, no detail disclosure or settings sheet. Cleared test draft/banner afterward. Retry uses same component and is compiled/reviewed.
- User preference comparisons for destination, quality, media mode, browser selection and format/network settings all unchanged. No further clip verification/export experiments performed after user stopped them; preview implementation is compiled/reviewed only.
- Updated quick-start and retry instructions to match simple failures and new preview sizing; no obsolete “expand original error” guidance remains in normal views.
