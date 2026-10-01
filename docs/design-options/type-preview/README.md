# Interactive design preview

Run `bash run.sh` from this directory, then visit http://127.0.0.1:8766/type-preview/ . macOS with Swift command-line tools and Python3 required. This replaces the original static server on port8766.

Current design: Sora + Manrope (Colorion Digital First pairing), PingFang SC for Chinese; #141514 / #4C2A71 / #ADCF37. Mascot edited with built-in imagegen from the approved bean character into a triangular bamboo-leaf zongzi hugging the same video tile. Original bean asset retained.

User comments implemented:
- Removed platform-list hint.
- Replaced native select with styled keyboard-operable listbox, click-away/Escape dismissal, selected state; audio disables video quality.
- Added native NSOpenPanel directory selection. Preview selection persists in ignored `.destination.json`; cancel leaves it unchanged. Same-origin local bridge, one picker at a time. The directory picker uses normal app initialization before displaying its panel.
- Zongzi image replaces preview mascot.

Verified 2026-10-01 using actual browser/native UI: keyboard1080p→720p and focus return; menu appearance; audio disables and video reenables quality; Cancel preserves directory; selecting MeTube returns full path and persists through reload. JS syntax and Python compile checks pass; Swift helper builds and runs.

Scope: frontend interaction preview only. It does NOT submit downloads, move media, or change installed Video Extractor settings. Native downloader still uses Downloads/MeTube. Production integration must route newly submitted downloads to their captured destination and preserve old task file locations; the prototype's persisted selection is not that implementation.
