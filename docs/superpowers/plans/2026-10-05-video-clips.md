# Video clip first version

Implement the user-approved native clip workflow, retaining Ink, TypeStyle and SoftButtonStyle. No AI, background analysis or automatic batch encoding.

1. Add range parsing/validation tests, then ClipRange and a single-export AVFoundation service. Export MP4 to a private temporary file in the selected destination, then move without overwriting. Support cancellation and remove temporary output on failure.
2. Add a dedicated window with AVPlayer preview, start/end fields, current-position markers, duration, selected-range playback, save panel, progress and explicit errors. Release playback observers on close; confirm cancellation before closing during export.
3. Add completed-video and File-menu entry points, with local-file recovery when the source moved.
4. Run range and existing regression tests, build, and do one bounded short export with frame/duration/audio validation. Inspect the UI and install locally. Initial delivery was local; the user subsequently requested a GitHub sync.

## Accepted refinements

- One playback toggle follows AVPlayer state.
- Two draggable timeline handles select the highlighted export range; numeric fields remain available.
- Custom 0.25–2x speed applies to preview and export; the UI shows predicted output duration.
- Export scales both media tracks and retains video orientation.
- Verified range boundaries, cancellation, no overwrite, and 0.5x / 1.35x / 2x exports with synthetic short media.
- Repository presentation uses the existing palette, an illustrative SVG cover and a rendered timeline component.
