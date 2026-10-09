# Native Mac Distribution Implementation Plan

> **For agentic workers:** Execute inline; user approved original Mac distribution and cancelled Windows.

**Goal:** Publish the exact native app with first-time backend setup and a private GitHub download entry.
**Architecture:** Keep all Shouxia sources unchanged. Add only distribution scripts and documentation.
**Tech Stack:** SwiftUI/AVFoundation/MeTube unchanged; bash installer; Python packaging verification for developers.

- [x] Test required non-mutating setup plan and existing-environment conflict handling before implementation.
- [x] Implement Mac-only setup/check scripts with fixed runtime manifest, no history import or subscriptions, no overwrite of existing runtime tools.
- [x] Package the currently installed native app and required runtime files; compare every source bundle file and include dependency licenses/checksums.
- [x] Update native README and install notes; private Releases download entry. Close the abandoned Electron PR without merging it.
- [x] Run syntax, installer tests, native tests, bundle comparison and backend health checks. State clean-Mac and signing limitations.
- [ ] Commit/push a native-only branch, review, integrate docs/distribution and publish a private prerelease.

Validation: 11 installer tests pass, including interrupted initialization retry and existing-user-container preservation. Original native tests and source typecheck pass. All 15 installed app files match exactly; archive checksums, ZIP integrity and read-only backend check pass. Review found no remaining blockers. Clean-Mac first installation is pending and disclosed in prerelease instructions.
