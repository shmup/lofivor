# Zoom/Pan Camera Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add viewport zoom (scroll wheel toward cursor) and pan (any mouse drag when zoomed) to observe the simulation up close.

**Architecture:** Camera state (zoom, pan) lives in sandbox_main.zig. Passed to shader as uniforms. All rendering paths use the same camera state, but only SSBO path gets shader-based zoom (others would need separate work).

**Tech Stack:** Zig, raylib, GLSL 430

---

### Task 1: Add camera state and shader uniforms

**Files:**
- Modify: `src/sandbox_main.zig:266` (add state after `var paused`)
- Modify: `src/ssbo_renderer.zig:20-21` (add uniform locations to struct)
- Modify: `src/ssbo_renderer.zig:54-62` (get uniform locations in init)
- Modify: `src/ssbo_renderer.zig:154-156` (pass uniforms in render)

**Step 1: Add camera state to sandbox_main.zig**

After line 266 (`var paused = false;`), add:

```zig
// camera state for zoom/pan
var zoom: f32 = 1.0;
var pan = @Vector(2, f32){ 0, 0 };
```

**Step 2: Add uniform locations to SsboRenderer struct**

In `src/ssbo_renderer.zig`, add to struct fields after line 21 (`circle_texture_loc`):

```zig
zoom_loc: i32,
pan_loc: i32,
```

**Step 3: Get uniform locations in init**

After line 55 (`const circle_texture_loc = ...`), add:

```zig
const zoom_loc = rl.gl.rlGetLocationUniform(shader_id, "zoom");
const pan_loc = rl.gl.rlGetLocationUniform(shader_id, "pan");
```

**Step 4: Add fields to return struct**

In the return statement (around line 112), add:

```zig
.zoom_loc = zoom_loc,
.pan_loc = pan_loc,
```

**Step 5: Pass uniforms in render method**

Change render signature to accept zoom/pan:

```zig
pub fn render(self: *SsboRenderer, entities: *const sandbox.Entities, zoom: f32, pan: @Vector(2, f32)) void {
```

After line 156 (setting screenSize uniform), add:

```zig
// set zoom uniform
rl.gl.rlSetUniform(self.zoom_loc, &zoom, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_float), 1);

// set pan uniform
const pan_arr = [2]f32{ pan[0], pan[1] };
rl.gl.rlSetUniform(self.pan_loc, &pan_arr, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_vec2), 1);
```

**Step 6: Update render call in sandbox_main.zig**

Change line 336 from:

```zig
ssbo_renderer.?.render(&entities);
```

To:

```zig
ssbo_renderer.?.render(&entities, zoom, pan);
```

**Step 7: Build and verify compiles**

Run: `zig build`

Expected: Compiles with no errors (shader won't use uniforms yet, but that's fine)

---

### Task 2: Update vertex shader for zoom/pan

**Files:**
- Modify: `src/shaders/entity.vert`

**Step 1: Add uniforms**

After line 19 (`uniform vec2 screenSize;`), add:

```glsl
uniform float zoom;
uniform vec2 pan;
```

**Step 2: Update NDC calculation**

Replace lines 29-31:

```glsl
// convert entity position to NDC
// entity coords are in screen pixels, convert to [-1, 1]
float ndcX = (e.x / screenSize.x) * 2.0 - 1.0;
float ndcY = (e.y / screenSize.y) * 2.0 - 1.0;
```

With:

```glsl
// apply pan offset and zoom to convert to NDC
// pan is in screen pixels, zoom scales the view
float ndcX = ((e.x - pan.x) * zoom / screenSize.x) * 2.0 - 1.0;
float ndcY = ((e.y - pan.y) * zoom / screenSize.y) * 2.0 - 1.0;
```

**Step 3: Scale quad size by zoom**

Replace line 34:

```glsl
float quadSizeNdc = 16.0 / screenSize.x;
```

With:

```glsl
float quadSizeNdc = (16.0 * zoom) / screenSize.x;
```

**Step 4: Build and test**

Run: `zig build && ./zig-out/bin/lofivor`

Expected: Renders exactly as before (zoom=1.0, pan=0,0 should be identical to old behavior)

---

### Task 3: Add zoom input handling

