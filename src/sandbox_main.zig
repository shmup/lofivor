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

// logging thresholds
const TARGET_FRAME_MS: f32 = 16.7; // 60fps
const THRESHOLD_MARGIN: f32 = 2.0; // hysteresis margin to avoid bounce
const JUMP_THRESHOLD_MS: f32 = 5.0; // log if frame time jumps by this much
const HEARTBEAT_INTERVAL: f32 = 10.0; // seconds between periodic logs

const BenchmarkLogger = struct {
    file: ?std.fs.File,
    last_logged_frame_ms: f32,
    was_above_target: bool,
    last_heartbeat: f32,
    start_time: i64,

    fn init() BenchmarkLogger {
        // create log in project root (where zig build runs from)
        const file = std.fs.cwd().createFile("benchmark.log", .{}) catch |err| blk: {
            std.debug.print("failed to create benchmark.log: {}\n", .{err});
            break :blk null;
        };
        if (file) |f| {
            const header = "# lofivor sandbox benchmark\n# time entities frame_ms update_ms render_ms note\n";
            f.writeAll(header) catch {};
            std.debug.print("logging to benchmark.log\n", .{});
        }
        return .{
            .file = file,
            .last_logged_frame_ms = 0,
            .was_above_target = false,
            .last_heartbeat = 0,
            .start_time = std.time.timestamp(),
        };
    }

    fn deinit(self: *BenchmarkLogger) void {
        if (self.file) |f| f.close();
    }

    fn log(self: *BenchmarkLogger, elapsed: f32, entity_count: usize, frame_ms: f32, update_ms: f32, render_ms: f32) void {
        const f = self.file orelse return;

        // hysteresis: need to cross threshold + margin to flip state
        var crossed_threshold = false;
        var now_above = self.was_above_target;
        if (self.was_above_target) {
            // need to drop below target to flip back
            if (frame_ms < TARGET_FRAME_MS) {
                now_above = false;
                crossed_threshold = true;
            }
        } else {
            // need to exceed target + margin to flip
            if (frame_ms > TARGET_FRAME_MS + THRESHOLD_MARGIN) {
                now_above = true;
                crossed_threshold = true;
            }
        }

        const big_jump = (frame_ms - self.last_logged_frame_ms) >= JUMP_THRESHOLD_MS;
        const heartbeat_due = (elapsed - self.last_heartbeat) >= HEARTBEAT_INTERVAL;

        if (!crossed_threshold and !big_jump and !heartbeat_due) return;

        // determine note
        var note: []const u8 = "";
        if (crossed_threshold and now_above) {
            note = "[!60fps]";
        } else if (crossed_threshold and !now_above) {
            note = "[+60fps]";
        } else if (big_jump) {
            note = "[jump]";
        }

        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "[{d:.1}s] entities={d} frame={d:.1}ms update={d:.1}ms render={d:.1}ms {s}\n", .{
            elapsed,
            entity_count,
            frame_ms,
            update_ms,
            render_ms,
            note,
        }) catch return;

        f.writeAll(line) catch {};

        self.last_logged_frame_ms = frame_ms;
        self.was_above_target = now_above;
        if (heartbeat_due) self.last_heartbeat = elapsed;
    }
};

pub fn main() !void {
    rl.initWindow(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT), "lofivor sandbox");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var entities = sandbox.Entities.init();
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    var rng = prng.random();

    var paused = false;
    var logger = BenchmarkLogger.init();
    defer logger.deinit();

    // timing
    var update_time_us: i64 = 0;
    var render_time_us: i64 = 0;
    var elapsed: f32 = 0;

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        elapsed += dt;

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

        // smart logging
        const frame_ms = dt * 1000.0;
        const update_ms = @as(f32, @floatFromInt(update_time_us)) / 1000.0;
        const render_ms = @as(f32, @floatFromInt(render_time_us)) / 1000.0;
        logger.log(elapsed, entities.count, frame_ms, update_ms, render_ms);
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

    // dark background for readability
    const bg_height: i32 = if (paused) 130 else 100;
    rl.drawRectangle(5, 5, 180, bg_height, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 200 });

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
    rl.drawRectangle(5, help_y - 5, 370, 24, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 200 });
    rl.drawText("+/-: 100  shift+/-: 1000  space: pause  r: reset", 10, help_y, 14, rl.Color.gray);
}
