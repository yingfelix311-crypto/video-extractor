# Clip canvas aspect ratios and custom size

The user requests recognizable aspect ratios (including16:9,21:9,4:3) and explicitly approved BOTH custom ratio and custom pixel width/height. Earlier approval requires preview and export use the same canvas, with source dimensions as default. This is a narrow extension of the existing native editor, preserving its playback/timeline/speed and fitting complete video with black padding.

## Behavior

The picker is labeled 画面比例 and displays 原视频比例,16:9,21:9,4:3,3:2,1:1,9:16,3:4,2:3,4:5,自定义. Pixel dimensions appear separately. Existing preset pixel mappings remain;21:9 is2520×1080,3:2 is1620×1080,2:3 is1080×1620.21:9 is exact, not mislabeled2560×1080.

Custom reveals an inline segmented ratio/pixels mode plus two number fields. Valid input updates preview immediately, no hidden Apply step. Changing modes converts the current valid size; last custom fields survive switching to a preset and back. Invalid input shows one concise reason, retains a bounded source-shaped placeholder and disables preview/export actions that would otherwise use different dimensions. Source/presets ignore unused invalid custom drafts.

Ratio accepts positive finite decimal numbers up to1000 per side and aspect range1:128..128:1. Derive a1080-pixel short edge, constrain the long edge to8192 and total pixels to33,554,432, then round down to even dimensions. Pixel input accepts integers64..8192 with even dimensions and at most33,554,432 pixels. No implicit pixel rounding: explain invalid values. These bounds apply to custom canvas, not the original-source default.

Export captures one validated custom size at save time and checks it again in the exporter. Preview uses the same resolved size. Keep orientation-aware centered fit and black padding, never stretch or silently crop. Preview display zoom remains independent of output pixels.

## Verification and delivery

Meaningful tests cover custom validation/bounds, exact21:9, source orientation, mode conversion, invalid drafts preventing export, and actual short synthetic exports with standard/custom canvases, video/audio and frame geometry. Limit verification to changed canvas behavior, not a full repeat of unrelated clipping features. Build/install with local previous-app backup; publish source/docs and a versioned native patch package under existing GitHub authorization, preserve private visibility and existing signing limitations.