**Files:**
- Modify: `src/sandbox_main.zig` (handleInput function and main loop)

**Step 1: Add zoom constants**

After line 32 (BENCH_EXIT_SUSTAIN), add:

```zig
// zoom settings
const ZOOM_MIN: f32 = 1.0;
const ZOOM_MAX: f32 = 10.0;
const ZOOM_SPEED: f32 = 0.1; // multiplier per scroll tick
```

**Step 2: Create handleCamera function**

After the `handleInput` function (around line 458), add:

```zig
fn handleCamera(zoom: *f32, pan: *@Vector(2, f32)) void {
    const wheel = rl.getMouseWheelMove();

    if (wheel != 0) {
        const mouse_pos = rl.getMousePosition();
        const old_zoom = zoom.*;

        // calculate new zoom
        const zoom_factor = if (wheel > 0) (1.0 + ZOOM_SPEED) else (1.0 / (1.0 + ZOOM_SPEED));
        var new_zoom = old_zoom * zoom_factor;
        new_zoom = std.math.clamp(new_zoom, ZOOM_MIN, ZOOM_MAX);

        if (new_zoom != old_zoom) {
            // zoom toward mouse cursor:
            // keep the world point under the cursor stationary
            // world_pos = (screen_pos / old_zoom) + old_pan
            // new_pan = world_pos - (screen_pos / new_zoom)
            const world_x = (mouse_pos.x / old_zoom) + pan.*[0];
            const world_y = (mouse_pos.y / old_zoom) + pan.*[1];
            pan.*[0] = world_x - (mouse_pos.x / new_zoom);
            pan.*[1] = world_y - (mouse_pos.y / new_zoom);
            zoom.* = new_zoom;

            // clamp pan to bounds
            clampPan(pan, zoom.*);
        }
    }

    // reset on Esc or Space (Space also toggles pause in handleInput)
    if (rl.isKeyPressed(.escape)) {
        zoom.* = 1.0;
        pan.* = @Vector(2, f32){ 0, 0 };
    }
}

fn clampPan(pan: *@Vector(2, f32), zoom: f32) void {
    // when zoomed in, limit pan so viewport stays in simulation bounds
    // visible area = screen_size / zoom
    // max pan = world_size - visible_area
    const screen_w: f32 = @floatFromInt(SCREEN_WIDTH);
    const screen_h: f32 = @floatFromInt(SCREEN_HEIGHT);
    const visible_w = screen_w / zoom;
    const visible_h = screen_h / zoom;

    const max_pan_x = @max(0, screen_w - visible_w);
    const max_pan_y = @max(0, screen_h - visible_h);

    pan.*[0] = std.math.clamp(pan.*[0], 0, max_pan_x);
    pan.*[1] = std.math.clamp(pan.*[1], 0, max_pan_y);
}
```

**Step 3: Call handleCamera in main loop**

In the main loop, after the `handleInput` call (line 318), add:

```zig
handleCamera(&zoom, &pan);
```

**Step 4: Also reset zoom when Space is pressed**

In `handleInput`, modify the space key handler (around line 450):

```zig
// pause: space (also resets zoom in handleCamera context)
if (rl.isKeyPressed(.space)) {
    paused.* = !paused.*;
}
```

Actually, handleInput doesn't have access to zoom/pan. We need to either:
- Pass zoom/pan to handleInput
- Handle space reset in handleCamera

Let's handle it in handleCamera. Add after the escape check:

```zig
// Space also resets zoom (pause is handled separately in handleInput)
if (rl.isKeyPressed(.space)) {
    zoom.* = 1.0;
    pan.* = @Vector(2, f32){ 0, 0 };
}
```

**Step 5: Build and test zoom**

Run: `zig build && ./zig-out/bin/lofivor`

Test:
1. Scroll up - entities should get bigger (zoom in toward cursor)
2. Scroll down - entities get smaller (but not below 1x)
3. Press Esc or Space - resets to default view

---

### Task 4: Add pan input handling

**Files:**
- Modify: `src/sandbox_main.zig` (handleCamera function)

**Step 1: Add pan logic to handleCamera**

Add this after the zoom handling, before the reset checks:

