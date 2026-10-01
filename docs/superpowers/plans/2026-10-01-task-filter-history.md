# Task filtering and history management

Approved design: Video/audio tabs filter all task states; management mode selects terminal history, supports select-all in current view, deletes records without files; selection clears on category changes.

- [x] Add regression coverage for backend download_type, legacy filename/format fallback, mixed-category/status filtering, and safe bulk deletion payload.
- [x] Decode media metadata in Models.swift and share filtering policy with MainView and TaskRow.
- [x] Add guarded bulk record removal in Store.swift; retain records on API failure and protect active exports.
- [x] Add selection controls and contextual empty states in MainView.swift.
- [x] Run core/live tests, build and install the app, and inspect the updated interface.

Additional approved change: compact 320pt two-row quick panel, preserving existing theme and download preferences. Native preview approved by user.
