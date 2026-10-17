# Douyin Share Fallback Implementation Plan

> Execute inline with executing-plans; this is the already requested Douyin download bug fix.

**Goal:** Download the user's Douyin video using their automatically scoped Safari session.

**Architecture:** Preserve upstream DouyinIE; add a bounded mobile-share fallback through the official yt-dlp plugin interface. Deploy backend-only so the installed native application keeps its current FDA identity.

**Tech Stack:** Python 3.14, yt-dlp 2026.10.10.233141, installed curl_cffi, existing MeTube container.

## Global Constraints

- No Cookie values in output, reports, fixtures, or source.
- No native rebuild or signing changes.
- Exact target video ID and http(s) media URLs only; no copied authentication cookies to CDN.
- Existing queues and download history remain intact. Restart only while idle.

## Task 1: Parser and plugin

Files: `Shouxia/BackendPlugins/yt_dlp_plugins/extractor/shouxia_douyin.py`, `Shouxia/BackendPlugins/tests/test_douyin_share.py`.

- [x] Write fixture-based tests against a pass-through subclass, run in the real container, and observe the missing fallback fail.
- [x] Parse the `window._ROUTER_DATA` JSON assignment with a JSON decoder, select `loaderData['video_(id)/page'].videoInfoRes.item_list` by exact aweme_id, build formats from play_addr and bit_rate addresses without forwarding sid_tt.
- [x] Catch only the upstream Fresh cookies extraction error; fetch `https://www.iesdouyin.com/share/video/{id}/` with mobile User-Agent, normal Referer, and available Chrome Android impersonation; retain downloader-scoped cookie jar.
- [x] Run tests covering successful upstream, fallback, wrong ID, malformed JSON, missing video, non-http URLs, partial metadata, and non-Cookie upstream errors.

## Task 2: Deploy and verify

Files: `Shouxia/install-backend-plugins.sh`, `Shouxia/README.md`, diagnosis and validation artifacts.

- [x] Copy only plugin code to `/downloads/.shouxia/yt-dlp-plugins/`; expose through `/etc/yt-dlp/plugins/shouxia` symlink. Confirm fresh Python plugin discovery before service restart.
- [x] Check queue/pending empty, restart existing metube container, verify loopback HTTP readiness and effective plugin.
- [x] Retry the provided share link through the native UI (share-text URL extraction was established in the original failure). Confirm complete status and ffprobe duration plus audio/video streams. Keep resulting video in the selected destination.
- [x] Record exact result and deployment limitation; verify native binary digest and that per-task Cookie files are cleaned.
