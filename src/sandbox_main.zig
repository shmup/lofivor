// sandbox stress test entry point
// measures entity count ceiling on weak hardware

const std = @import("std");
const rl = @import("raylib");
const sandbox = @import("sandbox.zig");

const SCREEN_WIDTH = sandbox.SCREEN_WIDTH;
const SCREEN_HEIGHT = sandbox.SCREEN_HEIGHT;

// colors
const BG_COLOR = rl.Color{ .r = 10, .g = 10, .b = 18, .a = 255 };
const CYAN = rl.Color{ .r = 0, .g = 255, .b = 255, .a = 255 };

pub fn main() !void {
    rl.initWindow(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT), "lofivor sandbox");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var entities = sandbox.Entities.init();
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    var rng = prng.random();

    var paused = false;

    // timing
    var update_time_us: i64 = 0;
    var render_time_us: i64 = 0;

    while (!rl.windowShouldClose()) {
        // controls
        handleInput(&entities, &rng, &paused);

        // update
        if (!paused) {
            const update_start = std.time.microTimestamp();
            sandbox.update(&entities, &rng);
            update_time_us = std.time.microTimestamp() - update_start;
        }

        // render
        const render_start = std.time.microTimestamp();

        rl.beginDrawing();
        rl.clearBackground(BG_COLOR);

        // draw entities as filled circles
        for (entities.items[0..entities.count]) |entity| {
            rl.drawCircle(
                @intFromFloat(entity.x),
                @intFromFloat(entity.y),
                4,
                CYAN,
            );
        }

        // metrics overlay
        drawMetrics(&entities, update_time_us, render_time_us, paused);

        rl.endDrawing();

        render_time_us = std.time.microTimestamp() - render_start;
    }
}

fn handleInput(entities: *sandbox.Entities, rng: *std.Random, paused: *bool) void {
    const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    const add_count: usize = if (shift) 1000 else 100;

    // add entities: = or +
    if (rl.isKeyPressed(.equal) or rl.isKeyPressed(.kp_add)) {
        for (0..add_count) |_| {
            entities.add(rng);
        }
    }

    // remove entities: - or _
    if (rl.isKeyPressed(.minus) or rl.isKeyPressed(.kp_subtract)) {
        entities.remove(add_count);
    }

    // reset: r
    if (rl.isKeyPressed(.r)) {
        entities.reset();
    }

    // pause: space
    if (rl.isKeyPressed(.space)) {
        paused.* = !paused.*;
    }
}

fn drawMetrics(entities: *const sandbox.Entities, update_us: i64, render_us: i64, paused: bool) void {
    var buf: [256]u8 = undefined;
    var y: i32 = 10;
    const line_height: i32 = 20;

    // entity count
    const count_text = std.fmt.bufPrintZ(&buf, "entities: {d}", .{entities.count}) catch "?";
    rl.drawText(count_text, 10, y, 16, rl.Color.white);
    y += line_height;

    // frame time
    const frame_ms = rl.getFrameTime() * 1000.0;
    const frame_text = std.fmt.bufPrintZ(&buf, "frame:    {d:.1}ms", .{frame_ms}) catch "?";
    rl.drawText(frame_text, 10, y, 16, rl.Color.white);
    y += line_height;

    // update time
    const update_ms = @as(f32, @floatFromInt(update_us)) / 1000.0;
    const update_text = std.fmt.bufPrintZ(&buf, "update:   {d:.1}ms", .{update_ms}) catch "?";
    rl.drawText(update_text, 10, y, 16, rl.Color.white);
    y += line_height;

    // render time
    const render_ms = @as(f32, @floatFromInt(render_us)) / 1000.0;
    const render_text = std.fmt.bufPrintZ(&buf, "render:   {d:.1}ms", .{render_ms}) catch "?";
    rl.drawText(render_text, 10, y, 16, rl.Color.white);
    y += line_height;

    // paused indicator
    if (paused) {
        y += line_height;
        rl.drawText("PAUSED", 10, y, 16, rl.Color.yellow);
    }

    // controls help (bottom)
    const help_y: i32 = @intCast(SCREEN_HEIGHT - 30);
    rl.drawText("+/-: 100  shift+/-: 1000  space: pause  r: reset", 10, help_y, 14, rl.Color.gray);
}
