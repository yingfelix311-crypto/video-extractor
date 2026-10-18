# Clip Aspect Ratios Implementation Plan

> **For agentic workers:** Execute the three bounded tasks in order with focused tests and final review.

**Goal:** Add recognizable preset ratios and custom ratio/pixel dimensions with matching preview/export.
**Architecture:** Keep ClipCanvas raw enum; add a standalone validated custom dimension helper, use one model resolution path, pass an immutable size snapshot to ClipExporter.
**Tech Stack:** Swift5, SwiftUI, AVFoundation, CoreGraphics, existing native packager.

## Global Constraints

- Preserve source-size default and orientation-aware full-image fit with black padding.
- Presets16:9,21:9,4:3,3:2,1:1,9:16,3:4,2:3,4:5; ratio labels separate from pixel dimensions.
- Custom ratio and pixels both supported; even pixel edges64..8192, area<=33,554,432; ratio decimal inputs positive<=1000, aspect1:128..128:1.
- Invalid custom drafts block export; preview/export use one validated canvas snapshot.
- No changes to downloading/Cookie setup and no full unrelated clip regression. Preserve user files/preferences.
- Reuse current checkout on codex/clip-aspect-ratios, existing repository authorization applies to source/patch release; do not alter existing published1.4.0 assets.

### Task1: Canvas resolution and exporter

**Files:** ClipCanvas.swift, ClipExporter.swift, ClipCanvasTests.swift, new focused canvas test runner.
- [ ] Add failing tests for21:9, customratio5:4/2.35:1/vertical, custompixels1280×1024, malformed/out-of-range/odd/oversize input; run to observe missing behavior.
- [ ] Add presets and ClipCustomCanvas parsing/validation. Existing size(for:) remains for presets; custom explicit pixel size supplied by model/exporter.
- [ ] Extend exporter with optional customSize captured by caller, require a validated size for.custom, keep existing source path and fit transform.
- [ ] Adapt legacy preset loops to exclude.custom, add a focused actual-export test for21:9/custompixels/customratio/source with synthetic audio video; verify render size and content bounds.

### Task2: Editor control

**Files:** ClipEditor.swift, new focused model test.
- [ ] Add model custom mode/texts, one resolvedCanvasSize property, concise validation error and mode conversion preserving current ratio/size. Test invalid-draft export readiness and orientation/source preservation.
- [ ] Change picker toratio labels; add inline custom mode/number fields only when selected, accessible labels, disabled during loading/exporting. Show output pixel dimensions separately.
- [ ] Resolve once for preview and snapshot for export; disable export for invalid custom fields. Preserve preview zoom.
- [ ] Build/typecheck, inspect UI if Mac available, report actual verification limit if locked.

### Task3: Integration and release

**Files:** Info.plist, README.md, Shouxia/README.md, docs/INSTALL-MAC.md, validation note.
- [ ] Review code and tests, fix findings, run focused canvas/model/export checks and build.
- [ ] Bump1.4.1/build8; update install docs/version links and ratio controls. Backup/install native build without changing user preferences.
- [ ] Commit/push PR, attach, run nativeCI and merge. Package correct source commit/app, checksums, licenses/plugin, test verify-only/check. Publish new private prerelease and verify remote SHA/tag/assets.
