// fixed-point math module
// 32.32 format: 32 integer bits, 32 fractional bits
// deterministic across all platforms - no floats in simulation

const std = @import("std");

pub const Fixed = struct {
    raw: i64,

    pub const FRAC_BITS = 32;
    pub const SCALE: i64 = 1 << FRAC_BITS;

    // common constants
    pub const ZERO: Fixed = .{ .raw = 0 };
    pub const ONE: Fixed = .{ .raw = SCALE };
    pub const HALF: Fixed = .{ .raw = SCALE >> 1 };
    pub const TWO: Fixed = .{ .raw = SCALE << 1 };
    pub const NEG_ONE: Fixed = .{ .raw = -SCALE };

    // mathematical constants (precomputed)
    pub const PI: Fixed = .{ .raw = 13493037705 }; // pi * 2^32
    pub const TWO_PI: Fixed = .{ .raw = 26986075409 }; // 2*pi * 2^32
    pub const HALF_PI: Fixed = .{ .raw = 6746518852 }; // pi/2 * 2^32

    // game constants
    pub const GRAVITY: Fixed = .{ .raw = 42949673 }; // ~0.01
    pub const WIND_FACTOR: Fixed = .{ .raw = 4294967 }; // ~0.001
    pub const MAX_POWER: Fixed = .{ .raw = 100 << 32 };

    pub fn fromInt(n: i32) Fixed {
        return .{ .raw = @as(i64, n) << FRAC_BITS };
    }

    pub fn fromFloat(comptime f: f64) Fixed {
        return .{ .raw = @intFromFloat(f * @as(f64, SCALE)) };
    }

    // only for rendering - never use in simulation!
    pub fn toFloat(self: Fixed) f32 {
        return @as(f32, @floatFromInt(self.raw)) / @as(f32, @floatFromInt(SCALE));
    }

    pub fn toInt(self: Fixed) i32 {
        return @intCast(self.raw >> FRAC_BITS);
    }

    pub fn add(a: Fixed, b: Fixed) Fixed {
        return .{ .raw = a.raw + b.raw };
    }

    pub fn sub(a: Fixed, b: Fixed) Fixed {
        return .{ .raw = a.raw - b.raw };
    }

    pub fn mul(a: Fixed, b: Fixed) Fixed {
        // widen to i128 to avoid overflow
        const wide = @as(i128, a.raw) * @as(i128, b.raw);
        return .{ .raw = @intCast(wide >> FRAC_BITS) };
    }

    pub fn div(a: Fixed, b: Fixed) Fixed {
        const wide = @as(i128, a.raw) << FRAC_BITS;
        return .{ .raw = @intCast(@divTrunc(wide, b.raw)) };
    }

    pub fn neg(self: Fixed) Fixed {
        return .{ .raw = -self.raw };
    }

    pub fn abs(self: Fixed) Fixed {
        return .{ .raw = if (self.raw < 0) -self.raw else self.raw };
    }

    pub fn lessThan(a: Fixed, b: Fixed) bool {
        return a.raw < b.raw;
    }

    pub fn greaterThan(a: Fixed, b: Fixed) bool {
        return a.raw > b.raw;
    }

    pub fn lessThanOrEqual(a: Fixed, b: Fixed) bool {
        return a.raw <= b.raw;
    }

    pub fn greaterThanOrEqual(a: Fixed, b: Fixed) bool {
        return a.raw >= b.raw;
    }

    pub fn eq(a: Fixed, b: Fixed) bool {
        return a.raw == b.raw;
    }

    pub fn min(a: Fixed, b: Fixed) Fixed {
        return if (a.raw < b.raw) a else b;
    }

    pub fn max(a: Fixed, b: Fixed) Fixed {
        return if (a.raw > b.raw) a else b;
    }

    pub fn clamp(self: Fixed, lo: Fixed, hi: Fixed) Fixed {
        return max(lo, min(hi, self));
    }

    // format for debug printing
    pub fn format(
        self: Fixed,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:.4}", .{self.toFloat()});
    }
};

test "fixed point basic ops" {
    const a = Fixed.fromInt(10);
    const b = Fixed.fromInt(3);

    // add
    try std.testing.expectEqual(@as(i32, 13), a.add(b).toInt());

    // sub
    try std.testing.expectEqual(@as(i32, 7), a.sub(b).toInt());

    // mul
    try std.testing.expectEqual(@as(i32, 30), a.mul(b).toInt());

    // div
    try std.testing.expectEqual(@as(i32, 3), a.div(b).toInt());
}

test "fixed point fractional" {
    const half = Fixed.HALF;
    const one = Fixed.ONE;
    const two = Fixed.TWO;

    try std.testing.expectEqual(@as(i32, 0), half.toInt());
    try std.testing.expectEqual(@as(i32, 1), one.toInt());
    try std.testing.expectEqual(@as(i32, 2), two.toInt());

    // half + half = one
    try std.testing.expect(half.add(half).eq(one));
}
