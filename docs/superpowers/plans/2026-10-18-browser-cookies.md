# Browser Cookie Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Let an opted-in user reuse browser sessions automatically for supported video platforms.

**Architecture:** Native Swift browser readers filter website cookies; per-request private files in the verified MeTube download mount isolate concurrent downloads. Store owns synchronization, cancellation, durable identity and cleanup. SwiftUI settings remember the selected browser/profile without storing cookie values.

**Tech Stack:** Swift 5/macOS 14, SwiftUI, SQLite3, Security, CommonCrypto, CryptoKit; existing MeTube/yt-dlp options overrides.

## Global Constraints

- Keep existing app appearance, manual Netscape import, downloads, exports, clipping and engine updates.
- No dependency on Stacher, new browser extension, cloud service or external helper installation.
- Browser reading is opt-in; system authorization is never bypassed. No real browser credentials in development tests or logs.
- Support Chrome, Edge, Firefox standard profiles and Safari default store. Allowlist platform domains; no similar-domain matching.
- Per-request 0600 cookies in a 0700 directory, verified local bind mount and loopback backend; reject symlinks and arbitrary paths.
- Fresh reading on every retry. Cleanup only after confirmed terminal state. Cookie values never enter settings, logs or request bodies.

### Task 1: Native scoped readers

**Files:** Create `Shouxia/Sources/BrowserCookies.swift`, `BrowserCookieReader.swift`, `Shouxia/Tests/BrowserCookieTests.swift`, `Shouxia/test-browser-cookies.sh`.

**Interfaces:** `BrowserKind: String, Codable, CaseIterable, Identifiable, Sendable` cases chrome/edge/firefox/safari with title. `BrowserProfile: Identifiable, Equatable, Sendable` properties browser, directory, name. `CookieScope.forURL(_ text:String)->CookieScope?`, name/domains/contains(domain:). `SessionCookie` properties domain/name/value/path/expires(Int64, 0=session)/secure/httpOnly. `BrowserCookieReading: Sendable { func read(browser:BrowserKind,profile:String,scope:CookieScope) async throws -> [SessionCookie] }`. `NativeBrowserCookieReader.profiles(for:home:) throws -> [BrowserProfile]`. `BrowserCookieJar.netscape(_:scope:now:) throws -> Data` excludes expired or foreign rows.

- [ ] Add red fixtures for domain boundaries, profile traversal, expiry, Netscape injection, Firefox SQLite, Chrome encrypted v10 and host digest, Safari binary truncation/valid page. Run `bash Shouxia/test-browser-cookies.sh` to see the missing feature fail.
- [ ] Implement read-only SQLite targeted domain queries, profile discovery, lazy scoped Chrome/Edge keychain access, PBKDF2/AES and Safari parsing with strict offsets. Use synthetic encryption fixture and injectable key provider rather than real keychain secrets.
- [ ] Run tests; compile with `-lsqlite3 -framework Security` and report limits. Commit owned files. Task review checks correctness and isolation.

### Task 2: Isolated files and Store synchronization

**Files:** Create `Shouxia/Sources/TaskCookies.swift`, `Shouxia/Sources/BrowserSessionStore.swift`, `Shouxia/Tests/BrowserSessionTests.swift`, `Shouxia/test-browser-session.sh`; modify Store.swift, Models.swift, Submission.swift, RuntimeSupport.swift and affected test scripts.

**Interfaces:** `BrowserCookiePreferences: Codable, Equatable` enabled/browser/profile. Store published preferences, profiles/status; `saveBrowserCookies(_:) async`, `reloadBrowserProfiles(_:)`, `openBrowserLogin(_:)`. Request body accepts optional internally generated `cookieFile:String?`; only `/downloads/.video-extractor-sessions/<UUID>/cookies.txt` accepted. Task file coordinator verifies mount and exposure, creates/cleans request files. Readers injected in Store initializer.

- [ ] Write failing request and Store tests: disabled/foreign scopes make zero reads, enabled expected profile generates isolated file/path, no cookies retains manual mode, permission failure makes zero adds, sync cancellation makes zero cancel-adds, interrupted local sync restores safe failure, unknown backend results preserve cookie file.
- [ ] Implement private path creation and cleanup keyed to request folder UUID. Validate actual Docker bind /downloads source before writing. Enable existing overrides only from idle settings save. Add `.syncing` state and local cancellation before add; retain cancellation/uncertainty rules after add.
- [ ] Run `test-browser-session.sh`, `test-submissions.sh`, `test-backend.sh`, `test-runtime.sh`, `test-store.sh`; preserve existing initializers via defaults. Commit and review.

### Task 3: Native settings and recovery UX

**Files:** Modify DownloadSettings.swift, SubmissionRow.swift, RetryEditor.swift, DownloadPolicy.swift; modify build.sh, Info.plist, README.md.

- [ ] Add settings toggle, browser/profile pickers, save and local-only scope explanation, recent synchronization result, open selected browser and macOS privacy settings. Follow existing tokens and layout; active UI can scroll.
- [ ] Show syncing stage, cancel synchronization action, corrected cookie failure/retry copy. Keep file import and removal distinct from automatic reading.
- [ ] Build/typecheck, inspect actual native settings and failure states; verify choices persist and disabled state doesn't read cookies. Set version 1.2.0/build 3 after checks.

### Task 4: Final verification and install

- [ ] Run all existing 8 shell suites plus two new suites, `bash Shouxia/build.sh`, strict codesign verify.
- [ ] Real backend test with synthetic `.example.invalid` cookies and public video confirms isolated cookiefile opts and exact downloaded bytes; remove only test artifacts. Do not pull actual browser credentials.
- [ ] Independent broad review; fix meaningful defects and run covering checks. Back up installed 1.1.0, install 1.2.0, inspect UI. Save validation evidence and update comparison implementation report.
