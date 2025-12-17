// sandbox stress test
// measures entity count ceiling on weak hardware

const std = @import("std");

pub const SCREEN_WIDTH: u32 = 1280;
pub const SCREEN_HEIGHT: u32 = 1024;
const CENTER_X: f32 = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2.0;
const CENTER_Y: f32 = @as(f32, @floatFromInt(SCREEN_HEIGHT)) / 2.0;
const RESPAWN_THRESHOLD: f32 = 10.0;
const ENTITY_SPEED: f32 = 2.0;

pub const Entity = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    color: u32,
};

pub const MAX_ENTITIES: usize = 10_000_000;

pub const Entities = struct {
    items: []Entity,
    count: usize,

    var backing: [MAX_ENTITIES]Entity = undefined;

    pub fn init() Entities {
        return .{
            .items = &backing,
            .count = 0,
        };
    }

    pub fn add(self: *Entities, rng: *std.Random) void {
        if (self.count >= MAX_ENTITIES) return;
        self.items[self.count] = spawnAtEdge(rng);
        self.count += 1;
    }

    pub fn remove(self: *Entities, n: usize) void {
        if (n >= self.count) {
            self.count = 0;
        } else {
            self.count -= n;
        }
    }

    pub fn reset(self: *Entities) void {
        self.count = 0;
    }
};

pub fn update(entities: *Entities, rng: *std.Random) void {
    for (entities.items[0..entities.count]) |*entity| {
        // apply velocity
        entity.x += entity.vx;
        entity.y += entity.vy;

        // check if reached center
        const dx = entity.x - CENTER_X;
        const dy = entity.y - CENTER_Y;
        const dist = @sqrt(dx * dx + dy * dy);

        if (dist < RESPAWN_THRESHOLD) {
            // respawn at random edge
            entity.* = spawnAtEdge(rng);
        }
    }
}

pub fn spawnAtEdge(rng: *std.Random) Entity {
    // pick random edge: 0=top, 1=bottom, 2=left, 3=right
    const edge = rng.intRangeAtMost(u8, 0, 3);
    const screen_w = @as(f32, @floatFromInt(SCREEN_WIDTH));
    const screen_h = @as(f32, @floatFromInt(SCREEN_HEIGHT));

    var x: f32 = undefined;
    var y: f32 = undefined;

    switch (edge) {
        0 => { // top
            x = rng.float(f32) * screen_w;
            y = 0;
        },
        1 => { // bottom
            x = rng.float(f32) * screen_w;
            y = screen_h;
        },
        2 => { // left
            x = 0;
            y = rng.float(f32) * screen_h;
        },
        3 => { // right
            x = screen_w;
            y = rng.float(f32) * screen_h;
        },
        else => unreachable,
    }

    // velocity toward center
    const dx = CENTER_X - x;
    const dy = CENTER_Y - y;
    const dist = @sqrt(dx * dx + dy * dy);
    const vx = (dx / dist) * ENTITY_SPEED;
    const vy = (dy / dist) * ENTITY_SPEED;

    // random RGB color
    const r = rng.int(u8);
    const g = rng.int(u8);
    const b = rng.int(u8);
    const color: u32 = (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);

    return .{
        .x = x,
        .y = y,
        .vx = vx,
        .vy = vy,
        .color = color,
    };
}

// tests

test "Entity struct has correct size" {
    // 5 fields: x, y, vx, vy (f32 = 4 bytes each) + color (u32 = 4 bytes)
    // 20 bytes total as per plan
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(Entity));
}

test "Entity can be created with initial values" {
    const entity = Entity{
        .x = 100.0,
        .y = 200.0,
        .vx = 1.5,
        .vy = -0.5,
        .color = 0x00FFFF,
    };

    try std.testing.expectEqual(@as(f32, 100.0), entity.x);
    try std.testing.expectEqual(@as(f32, 200.0), entity.y);
    try std.testing.expectEqual(@as(f32, 1.5), entity.vx);
    try std.testing.expectEqual(@as(f32, -0.5), entity.vy);
    try std.testing.expectEqual(@as(u32, 0x00FFFF), entity.color);
}

test "Entities init starts empty" {
    const entities = Entities.init();
    try std.testing.expectEqual(@as(usize, 0), entities.count);
}

test "Entities add increases count" {
    var entities = Entities.init();
    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    entities.add(&rng);
    try std.testing.expectEqual(@as(usize, 1), entities.count);

    entities.add(&rng);
    try std.testing.expectEqual(@as(usize, 2), entities.count);
}

test "Entities remove decreases count" {
    var entities = Entities.init();
    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    // add 5
    for (0..5) |_| entities.add(&rng);
    try std.testing.expectEqual(@as(usize, 5), entities.count);

    // remove 2
    entities.remove(2);
    try std.testing.expectEqual(@as(usize, 3), entities.count);

    // remove more than count
    entities.remove(100);
    try std.testing.expectEqual(@as(usize, 0), entities.count);
}

test "Entities reset clears all" {
    var entities = Entities.init();
    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    for (0..10) |_| entities.add(&rng);
    try std.testing.expectEqual(@as(usize, 10), entities.count);

    entities.reset();
    try std.testing.expectEqual(@as(usize, 0), entities.count);
}

test "spawnAtEdge creates entity on screen edge" {
    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    // spawn several and check they're on edges
    for (0..20) |_| {
        const entity = spawnAtEdge(&rng);
        const on_left = entity.x == 0;
        const on_right = entity.x == @as(f32, @floatFromInt(SCREEN_WIDTH));
        const on_top = entity.y == 0;
        const on_bottom = entity.y == @as(f32, @floatFromInt(SCREEN_HEIGHT));

        try std.testing.expect(on_left or on_right or on_top or on_bottom);
    }
}

