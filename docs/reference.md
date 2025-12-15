# quick reference

## fixed-point math

32.32 format: 32 integer bits, 32 fractional bits.

```zig
const Fixed = struct { raw: i64 };

// constants
const ONE = Fixed{ .raw = 1 << 32 };
const HALF = Fixed{ .raw = 1 << 31 };
const PI = Fixed{ .raw = 13493037705 };  // pi * 2^32

// from int
Fixed{ .raw = @as(i64, n) << 32 }

// to float (rendering only!)
@as(f32, @floatFromInt(f.raw)) / 4294967296.0

// add/sub: direct
a.raw + b.raw
a.raw - b.raw

// mul: widen to i128
@intCast((@as(i128, a.raw) * b.raw) >> 32)

// div: shift first
@intCast(@divTrunc(@as(i128, a.raw) << 32, b.raw))
```

## trig lookup tables

generate at comptime:

```zig
const TABLE_SIZE = 1024;
const sin_table: [TABLE_SIZE]Fixed = blk: {
    var table: [TABLE_SIZE]Fixed = undefined;
    for (0..TABLE_SIZE) |i| {
        const angle = @as(f64, @floatFromInt(i)) * std.math.pi * 2.0 / TABLE_SIZE;
        const s = @sin(angle);
        table[i] = .{ .raw = @intFromFloat(s * 4294967296.0) };
    }
    break :blk table;
};

pub fn sin(angle: Fixed) Fixed {
    // angle in radians, normalize to table index
    const two_pi = Fixed{ .raw = 26986075409 };  // 2*pi * 2^32
    var a = @mod(angle.raw, two_pi.raw);
    if (a < 0) a += two_pi.raw;
    const idx = @as(usize, @intCast((a * TABLE_SIZE) >> 32)) % TABLE_SIZE;
    return sin_table[idx];
}

pub fn cos(angle: Fixed) Fixed {
    const half_pi = Fixed{ .raw = 6746518852 };  // pi/2 * 2^32
    return sin(Fixed{ .raw = angle.raw + half_pi.raw });
}
```

## networking

### packet format

```
byte 0:     packet type
bytes 1-4:  frame number (u32 little-endian)
byte 5:     player id
bytes 6-9:  checksum (u32 little-endian)
bytes 10+:  payload
```

### packet types

| type | id   | payload |
|------|------|---------|
| INPUT | 0x01 | move(i8), angle_delta(i8), power_delta(i8), fire(u8) |
| SYNC  | 0x02 | full GameState blob |
| PING  | 0x03 | timestamp(u64) |
| PONG  | 0x04 | original timestamp(u64) |

### zig udp basics

```zig
const std = @import("std");
const net = std.net;

// create socket
const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
defer std.posix.close(sock);

// bind (server)
const addr = net.Address.initIp4(.{ 0, 0, 0, 0 }, 7777);
try std.posix.bind(sock, &addr.any, addr.getLen());

// send
const dest = net.Address.initIp4(.{ 127, 0, 0, 1 }, 7777);
_ = try std.posix.sendto(sock, &packet_bytes, 0, &dest.any, dest.getLen());

// receive
var buf: [1024]u8 = undefined;
var src_addr: std.posix.sockaddr = undefined;
var src_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
const len = try std.posix.recvfrom(sock, &buf, 0, &src_addr, &src_len);
```

## raylib-zig setup

### build.zig.zon

```zig
.{
    .name = "lofivor",
    .version = "0.0.1",
    .dependencies = .{
        .raylib_zig = .{
            .url = "git+https://github.com/Not-Nik/raylib-zig#devel",
            .hash = "...",  // zig fetch will tell you
        },
    },
}
```

### build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "lofivor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
    exe.linkLibrary(raylib_dep.artifact("raylib"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "run the game");
    run_step.dependOn(&run_cmd.step);
}
```

### basic window

```zig
const rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(800, 600, "lofivor");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        rl.drawText("hello", 10, 10, 20, rl.Color.white);
    }
}
```

## rendering glow effect

### render texture + shader

```zig
const rl = @import("raylib");

// load shader
const blur_shader = rl.loadShader(null, "shaders/blur.fs");
defer rl.unloadShader(blur_shader);

// create render textures
const game_tex = rl.loadRenderTexture(800, 600);
const blur_tex = rl.loadRenderTexture(800, 600);
defer rl.unloadRenderTexture(game_tex);
defer rl.unloadRenderTexture(blur_tex);

// in game loop:

// 1. draw game to texture
rl.beginTextureMode(game_tex);
rl.clearBackground(.{ .r = 10, .g = 10, .b = 18, .a = 255 });
drawGame(&state);
rl.endTextureMode();

// 2. blur pass (horizontal)
rl.beginTextureMode(blur_tex);
rl.beginShaderMode(blur_shader);
// set direction uniform to (1, 0)
rl.drawTextureRec(game_tex.texture, .{ .x = 0, .y = 0, .width = 800, .height = -600 }, .{ .x = 0, .y = 0 }, .white);
rl.endShaderMode();
rl.endTextureMode();

// 3. blur pass (vertical) + composite
rl.beginDrawing();
// draw original
rl.drawTextureRec(game_tex.texture, .{ .x = 0, .y = 0, .width = 800, .height = -600 }, .{ .x = 0, .y = 0 }, .white);
// additive blend blurred
rl.beginBlendMode(.additive);
rl.beginShaderMode(blur_shader);
// set direction uniform to (0, 1)
rl.drawTextureRec(blur_tex.texture, .{ .x = 0, .y = 0, .width = 800, .height = -600 }, .{ .x = 0, .y = 0 }, .white);
rl.endShaderMode();
rl.endBlendMode();
rl.endDrawing();
```

### drawing lines

```zig
// basic line
rl.drawLine(x1, y1, x2, y2, color);

// thick line
rl.drawLineEx(.{ .x = x1, .y = y1 }, .{ .x = x2, .y = y2 }, thickness, color);

// terrain as connected lines
for (0..SCREEN_WIDTH - 1) |x| {
    const y1 = SCREEN_HEIGHT - terrain.heights[x].toInt();
    const y2 = SCREEN_HEIGHT - terrain.heights[x + 1].toInt();
    rl.drawLine(@intCast(x), y1, @intCast(x + 1), y2, .{ .r = 0, .g = 255, .b = 0, .a = 255 });
}
```

## checksum

```zig
pub fn checksum(state: *const GameState) u32 {
    var h = std.hash.Fnv1a_32.init();
    h.update(std.mem.asBytes(&state.tick));
    h.update(std.mem.asBytes(&state.players));
    h.update(std.mem.asBytes(&state.wind.raw));
    if (state.projectile) |p| h.update(std.mem.asBytes(&p));
    return h.final();
}
```

## common fixed-point constants

```zig
pub const ZERO = Fixed{ .raw = 0 };
pub const ONE = Fixed{ .raw = 1 << 32 };
pub const HALF = Fixed{ .raw = 1 << 31 };
pub const TWO = Fixed{ .raw = 2 << 32 };
pub const PI = Fixed{ .raw = 13493037705 };
pub const TWO_PI = Fixed{ .raw = 26986075409 };
pub const HALF_PI = Fixed{ .raw = 6746518852 };

// game constants
pub const GRAVITY = Fixed{ .raw = 42949673 };     // ~0.01
pub const WIND_FACTOR = Fixed{ .raw = 4294967 };  // ~0.001
pub const MAX_POWER = Fixed{ .raw = 100 << 32 };
```
