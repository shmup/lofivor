// game state and simulation
// fully deterministic - no floats, no hashmaps, no system time

const std = @import("std");
const Fixed = @import("fixed.zig").Fixed;
const trig = @import("trig.zig");
const Terrain = @import("terrain.zig").Terrain;
const SCREEN_WIDTH = @import("terrain.zig").SCREEN_WIDTH;

// simulation constants
const ANGLE_SPEED: Fixed = Fixed.fromFloat(0.02); // radians per tick when adjusting
const POWER_SPEED: Fixed = Fixed.ONE; // units per tick when adjusting
const MIN_ANGLE: Fixed = Fixed.ZERO;
const MAX_ANGLE: Fixed = Fixed.PI;
const MIN_POWER: Fixed = Fixed.ZERO;
const MAX_POWER: Fixed = Fixed.fromInt(100);
const DAMAGE: i32 = 50;
const HIT_RADIUS: Fixed = Fixed.fromInt(20);
const PROJECTILE_SPEED_FACTOR: Fixed = Fixed.fromFloat(0.15);

pub const Player = struct {
    x: Fixed,
    y: Fixed, // sits on terrain
    cannon_angle: Fixed, // radians, 0 to PI (0=right, PI=left)
    power: Fixed, // 0 to 100
    health: i32,
    alive: bool,
};

pub const Projectile = struct {
    x: Fixed,
    y: Fixed,
    vx: Fixed,
    vy: Fixed,
};

pub const GameState = struct {
    tick: u32,
    current_turn: u8, // 0 or 1
    wind: Fixed,
    players: [2]Player,
    projectile: ?Projectile,
    terrain: *const Terrain,
    rng_state: u64,
};

pub const Input = struct {
    angle_delta: i8, // -1, 0, +1
    power_delta: i8, // -1, 0, +1
    fire: bool,

    pub const NONE: Input = .{
        .angle_delta = 0,
        .power_delta = 0,
        .fire = false,
    };
};

pub fn initGame(terrain: *const Terrain) GameState {
    const p1_x = Fixed.fromInt(100);
    const p2_x = Fixed.fromInt(700);

    return .{
        .tick = 0,
        .current_turn = 0,
        .wind = Fixed.ZERO,
        .players = .{
            .{
                .x = p1_x,
                .y = terrain.heightAt(p1_x),
                .cannon_angle = Fixed.fromFloat(0.785), // ~45 degrees
                .power = Fixed.fromInt(50),
                .health = 100,
                .alive = true,
            },
            .{
                .x = p2_x,
                .y = terrain.heightAt(p2_x),
                .cannon_angle = Fixed.fromFloat(2.356), // ~135 degrees
                .power = Fixed.fromInt(50),
                .health = 100,
                .alive = true,
            },
        },
        .projectile = null,
        .terrain = terrain,
        .rng_state = 0,
    };
}