test "spawnAtEdge velocity points toward center" {
    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    for (0..20) |_| {
        const entity = spawnAtEdge(&rng);

        // after one step, should be closer to center
        const dist_before = @sqrt((entity.x - CENTER_X) * (entity.x - CENTER_X) +
            (entity.y - CENTER_Y) * (entity.y - CENTER_Y));

        const new_x = entity.x + entity.vx;
        const new_y = entity.y + entity.vy;
        const dist_after = @sqrt((new_x - CENTER_X) * (new_x - CENTER_X) +
            (new_y - CENTER_Y) * (new_y - CENTER_Y));

        try std.testing.expect(dist_after < dist_before);
    }
}

test "spawnAtEdge velocity has correct speed" {
    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    const entity = spawnAtEdge(&rng);
    const speed = @sqrt(entity.vx * entity.vx + entity.vy * entity.vy);

    try std.testing.expectApproxEqAbs(ENTITY_SPEED, speed, 0.001);
}

test "update moves entities by velocity" {
    var entities = Entities.init();
    // manually place an entity
    entities.items[0] = .{
        .x = 100.0,
        .y = 100.0,
        .vx = 2.0,
        .vy = 3.0,
        .color = 0x00FFFF,
    };
    entities.count = 1;

    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    update(&entities, &rng);

    try std.testing.expectApproxEqAbs(@as(f32, 102.0), entities.items[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 103.0), entities.items[0].y, 0.001);
}

test "update respawns entity at edge when reaching center" {
    var entities = Entities.init();
    // place entity very close to center (within threshold)
    entities.items[0] = .{
        .x = CENTER_X + 1.0,
        .y = CENTER_Y + 1.0,
        .vx = -1.0,
        .vy = -1.0,
        .color = 0x00FFFF,
    };
    entities.count = 1;

    var prng = std.Random.DefaultPrng.init(12345);
    var rng = prng.random();

    // after update, entity moves to center and should respawn
    update(&entities, &rng);

    // should now be on an edge
    const entity = entities.items[0];
    const on_left = entity.x == 0;
    const on_right = entity.x == @as(f32, @floatFromInt(SCREEN_WIDTH));
    const on_top = entity.y == 0;
    const on_bottom = entity.y == @as(f32, @floatFromInt(SCREEN_HEIGHT));

    try std.testing.expect(on_left or on_right or on_top or on_bottom);
}

// GPU entity for SSBO rendering (16 bytes, matches compute shader layout)
pub const GpuEntity = extern struct {
    x: f32,
    y: f32,
    packed_vel: i32, // vx high 16 bits, vy low 16 bits (fixed-point 8.8)
    color: u32,
};

// pack two f32 velocities into a single i32 (fixed-point 8.8 format)
pub fn packVelocity(vx: f32, vy: f32) i32 {
    const vx_fixed: i16 = @intFromFloat(std.math.clamp(vx * 256.0, -32768.0, 32767.0));
    const vy_fixed: i16 = @intFromFloat(std.math.clamp(vy * 256.0, -32768.0, 32767.0));
    return (@as(i32, vx_fixed) << 16) | (@as(i32, vy_fixed) & 0xFFFF);
}

test "GpuEntity struct has correct size for SSBO" {
    // SSBO layout: x(4) + y(4) + packed_vel(4) + color(4) = 16 bytes
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(GpuEntity));
}

test "GpuEntity can be created from Entity" {
    const entity = Entity{
        .x = 100.0,
        .y = 200.0,
        .vx = 1.5,
        .vy = -0.5,
        .color = 0x00FFFF,
    };

    const gpu_entity = GpuEntity{
        .x = entity.x,
        .y = entity.y,
        .packed_vel = packVelocity(entity.vx, entity.vy),
        .color = entity.color,
    };

    try std.testing.expectEqual(@as(f32, 100.0), gpu_entity.x);
    try std.testing.expectEqual(@as(f32, 200.0), gpu_entity.y);
    try std.testing.expectEqual(@as(u32, 0x00FFFF), gpu_entity.color);

    // unpack and verify velocity (should round-trip within precision)
    const vx_unpacked = @as(f32, @floatFromInt(@as(i16, @truncate(gpu_entity.packed_vel >> 16)))) / 256.0;
    const vy_unpacked = @as(f32, @floatFromInt(@as(i16, @truncate(gpu_entity.packed_vel)))) / 256.0;
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), vx_unpacked, 0.004);
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), vy_unpacked, 0.004);
}

test "packVelocity round-trips correctly" {
    // test positive values
    const packed1 = packVelocity(2.0, 1.5);
    const vx1 = @as(f32, @floatFromInt(@as(i16, @truncate(packed1 >> 16)))) / 256.0;
    const vy1 = @as(f32, @floatFromInt(@as(i16, @truncate(packed1)))) / 256.0;
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), vx1, 0.004);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), vy1, 0.004);

    // test negative values
    const packed2 = packVelocity(-1.0, -2.5);
    const vx2 = @as(f32, @floatFromInt(@as(i16, @truncate(packed2 >> 16)))) / 256.0;
    const vy2 = @as(f32, @floatFromInt(@as(i16, @truncate(packed2)))) / 256.0;
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), vx2, 0.004);
    try std.testing.expectApproxEqAbs(@as(f32, -2.5), vy2, 0.004);

    // test zero
    const packed3 = packVelocity(0.0, 0.0);
    try std.testing.expectEqual(@as(i32, 0), packed3);
}
