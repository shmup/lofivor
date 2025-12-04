// trig lookup tables - generated at comptime
// no @sin/@cos at runtime - fully deterministic

const std = @import("std");
const Fixed = @import("fixed.zig").Fixed;

pub const TABLE_SIZE = 1024;

// precomputed sin table at comptime
pub const sin_table: [TABLE_SIZE]Fixed = blk: {
    @setEvalBranchQuota(10000);
    var table: [TABLE_SIZE]Fixed = undefined;
    for (0..TABLE_SIZE) |i| {
        const angle = @as(f64, @floatFromInt(i)) * std.math.pi * 2.0 / @as(f64, TABLE_SIZE);
        const s = @sin(angle);
        table[i] = .{ .raw = @intFromFloat(s * @as(f64, Fixed.SCALE)) };
    }
    break :blk table;
};

// precomputed cos table at comptime
pub const cos_table: [TABLE_SIZE]Fixed = blk: {
    @setEvalBranchQuota(10000);
    var table: [TABLE_SIZE]Fixed = undefined;
    for (0..TABLE_SIZE) |i| {
        const angle = @as(f64, @floatFromInt(i)) * std.math.pi * 2.0 / @as(f64, TABLE_SIZE);
        const c = @cos(angle);
        table[i] = .{ .raw = @intFromFloat(c * @as(f64, Fixed.SCALE)) };
    }
    break :blk table;
};

// lookup sin from fixed-point angle (radians)
pub fn sin(angle: Fixed) Fixed {
    // normalize to [0, 2*pi)
    var a = @mod(angle.raw, Fixed.TWO_PI.raw);
    if (a < 0) a += Fixed.TWO_PI.raw;

    // convert to table index
    // idx = (a / TWO_PI) * TABLE_SIZE = (a * TABLE_SIZE) / TWO_PI
    const scaled = @as(u128, @intCast(a)) * TABLE_SIZE;
    const idx = @as(usize, @intCast(scaled / @as(u128, @intCast(Fixed.TWO_PI.raw)))) % TABLE_SIZE;

    return sin_table[idx];
}

// lookup cos from fixed-point angle (radians)
pub fn cos(angle: Fixed) Fixed {
    // normalize to [0, 2*pi)
    var a = @mod(angle.raw, Fixed.TWO_PI.raw);
    if (a < 0) a += Fixed.TWO_PI.raw;

    // convert to table index
    const scaled = @as(u128, @intCast(a)) * TABLE_SIZE;
    const idx = @as(usize, @intCast(scaled / @as(u128, @intCast(Fixed.TWO_PI.raw)))) % TABLE_SIZE;

    return cos_table[idx];
}

test "trig tables" {
    // sin(0) ~= 0
    const sin_0 = sin(Fixed.ZERO);
    try std.testing.expect(sin_0.abs().raw < Fixed.fromFloat(0.01).raw);

    // sin(pi/2) ~= 1
    const sin_half_pi = sin(Fixed.HALF_PI);
    try std.testing.expect(sin_half_pi.sub(Fixed.ONE).abs().raw < Fixed.fromFloat(0.01).raw);

    // cos(0) ~= 1
    const cos_0 = cos(Fixed.ZERO);
    try std.testing.expect(cos_0.sub(Fixed.ONE).abs().raw < Fixed.fromFloat(0.01).raw);

    // cos(pi/2) ~= 0
    const cos_half_pi = cos(Fixed.HALF_PI);
    try std.testing.expect(cos_half_pi.abs().raw < Fixed.fromFloat(0.01).raw);
}
