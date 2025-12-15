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

// entity rendering
const ENTITY_RADIUS: f32 = 4.0;
const TEXTURE_SIZE: i32 = 16; // must be >= 2 * radius

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

fn createCircleTexture() ?rl.Texture2D {
    // create a render texture to draw circle into
    const target = rl.loadRenderTexture(TEXTURE_SIZE, TEXTURE_SIZE) catch return null;

    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); // transparent
    rl.drawCircle(
        @divTrunc(TEXTURE_SIZE, 2),
        @divTrunc(TEXTURE_SIZE, 2),
        ENTITY_RADIUS,
        CYAN,
    );
    rl.endTextureMode();

    return target.texture;
}

pub fn main() !void {
    rl.initWindow(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT), "lofivor sandbox");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // create circle texture for batched rendering
    const circle_texture = createCircleTexture() orelse {
        std.debug.print("failed to create circle texture\n", .{});
        return;
    };
    defer rl.unloadTexture(circle_texture);

    // load UI font (embedded)
    const font_data = @embedFile("verdanab.ttf");
    const ui_font = rl.loadFontFromMemory(".ttf", font_data, 32, null) catch {
        std.debug.print("failed to load embedded font\n", .{});
        return;
    };
    defer rl.unloadFont(ui_font);

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

        // draw entities using rlgl quad batching
        const size = @as(f32, @floatFromInt(TEXTURE_SIZE));
        const half = size / 2.0;

        rl.gl.rlSetTexture(circle_texture.id);
        rl.gl.rlBegin(rl.gl.rl_quads);
        rl.gl.rlColor4ub(255, 255, 255, 255); // white tint

        for (entities.items[0..entities.count]) |entity| {
            const x1 = entity.x - half;
            const y1 = entity.y - half;
            const x2 = entity.x + half;
            const y2 = entity.y + half;

            // quad vertices: bottom-left, bottom-right, top-right, top-left
            rl.gl.rlTexCoord2f(0, 0);
            rl.gl.rlVertex2f(x1, y2);
            rl.gl.rlTexCoord2f(1, 0);
            rl.gl.rlVertex2f(x2, y2);
            rl.gl.rlTexCoord2f(1, 1);
            rl.gl.rlVertex2f(x2, y1);
            rl.gl.rlTexCoord2f(0, 1);
            rl.gl.rlVertex2f(x1, y1);
        }

        rl.gl.rlEnd();
        rl.gl.rlSetTexture(0);

        // metrics overlay
        drawMetrics(&entities, update_time_us, render_time_us, paused, ui_font);

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
    const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
    const add_count: usize = if (ctrl and shift) 10000 else if (shift) 1000 else 100;

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

fn drawMetrics(entities: *const sandbox.Entities, update_us: i64, render_us: i64, paused: bool, font: rl.Font) void {
    var buf: [256]u8 = undefined;
    var y: f32 = 10;
    const line_height: f32 = 20;
    const font_size: f32 = 14;

    // dark background for readability
    const bg_height: i32 = if (paused) 130 else 100;
    rl.drawRectangle(5, 5, 180, bg_height, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 200 });

    // entity count
    const count_text = std.fmt.bufPrintZ(&buf, "entities: {d}", .{entities.count}) catch "?";
    rl.drawTextEx(font, count_text, .{ .x = 10, .y = y }, font_size, 0, rl.Color.white);
    y += line_height;

    // frame time
    const frame_ms = rl.getFrameTime() * 1000.0;
    const frame_text = std.fmt.bufPrintZ(&buf, "frame:    {d:.1}ms", .{frame_ms}) catch "?";
    rl.drawTextEx(font, frame_text, .{ .x = 10, .y = y }, font_size, 0, rl.Color.white);
    y += line_height;

    // update time
    const update_ms = @as(f32, @floatFromInt(update_us)) / 1000.0;
    const update_text = std.fmt.bufPrintZ(&buf, "update:   {d:.1}ms", .{update_ms}) catch "?";
    rl.drawTextEx(font, update_text, .{ .x = 10, .y = y }, font_size, 0, rl.Color.white);
    y += line_height;

    // render time
    const render_ms = @as(f32, @floatFromInt(render_us)) / 1000.0;
    const render_text = std.fmt.bufPrintZ(&buf, "render:   {d:.1}ms", .{render_ms}) catch "?";
    rl.drawTextEx(font, render_text, .{ .x = 10, .y = y }, font_size, 0, rl.Color.white);
    y += line_height;

    // paused indicator
    if (paused) {
        y += line_height;
        rl.drawTextEx(font, "PAUSED", .{ .x = 10, .y = y }, font_size, 0, rl.Color.yellow);
    }

    // controls legend (top left, beneath debug info)
    const ctrl_line_height: f32 = 18;
    const ctrl_font_size: f32 = 12;
    const ctrl_box_height: i32 = @intFromFloat(ctrl_line_height * 5 + 16); // 5 lines + padding
    const ctrl_box_y: i32 = 5 + bg_height + 5; // beneath debug box with gap
    rl.drawRectangle(5, ctrl_box_y, 175, ctrl_box_height, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 200 });

    var ctrl_y: f32 = @floatFromInt(ctrl_box_y + 8);
    rl.drawTextEx(font, "+/-: add/remove 100", .{ .x = 10, .y = ctrl_y }, ctrl_font_size, 0, rl.Color.gray);
    ctrl_y += ctrl_line_height;
    rl.drawTextEx(font, "shift +/-: 1000", .{ .x = 10, .y = ctrl_y }, ctrl_font_size, 0, rl.Color.gray);
    ctrl_y += ctrl_line_height;
    rl.drawTextEx(font, "ctrl+shift +/-: 10000", .{ .x = 10, .y = ctrl_y }, ctrl_font_size, 0, rl.Color.gray);
    ctrl_y += ctrl_line_height;
    rl.drawTextEx(font, "space: pause", .{ .x = 10, .y = ctrl_y }, ctrl_font_size, 0, rl.Color.gray);
    ctrl_y += ctrl_line_height;
    rl.drawTextEx(font, "r: reset", .{ .x = 10, .y = ctrl_y }, ctrl_font_size, 0, rl.Color.gray);
}
