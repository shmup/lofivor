const std = @import("std");
const rl = @import("raylib");

const Fixed = @import("fixed.zig").Fixed;
const trig = @import("trig.zig");
const terrain_mod = @import("terrain.zig");
const game = @import("game.zig");

const Terrain = terrain_mod.Terrain;
const GameState = game.GameState;
const Input = game.Input;

const SCREEN_WIDTH = terrain_mod.SCREEN_WIDTH;
const SCREEN_HEIGHT = terrain_mod.SCREEN_HEIGHT;

// colors (vector/oscilloscope aesthetic)
const BG_COLOR = rl.Color{ .r = 10, .g = 10, .b = 18, .a = 255 };
const CYAN = rl.Color{ .r = 0, .g = 255, .b = 255, .a = 255 };
const MAGENTA = rl.Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
const GREEN = rl.Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
const YELLOW = rl.Color{ .r = 255, .g = 255, .b = 0, .a = 255 };

pub fn main() !void {
    rl.initWindow(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT), "lockstep artillery");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // initialize game
    const terrain = terrain_mod.generateFixed();
    var state = game.initGame(&terrain);

    while (!rl.windowShouldClose()) {
        // gather input for current player
        const input = gatherInput();

        // simulate (both players' inputs, but only current player acts)
        var inputs: [2]Input = .{ Input.NONE, Input.NONE };
        inputs[state.current_turn] = input;
        game.simulate(&state, inputs);

        // render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(BG_COLOR);

        drawDebugInfo(&state);
    }
}

fn gatherInput() Input {
    var input = Input.NONE;

    // angle: up/down arrows
    if (rl.isKeyDown(.up)) input.angle_delta = 1;
    if (rl.isKeyDown(.down)) input.angle_delta = -1;

    // power: left/right arrows
    if (rl.isKeyDown(.right)) input.power_delta = 1;
    if (rl.isKeyDown(.left)) input.power_delta = -1;

    // fire: space
    if (rl.isKeyPressed(.space)) input.fire = true;

    return input;
}

fn drawDebugInfo(state: *const GameState) void {
    var buf: [256]u8 = undefined;
    var y: i32 = 10;
    const line_height: i32 = 20;

    // tick and turn
    const turn_text = std.fmt.bufPrintZ(&buf, "tick: {d}  turn: player {d}", .{ state.tick, state.current_turn }) catch "?";
    rl.drawText(turn_text, 10, y, 16, rl.Color.white);
    y += line_height;

    // player 0 info
    const p0 = &state.players[0];
    const p0_text = std.fmt.bufPrintZ(&buf, "P0: angle={d:.2} power={d:.0} health={d}", .{
        p0.cannon_angle.toFloat(),
        p0.power.toFloat(),
        p0.health,
    }) catch "?";
    rl.drawText(p0_text, 10, y, 16, CYAN);
    y += line_height;

    // player 1 info
    const p1 = &state.players[1];
    const p1_text = std.fmt.bufPrintZ(&buf, "P1: angle={d:.2} power={d:.0} health={d}", .{
        p1.cannon_angle.toFloat(),
        p1.power.toFloat(),
        p1.health,
    }) catch "?";
    rl.drawText(p1_text, 10, y, 16, MAGENTA);
    y += line_height;

    // projectile info
    if (state.projectile) |proj| {
        const proj_text = std.fmt.bufPrintZ(&buf, "projectile: x={d:.1} y={d:.1} vx={d:.2} vy={d:.2}", .{
            proj.x.toFloat(),
            proj.y.toFloat(),
            proj.vx.toFloat(),
            proj.vy.toFloat(),
        }) catch "?";
        rl.drawText(proj_text, 10, y, 16, YELLOW);
    } else {
        rl.drawText("projectile: none (press SPACE to fire)", 10, y, 16, YELLOW);
    }
    y += line_height;

    // controls
    y += line_height;
    rl.drawText("controls: UP/DOWN=angle  LEFT/RIGHT=power  SPACE=fire", 10, y, 14, rl.Color.gray);
}
