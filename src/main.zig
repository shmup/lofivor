const std = @import("std");
const rl = @import("raylib");

const Fixed = @import("fixed.zig").Fixed;
const trig = @import("trig.zig");

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;

// colors (vector/oscilloscope aesthetic)
const BG_COLOR = rl.Color{ .r = 10, .g = 10, .b = 18, .a = 255 };
const CYAN = rl.Color{ .r = 0, .g = 255, .b = 255, .a = 255 };
const MAGENTA = rl.Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
const GREEN = rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 };

pub fn main() !void {
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "lockstep");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // test fixed-point math
    const angle = Fixed.ZERO;
    const sin_val = trig.sin(angle);
    const cos_val = trig.cos(angle);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(BG_COLOR);

        // draw some test lines
        rl.drawLine(100, 500, 700, 500, GREEN);
        rl.drawLine(200, 300, 200, 500, CYAN);
        rl.drawLine(600, 300, 600, 500, MAGENTA);

        // show fixed-point values
        var buf: [128]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "sin(0)={d:.3} cos(0)={d:.3}", .{ sin_val.toFloat(), cos_val.toFloat() }) catch "?";
        rl.drawText(text, 10, 10, 20, rl.Color.white);
        rl.drawText("lockstep artillery - phase 1 complete", 10, 40, 20, GREEN);
    }
}
