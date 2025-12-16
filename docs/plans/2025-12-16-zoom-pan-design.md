# Zoom/Pan Camera Design

A viewport camera for zooming into and panning around the simulation without affecting entity behavior.

## Core Behavior

### Zoom
- Scroll wheel zooms toward mouse cursor position
- Range: 1x (default floor) to 10x (ceiling)
- Instant response, no animation
- Esc or Space resets to 1x and clears pan offset

### Pan
- Any mouse button (left/middle/right) + drag pans the viewport
- Only available when zoom > 1x
- Bounded to simulation area - cannot pan into empty space

### UI
- Display current zoom level in existing panel under render info (e.g., `zoom: 2.3x`)

## Implementation Approach

### State
New camera state in `sandbox_main.zig`:
```zig
var zoom: f32 = 1.0;
var pan: @Vector(2, f32) = .{ 0, 0 };
```

### Shader Changes
Modify `entity.vert` to accept `zoom` and `pan` uniforms:
- Apply pan offset before converting to NDC
- Scale by zoom factor
- Scale quad size by zoom so entities appear larger

### Input Handling
- `getMouseWheelMove()` adjusts zoom (clamped 1.0–10.0)
- Zoom-toward-cursor: adjust pan to keep point under cursor stationary
- Mouse drag (any button) adjusts pan with bounds checking
- Esc/Space resets zoom to 1.0 and pan to (0, 0)

### Zoom-Toward-Cursor Math
When zooming from `oldZoom` to `newZoom` with cursor at `mousePos`:
```
worldMousePos = (mousePos / oldZoom) + pan
newPan = worldMousePos - (mousePos / newZoom)
```

### Pan Bounds
Constrain pan so viewport stays within simulation area:
```
maxPan = simulationSize - (screenSize / zoom)
pan = clamp(pan, 0, maxPan)
```