pub fn simulate(state: *GameState, inputs: [2]Input) void {
    const current = state.current_turn;
    const input = inputs[current];
    var player = &state.players[current];

    // apply input only when no projectile in flight
    if (state.projectile == null) {
        // adjust angle
        const angle_adj = ANGLE_SPEED.mul(Fixed.fromInt(input.angle_delta));
        player.cannon_angle = player.cannon_angle.add(angle_adj).clamp(MIN_ANGLE, MAX_ANGLE);

        // adjust power
        const power_adj = POWER_SPEED.mul(Fixed.fromInt(input.power_delta));
        player.power = player.power.add(power_adj).clamp(MIN_POWER, MAX_POWER);

        // fire
        if (input.fire) {
            const cos_a = trig.cos(player.cannon_angle);
            const sin_a = trig.sin(player.cannon_angle);
            const speed = player.power.mul(PROJECTILE_SPEED_FACTOR);

            // flip vx for player 1 (facing right uses positive cos)
            // player 0 at x=100 faces right, player 1 at x=700 faces left
            const vx = if (current == 0) speed.mul(cos_a) else speed.mul(cos_a).neg();

            state.projectile = .{
                .x = player.x,
                .y = player.y.add(Fixed.fromInt(20)), // spawn above player
                .vx = vx,
                .vy = speed.mul(sin_a),
            };
        }
    }

    // update projectile physics
    if (state.projectile) |*proj| {
        // gravity (downward)
        proj.vy = proj.vy.sub(Fixed.GRAVITY);

        // wind
        proj.vx = proj.vx.add(state.wind.mul(Fixed.WIND_FACTOR));

        // movement
        proj.x = proj.x.add(proj.vx);
        proj.y = proj.y.add(proj.vy);

        var hit = false;

        // terrain collision
        const terrain_y = state.terrain.heightAt(proj.x);
        if (proj.y.lessThan(terrain_y)) {
            hit = true;
        }

        // player collision
        for (&state.players) |*p| {
            if (p.alive and hitTest(proj, p)) {
                p.health -= DAMAGE;
                if (p.health <= 0) p.alive = false;
                hit = true;
            }
        }

        // out of bounds (left/right)
        if (proj.x.lessThan(Fixed.ZERO) or proj.x.greaterThan(Fixed.fromInt(@intCast(SCREEN_WIDTH)))) {
            hit = true;
        }

        // out of bounds (too high - prevent infinite flight)
        if (proj.y.greaterThan(Fixed.fromInt(2000))) {
            hit = true;
        }

        if (hit) {
            state.projectile = null;
            state.current_turn = 1 - current;
        }
    }

    state.tick += 1;
}

fn hitTest(proj: *const Projectile, player: *const Player) bool {
    const dx = proj.x.sub(player.x).abs();
    const dy = proj.y.sub(player.y).abs();
    return dx.lessThan(HIT_RADIUS) and dy.lessThan(HIT_RADIUS);
}

// tests

test "initGame creates valid state" {
    const terrain = @import("terrain.zig").generateFixed();
    const state = initGame(&terrain);

    try std.testing.expectEqual(@as(u32, 0), state.tick);
    try std.testing.expectEqual(@as(u8, 0), state.current_turn);
    try std.testing.expect(state.projectile == null);
    try std.testing.expect(state.players[0].alive);
    try std.testing.expect(state.players[1].alive);
}

test "simulate advances tick" {
    const terrain = @import("terrain.zig").generateFixed();
    var state = initGame(&terrain);

    simulate(&state, .{ Input.NONE, Input.NONE });
    try std.testing.expectEqual(@as(u32, 1), state.tick);

    simulate(&state, .{ Input.NONE, Input.NONE });
    try std.testing.expectEqual(@as(u32, 2), state.tick);
}

test "fire creates projectile" {
    const terrain = @import("terrain.zig").generateFixed();
    var state = initGame(&terrain);

    const fire_input: Input = .{ .angle_delta = 0, .power_delta = 0, .fire = true };
    simulate(&state, .{ fire_input, Input.NONE });

    try std.testing.expect(state.projectile != null);
}

test "projectile moves" {
    const terrain = @import("terrain.zig").generateFixed();
    var state = initGame(&terrain);

    // fire
    const fire_input: Input = .{ .angle_delta = 0, .power_delta = 0, .fire = true };
    simulate(&state, .{ fire_input, Input.NONE });

    const initial_x = state.projectile.?.x;
    const initial_y = state.projectile.?.y;

    // advance
    simulate(&state, .{ Input.NONE, Input.NONE });

    // projectile should have moved
    try std.testing.expect(!state.projectile.?.x.eq(initial_x) or !state.projectile.?.y.eq(initial_y));
}

test "angle adjustment" {
    const terrain = @import("terrain.zig").generateFixed();
    var state = initGame(&terrain);

    const initial_angle = state.players[0].cannon_angle;

    const up_input: Input = .{ .angle_delta = 1, .power_delta = 0, .fire = false };
    simulate(&state, .{ up_input, Input.NONE });

    try std.testing.expect(state.players[0].cannon_angle.greaterThan(initial_angle));
}
