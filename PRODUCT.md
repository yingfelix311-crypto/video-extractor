# Product

<!-- impeccable:product-schema 1 -->

## Platform
macOS desktop, native SwiftUI + AppKit, Apple Silicon

## Users
Felix, an AI product manager using an Apple Silicon Mac. The app is currently for personal local use.

## Product Purpose
Save online videos to the Mac through a refined independent desktop app, with a main window and a menu-bar quick entry.

## Capabilities and Constraints
The user accepted the proposed compact download tool plus menu-bar entry. Primary flow: paste or drop a video page URL, inspect the video and quality choice, download, then open or locate the file. Proposed interactions to explore: inline link-to-preview transition, progress in the action area, dragging a completed file out.
Existing backend: locally installed MeTube using Colima and Docker; localhost port 8081. Downloads go to /Users/felix/Downloads/MeTube. One YouTube video has been downloaded and inspected successfully. Bilibili, Douyin and Twitter compatibility is not verified.
The user wants no extra paid service. First launch and background-service lifecycle should be designed as part of the app. Details remain open.

## Brand Commitments
High visual quality and inventive but understandable controls and interactions. First implemented direction: 收下, paper-white body, deep ink-green header, mint accent, Chinese interface.

## Evidence on Hand
Existing download: Shiro｜GOLDEN NAME｜Music Video.mp4, 360p, 135.58 seconds, approximately 8.7 MB. Future mockup content must be labeled illustrative.

## Open Decisions
First working build installed at ~/Applications/收下.app. Window and menu-bar quick entry; closing the window keeps the app running. Quitting the app leaves the MeTube backend running. This build reuses the local Colima environment; portable distribution and per-platform login flows remain future work.
