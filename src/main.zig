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

// trail ring buffer for projectile
const TRAIL_LENGTH = 20;
var trail_positions: [TRAIL_LENGTH]struct { x: f32, y: f32 } = undefined;
var trail_count: usize = 0;
var trail_head: usize = 0;
var last_proj_exists: bool = false;

// explosion animation state
const Explosion = struct {
    x: f32,
    y: f32,
    radius: f32,
    max_radius: f32,
    alpha: u8,
};
const MAX_EXPLOSIONS = 4;
var explosions: [MAX_EXPLOSIONS]?Explosion = .{ null, null, null, null };

fn spawnExplosion(x: f32, y: f32) void {
    for (&explosions) |*slot| {
        if (slot.* == null) {
            slot.* = .{
                .x = x,
                .y = y,
                .radius = 5,
                .max_radius = 40,
                .alpha = 255,
            };
            return;
        }
    }
}

fn updateExplosions() void {
    for (&explosions) |*slot| {
        if (slot.*) |*exp| {
            exp.radius += 2;
            if (exp.alpha > 8) {
                exp.alpha -= 8;
            } else {
                slot.* = null;
            }
        }
    }
}

fn drawExplosions() void {
    for (explosions) |maybe_exp| {
        if (maybe_exp) |exp| {
            const color = rl.Color{ .r = 255, .g = 200, .b = 50, .a = exp.alpha };
            rl.drawCircleLines(@intFromFloat(exp.x), @intFromFloat(exp.y), exp.radius, color);
            // inner circle
            if (exp.radius > 10) {
                const inner_color = rl.Color{ .r = 255, .g = 255, .b = 200, .a = exp.alpha / 2 };
                rl.drawCircleLines(@intFromFloat(exp.x), @intFromFloat(exp.y), exp.radius * 0.6, inner_color);
            }
        }
    }
}

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

    // load blur shader
    const blur_shader = rl.loadShader(null, "shaders/blur.fs") catch |err| {
        std.debug.print("warning: could not load blur shader: {}\n", .{err});
        @panic("shader load failed");
    };
    defer rl.unloadShader(blur_shader);

    // get shader uniform locations
    const direction_loc = rl.getShaderLocation(blur_shader, "direction");
    const resolution_loc = rl.getShaderLocation(blur_shader, "resolution");

    // set resolution uniform (doesn't change)
    const resolution = [2]f32{ @floatFromInt(SCREEN_WIDTH), @floatFromInt(SCREEN_HEIGHT) };
    rl.setShaderValue(blur_shader, resolution_loc, &resolution, .vec2);

    // create render textures for bloom pipeline
    const game_tex = rl.loadRenderTexture(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT)) catch |err| {
        std.debug.print("warning: could not load render texture: {}\n", .{err});
        @panic("render texture load failed");
    };
    defer rl.unloadRenderTexture(game_tex);
    const blur_tex = rl.loadRenderTexture(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT)) catch |err| {
        std.debug.print("warning: could not load render texture: {}\n", .{err});
        @panic("render texture load failed");
    };
    defer rl.unloadRenderTexture(blur_tex);

    // source rectangle (flip Y for render texture)
    const src_rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(SCREEN_WIDTH),
        .height = @floatFromInt(-@as(i32, SCREEN_HEIGHT)),
    };

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

        const screen_h: i32 = @intCast(SCREEN_HEIGHT);

        // update animations
        updateTrail(&state, screen_h);
        updateExplosions();

        // 1. draw game to texture
        rl.beginTextureMode(game_tex);
        rl.clearBackground(BG_COLOR);

        drawTerrain(state.terrain);
        for (0..2) |i| {
            drawPlayer(&state.players[i], i, screen_h);
        }
        drawProjectile(&state, screen_h);
        drawExplosions();

        rl.endTextureMode();

        // 2. horizontal blur pass
        rl.beginTextureMode(blur_tex);
        rl.beginShaderMode(blur_shader);
        const h_dir = [2]f32{ 1.0, 0.0 };
        rl.setShaderValue(blur_shader, direction_loc, &h_dir, .vec2);
        rl.drawTextureRec(game_tex.texture, src_rect, .{ .x = 0, .y = 0 }, rl.Color.white);
        rl.endShaderMode();
        rl.endTextureMode();

        // 3. final composite: original + vertical blur (additive)
        rl.beginDrawing();

        // draw original game
        rl.drawTextureRec(game_tex.texture, src_rect, .{ .x = 0, .y = 0 }, rl.Color.white);

        // additive blend the blurred version (vertical blur of horizontal blur)
        rl.beginBlendMode(.additive);
        rl.beginShaderMode(blur_shader);
        const v_dir = [2]f32{ 0.0, 1.0 };
        rl.setShaderValue(blur_shader, direction_loc, &v_dir, .vec2);
        rl.drawTextureRec(blur_tex.texture, src_rect, .{ .x = 0, .y = 0 }, rl.Color.white);
        rl.endShaderMode();
        rl.endBlendMode();

        // draw UI on top (not affected by bloom)
        drawDebugInfo(&state);

        rl.endDrawing();
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

