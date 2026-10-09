# Standalone macOS and Windows installers

User approved standalone packages for others to install. Existing SwiftUI source remains available; a shared Electron distribution retains the dark purple/chartreuse product style and removes dependence on the developer's Docker environment.

Targets: macOS 14+ arm64 DMG and Windows 10/11 x64 per-user NSIS installer. Bundle pinned yt-dlp, ffmpeg, ffprobe and a JS runtime provided by Electron; include upstream licenses. No cookies or existing download history shipped.

1. Write behavior tests for link validation, download/clip arguments, persistence, safe output creation, cancellation and removal; verify failures before implementation.
2. Implement isolated native IPC, direct subprocess execution, portable engine provisioning, persisted download state and serial clip export. Preserve originals and reject overwrites. No shell interpolation, subscriptions or background extraction.
3. Create theme-consistent download and clip views, double range handles, custom 0.25–2x rate, native folders/file dialogs, errors, cancellation, explicit file deletion and recovery messages. Previews use limited local file access.
4. Verify with synthetic short media, test process restart state, inspect UI in Electron and create Mac DMG. Use GitHub Actions on Windows for installer build and packaged self-tests; obtain Windows artifact and record exact validation limits.
5. Document install requirements, unsigned beta limitations and dependency versions. Keep installer artifacts outside source and release publication separate from build.

Verification uses synthetic short low-resolution media, no live video downloads unless needed for bounded validation, no lengthy benchmarks or AI models. Code signing credentials are unavailable; packages are beta builds, not notarized production releases.
