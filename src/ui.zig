// ui drawing - all visual config at top for easy tweaking

const std = @import("std");
const rl = @import("raylib");
const sandbox = @import("sandbox.zig");

// =============================================================================
// config - tweak these
// =============================================================================

pub const font_size: f32 = 16;
pub const small_font_size: f32 = 16;
pub const line_height: f32 = 20;
pub const small_line_height: f32 = 18;
pub const padding: f32 = 10;
pub const box_padding: f32 = 8;

// colors
pub const text_color = rl.Color.white;
pub const dim_text_color = rl.Color.gray;
pub const highlight_color = rl.Color.yellow;
pub const box_bg = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 200 };

// =============================================================================
// state
// =============================================================================

pub var show_ui: bool = true;

// =============================================================================
// drawing functions
// =============================================================================

pub fn drawMetrics(entities: *const sandbox.Entities, update_us: i64, render_us: i64, paused: bool, zoom: f32, font: rl.Font) void {
    if (!show_ui) return;

    var buf: [256]u8 = undefined;

    // fps box (above metrics)
    const fps_box_height: i32 = 26;
    rl.drawRectangle(5, 5, 180, fps_box_height, box_bg);
    const frame_ms = rl.getFrameTime() * 1000.0;
    const fps = if (frame_ms > 0) 1000.0 / frame_ms else 0;
    const fps_text = std.fmt.bufPrintZ(&buf, "FPS: {d:.0}", .{fps}) catch "?";
    rl.drawTextEx(font, fps_text, .{ .x = padding, .y = padding }, font_size, 0, text_color);

    // metrics box (below fps)
    const metrics_y: i32 = 5 + fps_box_height + 5;
    var y: f32 = @as(f32, @floatFromInt(metrics_y)) + box_padding;
    const bg_height: i32 = if (paused) 150 else 120;
    rl.drawRectangle(5, metrics_y, 180, bg_height, box_bg);

    // entity count
    const count_text = std.fmt.bufPrintZ(&buf, "entities: {d}", .{entities.count}) catch "?";
    rl.drawTextEx(font, count_text, .{ .x = padding, .y = y }, font_size, 0, text_color);
    y += line_height;

    // frame time (frame_ms already calculated above for fps)
    const frame_text = std.fmt.bufPrintZ(&buf, "frame:    {d:.1}ms", .{frame_ms}) catch "?";
    rl.drawTextEx(font, frame_text, .{ .x = padding, .y = y }, font_size, 0, text_color);
    y += line_height;

    // update time
    const update_ms = @as(f32, @floatFromInt(update_us)) / 1000.0;
    const update_text = std.fmt.bufPrintZ(&buf, "update:   {d:.1}ms", .{update_ms}) catch "?";
    rl.drawTextEx(font, update_text, .{ .x = padding, .y = y }, font_size, 0, text_color);
    y += line_height;

    // render time
    const render_ms = @as(f32, @floatFromInt(render_us)) / 1000.0;
    const render_text = std.fmt.bufPrintZ(&buf, "render:   {d:.1}ms", .{render_ms}) catch "?";
    rl.drawTextEx(font, render_text, .{ .x = padding, .y = y }, font_size, 0, text_color);
    y += line_height;

    // zoom level
    const zoom_text = std.fmt.bufPrintZ(&buf, "zoom:     {d:.1}x", .{zoom}) catch "?";
    rl.drawTextEx(font, zoom_text, .{ .x = padding, .y = y }, font_size, 0, if (zoom > 1.0) highlight_color else text_color);
    y += line_height;

    // paused indicator
    if (paused) {
        y += line_height;
        rl.drawTextEx(font, "PAUSED", .{ .x = padding, .y = y }, font_size, 0, highlight_color);
    }

    // controls legend
    drawControls(font, metrics_y + bg_height);
}

pub fn drawMemory(entity_count: usize, font: rl.Font) void {
    if (!show_ui) return;

    var buf: [256]u8 = undefined;

    const box_width: i32 = 160;
    const box_height: i32 = @intFromFloat(line_height * 3 + box_padding * 2);
    const box_x: i32 = @as(i32, @intCast(sandbox.SCREEN_WIDTH)) - box_width - 5;
    const box_y: i32 = 5;

    rl.drawRectangle(box_x, box_y, box_width, box_height, box_bg);

    var y: f32 = @as(f32, @floatFromInt(box_y)) + box_padding;
    const x: f32 = @floatFromInt(box_x + @as(i32, @intFromFloat(box_padding)));

    // entity memory (CPU side)
    const entity_bytes = entity_count * @sizeOf(sandbox.Entity);
    const entity_mb = @as(f32, @floatFromInt(entity_bytes)) / (1024.0 * 1024.0);
    const entity_text = std.fmt.bufPrintZ(&buf, "cpu:  {d:.1} MB", .{entity_mb}) catch "?";
    rl.drawTextEx(font, entity_text, .{ .x = x, .y = y }, font_size, 0, text_color);
    y += line_height;

    // GPU buffer memory (SSBO)
    const gpu_bytes = entity_count * @sizeOf(sandbox.GpuEntity);
    const gpu_mb = @as(f32, @floatFromInt(gpu_bytes)) / (1024.0 * 1024.0);
    const gpu_text = std.fmt.bufPrintZ(&buf, "gpu:  {d:.1} MB", .{gpu_mb}) catch "?";
    rl.drawTextEx(font, gpu_text, .{ .x = x, .y = y }, font_size, 0, text_color);
    y += line_height;

    // total
    const total_mb = entity_mb + gpu_mb;
    const total_text = std.fmt.bufPrintZ(&buf, "total: {d:.1} MB", .{total_mb}) catch "?";
    rl.drawTextEx(font, total_text, .{ .x = x, .y = y }, font_size, 0, dim_text_color);
}

fn drawControls(font: rl.Font, metrics_bottom: i32) void {
    const ctrl_box_height: i32 = @intFromFloat(small_line_height * 7 + box_padding * 2);
    const ctrl_box_y: i32 = metrics_bottom + 5;
    rl.drawRectangle(5, ctrl_box_y, 175, ctrl_box_height, box_bg);

    var y: f32 = @as(f32, @floatFromInt(ctrl_box_y)) + box_padding;

    const controls = [_][]const u8{
        "+/-: 10k entities",
        "shift +/-: 50k",
        "scroll: zoom",
        "drag: pan (zoomed)",
        "space: pause, r: reset",
        "q: zoom out / quit",
        "tab: toggle ui",
    };

    for (controls) |text| {
        rl.drawTextEx(font, @ptrCast(text), .{ .x = padding, .y = y }, small_font_size, 0, dim_text_color);
        y += small_line_height;
    }
}
