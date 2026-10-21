# Runtime dependencies and licensing

The native application uses Apple's SwiftUI, AppKit and AVFoundation frameworks plus system SQLite/Security. Sora and Manrope font license files are included in the app's Resources/Fonts directory.

The installer carries only runtime programs/resources, not an existing user environment:

| Component | Pinned version | Role | Upstream / license |
| --- | --- | --- | --- |
| Colima | 0.10.3 | Local Linux VM management | https://github.com/abiosoft/colima · MIT (included) |
| Docker CLI | 29.8.2 | Local Docker engine control | https://github.com/docker/cli · Apache-2.0 (included) |
| Lima | 2.2.0 | macOS virtual machine runtime/resources | https://github.com/lima-vm/lima · Apache-2.0 (included); Lima's distributed resources retain their upstream notices |

Downloaded during the first installation:

- MeTube container: digest pinned in `distribution/macos/runtime.env`, from https://github.com/alexta69/metube. Source and licensing for the image and included components are available from that upstream project. The installer does not distribute a modified image or copy the author's existing container.
- yt-dlp: `2026.10.10.233141.dev0` from PyPI; runtime reports `2026.10.10.233141`. Upstream: https://github.com/yt-dlp/yt-dlp (Unlicense; third-party dependencies have separate licenses). Engine updates may subsequently change this version.
- FFmpeg / ffprobe, Python, a JavaScript runtime (Deno or Node), curl_cffi and its TLS dependencies are supplied by the fixed MeTube image. They are checked before installing the client. The custom Douyin plugin requires the `chrome-131:android-14` impersonation target. No host Python/Node/FFmpeg is installed.
- Linux base VM image is downloaded by the pinned Lima/Colima runtime; its upstream component notices apply.

The release manifest records hashes of all bundled files and the exact source commit. Checksums verify package integrity, not developer identity; the application has an ad-hoc signature and is not notarized.

`desktop/` has a separate dependency/license set and is not included in this native release.

The Lima `lima` shell wrapper is vendored from `lima-vm/lima` tag `v2.2.0`, `cmd/lima`, with its Apache-2.0 SPDX notice. Its SHA256 is `88aeac60dbcb69ec675c0ce9af24d5f66255f4899fa73320402db57925500832`. Both `lima` and `limactl` are required by Colima and are included in the embedded backend installer.