const Player = game.Player;

// player rendering constants
const PLAYER_BASE_WIDTH: f32 = 30;
const PLAYER_BASE_HEIGHT: f32 = 15;
const CANNON_LENGTH: f32 = 25;
const CANNON_THICKNESS: f32 = 3;

fn getPlayerColor(idx: usize) rl.Color {
    return if (idx == 0) CYAN else MAGENTA;
}

fn drawPlayer(player: *const Player, idx: usize, screen_h: i32) void {
    if (!player.alive) return;

    const color = getPlayerColor(idx);
    const px = player.x.toFloat();
    const py = @as(f32, @floatFromInt(screen_h)) - player.y.toFloat();

    // base rectangle
    const base_x = px - PLAYER_BASE_WIDTH / 2;
    const base_y = py - PLAYER_BASE_HEIGHT;
    rl.drawRectangleLines(
        @intFromFloat(base_x),
        @intFromFloat(base_y),
        @intFromFloat(PLAYER_BASE_WIDTH),
        @intFromFloat(PLAYER_BASE_HEIGHT),
        color,
    );

    // turret circle on top
    const turret_y = py - PLAYER_BASE_HEIGHT;
    rl.drawCircleLines(@intFromFloat(px), @intFromFloat(turret_y), 8, color);

    // cannon barrel
    // angle: 0 = right, PI = left
    // for player 1 (idx=1), flip the direction
    const angle = player.cannon_angle.toFloat();
    const dir: f32 = if (idx == 0) 1 else -1;
    const cannon_end_x = px + dir * @cos(angle) * CANNON_LENGTH;
    const cannon_end_y = turret_y - @sin(angle) * CANNON_LENGTH;

    rl.drawLineEx(
        .{ .x = px, .y = turret_y },
        .{ .x = cannon_end_x, .y = cannon_end_y },
        CANNON_THICKNESS,
        color,
    );

    // power meter (bar below player)
    const power_bar_width: f32 = 40;
    const power_bar_height: f32 = 4;
    const power_y = py + 5;
    const power_x = px - power_bar_width / 2;
    const power_pct = player.power.toFloat() / 100.0;

    // outline
    rl.drawRectangleLines(
        @intFromFloat(power_x),
        @intFromFloat(power_y),
        @intFromFloat(power_bar_width),
        @intFromFloat(power_bar_height),
        color,
    );

    // filled portion
    rl.drawRectangle(
        @intFromFloat(power_x + 1),
        @intFromFloat(power_y + 1),
        @intFromFloat((power_bar_width - 2) * power_pct),
        @intFromFloat(power_bar_height - 2),
        color,
    );
}

fn updateTrail(state: *const GameState, screen_h: i32) void {
    if (state.projectile) |proj| {
        // add new position
        const x = proj.x.toFloat();
        const y = @as(f32, @floatFromInt(screen_h)) - proj.y.toFloat();

        trail_positions[trail_head] = .{ .x = x, .y = y };
        trail_head = (trail_head + 1) % TRAIL_LENGTH;
        if (trail_count < TRAIL_LENGTH) trail_count += 1;

        last_proj_exists = true;
    } else {
        // projectile gone - spawn explosion at last position
        if (last_proj_exists and trail_count > 0) {
            const last_idx = (trail_head + TRAIL_LENGTH - 1) % TRAIL_LENGTH;
            spawnExplosion(trail_positions[last_idx].x, trail_positions[last_idx].y);
            trail_count = 0;
            trail_head = 0;
        }
        last_proj_exists = false;
    }
}

fn drawProjectile(state: *const GameState, screen_h: i32) void {
    // draw trail (fading)
    if (trail_count > 1) {
        var i: usize = 0;
        while (i < trail_count - 1) : (i += 1) {
            const idx = (trail_head + TRAIL_LENGTH - trail_count + i) % TRAIL_LENGTH;
            const next_idx = (idx + 1) % TRAIL_LENGTH;

            const alpha: u8 = @intFromFloat(255.0 * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(trail_count)));
            const trail_color = rl.Color{ .r = 255, .g = 255, .b = 0, .a = alpha };

            rl.drawLineEx(
                .{ .x = trail_positions[idx].x, .y = trail_positions[idx].y },
                .{ .x = trail_positions[next_idx].x, .y = trail_positions[next_idx].y },
                2,
                trail_color,
            );
        }
    }

    // draw current projectile
    if (state.projectile) |proj| {
        const x = proj.x.toFloat();
        const y = @as(f32, @floatFromInt(screen_h)) - proj.y.toFloat();
        rl.drawCircle(@intFromFloat(x), @intFromFloat(y), 4, YELLOW);
    }
}

fn drawTerrain(terrain: *const Terrain) void {
    const screen_h: i32 = @intCast(SCREEN_HEIGHT);
    for (0..SCREEN_WIDTH - 1) |x| {
        const y1 = screen_h - terrain.heights[x].toInt();
        const y2 = screen_h - terrain.heights[x + 1].toInt();
        rl.drawLine(@intCast(x), y1, @intCast(x + 1), y2, GREEN);
    }
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
