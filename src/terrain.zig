// terrain generation and collision
// deterministic - no floats, no randomness (for now)

const Fixed = @import("fixed.zig").Fixed;

pub const SCREEN_WIDTH: usize = 800;
pub const SCREEN_HEIGHT: usize = 600;

pub const Terrain = struct {
    heights: [SCREEN_WIDTH]Fixed,

    pub fn heightAt(self: *const Terrain, x: Fixed) Fixed {
        const ix = x.toInt();
        if (ix < 0) return Fixed.ZERO;
        if (ix >= SCREEN_WIDTH) return Fixed.ZERO;
        return self.heights[@intCast(ix)];
    }
};

// fixed pattern: parabolic hills for testing
// produces gentle rolling terrain
pub fn generateFixed() Terrain {
    var t: Terrain = undefined;
    for (0..SCREEN_WIDTH) |i| {
        // base height + parabolic hills
        // creates two bumps across the screen
        const base: i32 = 100;
        const x: i32 = @intCast(i);

        // two hills centered at x=200 and x=600
        const hill1 = hillHeight(x, 200, 80, 150);
        const hill2 = hillHeight(x, 600, 80, 150);

        const height = base + hill1 + hill2;
        t.heights[i] = Fixed.fromInt(height);
    }
    return t;
}

// parabolic hill: peak at center, width determines spread
fn hillHeight(x: i32, center: i32, peak: i32, width: i32) i32 {
    const dist = x - center;
    if (dist < -width or dist > width) return 0;
    // parabola: peak * (1 - (dist/width)^2)
    const ratio_sq = @divTrunc(dist * dist * 100, width * width);
    return @max(0, peak - @divTrunc(peak * ratio_sq, 100));
}

const std = @import("std");

test "terrain heightAt bounds" {
    const t = generateFixed();

    // valid positions return height
    const h = t.heightAt(Fixed.fromInt(400));
    try std.testing.expect(h.raw > 0);

    // out of bounds returns zero
    try std.testing.expect(t.heightAt(Fixed.fromInt(-10)).eq(Fixed.ZERO));
    try std.testing.expect(t.heightAt(Fixed.fromInt(900)).eq(Fixed.ZERO));
}

test "terrain has hills" {
    const t = generateFixed();

    // hill peaks should be higher than edges
    const edge = t.heightAt(Fixed.fromInt(0)).toInt();
    const peak1 = t.heightAt(Fixed.fromInt(200)).toInt();
    const peak2 = t.heightAt(Fixed.fromInt(600)).toInt();

    try std.testing.expect(peak1 > edge);
    try std.testing.expect(peak2 > edge);
}
