# Public Showcase Implementation Plan

> **For agentic workers:** Use inline execution for this task; capture actions share one native UI and must remain sequential.

**Goal:** Deliver usable public showcase assets and GitHub presentation settings, with accurate signing readiness.

**Architecture:** Generate a synthetic sample, run the current native sources with isolated runtime paths and a separate MeTube backend, capture real UI through CUA, assemble a local HyperFrames video, and publish checked outputs. Keep credentials on the user's Mac.

**Tech Stack:** SwiftUI / AVFoundation, Docker / MeTube, CUA, HyperFrames, FFmpeg, GitHub CLI.

## Global constraints

- Current native product remains version1.4.1; no unrelated app feature changes.
- Share image1280×640, under1MB; demonstration approximately30seconds,16:9.
- No user history, cookies, accounts or downloaded third-party media in captures.
- Do not grant MIT before the user's explicit choice.
- Do not claim Developer ID notarization or clean-Mac acceptance without actual evidence.

## Tasks

- [x] Pin repository via GitHub UI and save visible proof.
- [x] Generate own sample video, record provenance and create an isolated native capture build / backend.
- [x] Capture real continuous paste, extraction, playback, ratio selection, range preview and successful export; verify resulting media and absence of private data.
- [x] Create branded share image and 40s HyperFrames composition using 503 real UI frames; check, inspect encoded playback, render and verify dimensions / duration.
- [ ] Update README / transcript, social preview and release assets; verify live presentation.
- [x] Inspect signing tools and identities; prepare local signing / notarization workflow plus clean-Mac acceptance document. Apply MIT only after explicit choice.
- [ ] Review targeted changes, validate scripts and media, push / merge checked delivery and report completed items and credential-dependent work separately.

Delivery integration is tracked in GitHub PR6. Social-preview upload, source license choice and live Apple signing remain external conditions documented in docs/VALIDATION-PUBLIC-SHOWCASE.md.
