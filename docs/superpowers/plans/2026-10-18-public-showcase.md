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

- [ ] Pin repository via GitHub UI and save visible proof.
- [ ] Generate own sample video, record provenance and create an isolated native capture build / backend.
- [ ] Capture paste, extraction and clip / custom-ratio states; verify real resulting media and absence of private data.
- [ ] Create branded share image and approximately30s HyperFrames composition; check, inspect contact sheet, render and verify dimensions / duration.
- [ ] Update README / transcript, social preview and release assets; verify live presentation.
- [ ] Inspect signing tools and identities; prepare local signing / notarization workflow plus clean-Mac acceptance document. Apply MIT only after explicit choice.
- [ ] Review targeted changes, validate scripts and media, push / merge checked delivery and report completed items and credential-dependent work separately.