```zig
// pan with any mouse button drag (only when zoomed in)
if (zoom.* > 1.0) {
    const any_button = rl.isMouseButtonDown(.left) or
                       rl.isMouseButtonDown(.right) or
                       rl.isMouseButtonDown(.middle);
    if (any_button) {
        const delta = rl.getMouseDelta();
        // pan in opposite direction of drag (drag right = view moves left = pan increases)
        pan.*[0] -= delta.x / zoom.*;
        pan.*[1] -= delta.y / zoom.*;
        clampPan(pan, zoom.*);
    }
}
```

**Step 2: Build and test pan**

Run: `zig build && ./zig-out/bin/lofivor`

Test:
1. Scroll to zoom in past 1x
2. Click and drag with any mouse button - viewport should pan
3. Try to pan past edges - should be bounded
4. At 1x zoom, dragging should do nothing

---

### Task 5: Add zoom display to UI

**Files:**
- Modify: `src/ui.zig:34` (drawMetrics signature)
- Modify: `src/ui.zig:71-72` (add zoom line after render)
- Modify: `src/sandbox_main.zig:387` (pass zoom to drawMetrics)

**Step 1: Update drawMetrics signature**

Change line 34:

```zig
pub fn drawMetrics(entities: *const sandbox.Entities, update_us: i64, render_us: i64, paused: bool, font: rl.Font) void {
```

To:

```zig
pub fn drawMetrics(entities: *const sandbox.Entities, update_us: i64, render_us: i64, paused: bool, zoom: f32, font: rl.Font) void {
```

**Step 2: Increase box height for zoom line**

Change line 50:

```zig
const bg_height: i32 = if (paused) 130 else 100;
```

To:

```zig
const bg_height: i32 = if (paused) 150 else 120;
```

**Step 3: Add zoom display after render line**

After line 72 (render_text draw), add:

```zig
y += line_height;

// zoom level
const zoom_text = std.fmt.bufPrintZ(&buf, "zoom:     {d:.1}x", .{zoom}) catch "?";
rl.drawTextEx(font, zoom_text, .{ .x = padding, .y = y }, font_size, 0, if (zoom > 1.0) highlight_color else text_color);
```

**Step 4: Update call in sandbox_main.zig**

Change line 387:

```zig
ui.drawMetrics(&entities, update_time_us, render_time_us, paused, ui_font);
```

To:

```zig
ui.drawMetrics(&entities, update_time_us, render_time_us, paused, zoom, ui_font);
```

**Step 5: Build and test UI**

Run: `zig build && ./zig-out/bin/lofivor`

Test:
1. UI should show "zoom: 1.0x" in white
2. Scroll to zoom - should update and turn yellow when > 1x
3. Reset with Esc - back to white 1.0x

---

### Task 6: Update controls legend

**Files:**
- Modify: `src/ui.zig:120-139` (drawControls function)

**Step 1: Update controls list and box height**

Change line 121:

```zig
const ctrl_box_height: i32 = @intFromFloat(small_line_height * 5 + box_padding * 2);
```

To:

```zig
const ctrl_box_height: i32 = @intFromFloat(small_line_height * 7 + box_padding * 2);
```

Change the controls array (lines 127-133):

```zig
const controls = [_][]const u8{
    "+/-: 10k entities",
    "shift +/-: 50k",
    "scroll: zoom",
    "drag: pan (zoomed)",
    "space: pause/reset",
    "esc: reset zoom",
    "tab: toggle ui",
};
```

**Step 2: Build and final test**

Run: `zig build && ./zig-out/bin/lofivor`

Full test:
1. Scroll wheel zooms toward cursor (1x-10x)
2. Any mouse drag pans when zoomed > 1x
3. Pan is bounded to simulation area
4. Esc resets zoom/pan
5. Space toggles pause AND resets zoom/pan
6. UI shows zoom level (yellow when zoomed)
7. Controls legend shows new controls

---

### Task 7: Commit

```bash
git add src/sandbox_main.zig src/ssbo_renderer.zig src/shaders/entity.vert src/ui.zig
git commit -m "feat: add zoom/pan camera

- scroll wheel zooms toward cursor (1x-10x range)
- any mouse button drag pans when zoomed
- pan bounded to simulation area
- esc/space resets to default view
- zoom level shown in metrics panel"
```
