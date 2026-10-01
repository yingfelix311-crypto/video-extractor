# 收下 / Shouxia desktop v1
User authorized development after cross-platform research. Native SwiftUI macOS app, arm64, local MeTube backend. Main window plus menu-bar popover. No cloud service or subscriptions.

Visual direction: a compact editorial media instrument. Paper background, ink header, acid-mint active accent. A bold Chinese title, compact aligned task rows, measured numbers; no giant video hero or decorative gray gradients. Native SF Symbols with consistent weight. Paste/drop is the authored transition, expanding the input tray into a real task row. Respect reduced motion.

Main surface: title and connection status, URL entry and paste action, quality and video/audio choices, primary download action; live task queue; recent completed files with open, Finder reveal and drag-out. Error messages are inline with retry. User can inspect raw error details. Empty state teaches paste/drop. No fake data in production.

Backend: auto-start existing Colima profile metube and container when offline; poll history. Cancel active download, retry failed, start pending, remove history without deleting files. Unsupported pause omitted. Native file actions restricted to download root. No automatic clipboard inspection or cookie extraction.

App lifecycle: closing window keeps menu-bar access; quitting app leaves ongoing downloads running, explicitly described. Backend can be stopped with existing desktop launcher. v1 reuses installed runtime; not a standalone distributable for other computers.

Validation: Swift unit-style executable tests for URL parsing, paths and API decoding; compile release app; actual UI inspection and a real download from a public W3C sample video to avoid changing existing user records. Install to ~/Applications/收下.app, desktop alias/link, launch and verify.
