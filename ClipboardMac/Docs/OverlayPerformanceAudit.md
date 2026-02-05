# Overlay Performance Audit (Horizontal + Vertical)

This document is a structured template to capture repeatable overlay performance measurements.

## Scope

- Horizontal overlay: `OverlayScreenEdge.top/bottom` → `OverlayLayoutAxis.horizontal`
- Vertical overlay: `OverlayScreenEdge.left/right` → `OverlayLayoutAxis.vertical`

Key root entry points:

- Window + hosting: [OverlayWindow.swift](file:///Users/hirchytsdaniil/Developer/Work/Paste/ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/OverlayWindow.swift)
- Root view: [OverlayShellView.swift](file:///Users/hirchytsdaniil/Developer/Work/Paste/ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/Shell/OverlayShellView.swift)
- Content switch: [ItemGridSection.swift](file:///Users/hirchytsdaniil/Developer/Work/Paste/ClipboardMac/Sources/ClipboardMacApp/UI/Overlay/ItemGridSection.swift)

## Instrumentation hooks in this repo

### Signpost category

- Subsystem: `com.paste`
- Category: `Overlay`

### Signposted operations (debug)

- `computeFilteredItems`
- `CachedItemProperties`
- `AttributedString`
- `ThumbnailDecode`
- `PreviewImageDecode`
- `URLBannerDecode`
- `LPMetadataFetch`
- `NSItemProviderImage`

### Debug HUD toggle

- UserDefaults key: `overlayPerfHUD` (bool)
- When enabled, an on-screen HUD shows FPS, avg/worst frame time, resident MB, and top timed operations.

## Capture protocol (repeatable)

Build/run:

- Use **Release** for final numbers; use **Debug** for signpost correlation.
- Disable unrelated background work (sync, scanning) if possible.

Warm-up:

- Open overlay once and close.
- Re-open overlay and wait 2 seconds (warm caches).

Scenarios (run each for ~15s):

1. Idle overlay (no scrolling)
2. Horizontal scroll (trackpad continuous scroll)
3. Vertical scroll (trackpad continuous scroll)
4. Drag reorder (if enabled) + hover pinboard targets
5. Open preview popover and scroll preview text
6. Open filters popover; toggle several chips

## Instruments setup

### Time Profiler

- Record CPU samples during each scenario.
- Filter call tree by:
  - `SwiftUI`
  - `AttributeGraph`
  - `CoreAnimation`
  - `ImageIO`
  - `LinkPresentation`
- Add “Points of Interest” to correlate signposts.

### Metal System Trace

- Capture GPU activity while scrolling and with the preview popover open.
- Extract:
  - Frame time / present time deltas
  - GPU utilization (average + spikes)

### Allocations / VM Tracker

- Capture peak “Resident Size” and transient allocations during preview popover open and fast scroll.

## Component ranking table (fill from traces)

| Rank | Component | File(s) | Avg render time / frame (ms) | FPS impact | CPU % | GPU % | Resident Δ (MB) | Notes |
|---:|---|---|---:|---|---:|---:|---:|---|
| 1 |  |  |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |  |  |

## Per-component signpost summary (optional)

| Operation | Avg (ms) | Max (ms) | Count | Scenario |
|---|---:|---:|---:|---|
| `computeFilteredItems` |  |  |  |  |
| `ThumbnailDecode` |  |  |  |  |
| `AttributedString` |  |  |  |  |
| `URLBannerDecode` |  |  |  |  |

