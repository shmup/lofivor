# lofivor artillery game - technical design

a deterministic lofivor networked artillery game in zig with vector-style glowing line visuals.

## why deterministic lofivor?

bandwidth scales with input size, not object count. send "fire at angle 45, power 80" instead of syncing projectile positions every frame. replay files are just input logs. certain cheats become impossible since all clients must agree on simulation.

the catch: simulation must be bitwise identical across all machines.

## architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         game loop                               │
├─────────────────────────────────────────────────────────────────┤
│  1. collect local input                                         │
│  2. send input to peer                                          │
│  3. wait for peer input (this is where latency shows)           │
│  4. apply both inputs deterministically (same order always)     │
│  5. advance simulation one tick                                 │
│  6. render (floats ok here, not in sim)                         │
└─────────────────────────────────────────────────────────────────┘
```

for artillery games, input delay is fine - it's turn-based-ish anyway.

## fixed-point math

floats are non-deterministic across compilers, optimization levels, and platforms. ints are always deterministic. fixed-point stores real numbers as ints.

using 32.32 fixed point (64-bit with 32 fractional bits):

```zig
pub const Fixed = struct {
    raw: i64,

    pub const FRAC_BITS = 32;
    pub const ONE: Fixed = .{ .raw = 1 << FRAC_BITS };

    pub fn fromInt(n: i32) Fixed {
        return .{ .raw = @as(i64, n) << FRAC_BITS };
    }

    pub fn toFloat(self: Fixed) f32 {
        // only for rendering, never in simulation
        return @as(f32, @floatFromInt(self.raw)) / @as(f32, @floatFromInt(@as(i64, 1) << FRAC_BITS));
    }

    pub fn add(a: Fixed, b: Fixed) Fixed {
        return .{ .raw = a.raw + b.raw };
    }

    pub fn mul(a: Fixed, b: Fixed) Fixed {
        // need i128 intermediate to avoid overflow
        const wide = @as(i128, a.raw) * @as(i128, b.raw);
        return .{ .raw = @intCast(wide >> FRAC_BITS) };
    }

    pub fn div(a: Fixed, b: Fixed) Fixed {
        const wide = @as(i128, a.raw) << FRAC_BITS;
        return .{ .raw = @intCast(@divTrunc(wide, b.raw)) };
    }
};
```

trig functions need lookup tables or taylor series with fixed-point - no `@sin()`.

## game state

minimal, fully serializable for checksums:

```zig
pub const GameState = struct {
    tick: u32,
    current_turn: u8,  // 0 or 1
    wind: Fixed,       // affects projectile horizontal velocity
    players: [2]Player,
    projectile: ?Projectile,
    terrain: Terrain,
    rng_state: u64,    // for any randomness (wind changes, etc)
};

pub const Player = struct {
    x: Fixed,
    cannon_angle: Fixed,  // radians, 0 to pi
    power: Fixed,         // 0 to 100
    health: i32,
    alive: bool,
};

pub const Projectile = struct {
    x: Fixed,
    y: Fixed,
    vx: Fixed,
    vy: Fixed,
};

pub const Terrain = struct {
    heights: [SCREEN_WIDTH]Fixed,  // height at each x pixel
};
```

## input structure

```zig
pub const Input = struct {
    move: i8,         // -1, 0, +1
    angle_delta: i8,  // -1, 0, +1 (scaled by some rate)
    power_delta: i8,  // -1, 0, +1
    fire: bool,
};

pub const InputPacket = struct {
    frame: u32,
    player_id: u8,
    input: Input,
    checksum: u32,  // hash of sender's game state
};
```

## networking

udp for speed. simple protocol:

```
packet types:
  0x01 INPUT    - InputPacket
  0x02 SYNC     - full GameState for initial sync / recovery
  0x03 PING     - latency measurement
  0x04 PONG     - ping response
```

connection flow:
1. host listens, guest connects
2. host sends SYNC with initial GameState
3. both start simulation
4. exchange INPUT packets each frame
5. compare checksums periodically

if checksums diverge = desync = bug to fix during development.

## simulation loop

```zig
pub fn simulate(state: *GameState, inputs: [2]Input) void {
    const current = state.current_turn;

    // apply input (only current player can act)
    applyInput(&state.players[current], inputs[current]);

    // update projectile if active
    if (state.projectile) |*proj| {
        // gravity (fixed-point constant)
        proj.vy = proj.vy.sub(GRAVITY);

        // wind affects horizontal
        proj.vx = proj.vx.add(state.wind.mul(WIND_FACTOR));

        // move
        proj.x = proj.x.add(proj.vx);
        proj.y = proj.y.add(proj.vy);

        // collision with terrain
        const terrain_y = state.terrain.heightAt(proj.x);
        if (proj.y.lessThan(terrain_y)) {
            handleExplosion(state, proj.x, proj.y);
            state.projectile = null;
            state.current_turn = 1 - current;  // switch turns
        }

        // collision with players
        for (&state.players, 0..) |*player, i| {
            if (player.alive and hitTest(proj, player)) {
                player.health -= DAMAGE;
                if (player.health <= 0) player.alive = false;
                handleExplosion(state, proj.x, proj.y);
                state.projectile = null;
                state.current_turn = 1 - current;
            }
        }

        // out of bounds
        if (proj.x.lessThan(Fixed.ZERO) or proj.x.greaterThan(SCREEN_WIDTH_FX)) {
            state.projectile = null;
            state.current_turn = 1 - current;
        }
    }

    state.tick += 1;
}
```

## rendering (the glow aesthetic)

vector/oscilloscope look with glowing lines. two approaches:

### approach a: multi-pass bloom (recommended)

1. draw lines to offscreen texture (dark background, bright lines)
2. horizontal gaussian blur pass
3. vertical gaussian blur pass
4. composite: original + blurred (additive blend)

raylib-zig has shader support. bloom shader:

```glsl
// blur pass (run horizontal then vertical)
uniform sampler2D texture0;
uniform vec2 direction;  // (1,0) or (0,1)
uniform float blur_size;

void main() {
    vec4 sum = vec4(0.0);
    vec2 tc = gl_TexCoord[0].xy;

    // 9-tap gaussian
    sum += texture2D(texture0, tc - 4.0 * blur_size * direction) * 0.0162;
    sum += texture2D(texture0, tc - 3.0 * blur_size * direction) * 0.0540;
    sum += texture2D(texture0, tc - 2.0 * blur_size * direction) * 0.1216;
    sum += texture2D(texture0, tc - 1.0 * blur_size * direction) * 0.1945;
    sum += texture2D(texture0, tc) * 0.2270;
    sum += texture2D(texture0, tc + 1.0 * blur_size * direction) * 0.1945;
    sum += texture2D(texture0, tc + 2.0 * blur_size * direction) * 0.1216;
    sum += texture2D(texture0, tc + 3.0 * blur_size * direction) * 0.0540;
    sum += texture2D(texture0, tc + 4.0 * blur_size * direction) * 0.0162;

    gl_FragColor = sum;
}
```

### visual elements

- terrain: jagged line across bottom
- players: simple geometric shapes (triangle cannon on rectangle base)
- projectile: bright dot with trail (store last N positions)
- explosions: expanding circle that fades
- ui: angle/power indicators as line gauges

color palette:
- background: near-black (#0a0a12)
- player 1: cyan (#00ffff)
- player 2: magenta (#ff00ff)
- terrain: green (#00ff00)
- projectile: white/yellow (#ffff00)

## desync detection

```zig
pub fn computeChecksum(state: *const GameState) u32 {
    var hasher = std.hash.Fnv1a_32.init();
    // hash deterministic parts only
    hasher.update(std.mem.asBytes(&state.tick));
    hasher.update(std.mem.asBytes(&state.current_turn));
    hasher.update(std.mem.asBytes(&state.wind.raw));
    hasher.update(std.mem.asBytes(&state.players));
    if (state.projectile) |proj| {
        hasher.update(std.mem.asBytes(&proj));
    }
    hasher.update(std.mem.asBytes(&state.rng_state));
    // terrain could be large, maybe hash less frequently
    return hasher.final();
}
```

exchange checksums every N frames. mismatch = log full state dump for debugging.

## what not to do

- no floats in game logic (only rendering)
- no hashmap iteration (order not deterministic)
- no system time in simulation
- no `@sin()` / `@cos()` - use lookup tables
- no uninitialized memory in game state
- no pointers in serialized state

## dependencies

- zig 0.15.2
- raylib-zig (for windowing, input, rendering, shaders)

no physics libraries, no other third-party code in simulation.

## file structure

```
lofivor/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig          # entry, game loop
│   ├── fixed.zig         # fixed-point math
│   ├── trig.zig          # sin/cos lookup tables
│   ├── game.zig          # GameState, simulation
│   ├── input.zig         # Input handling
│   ├── net.zig           # UDP networking
│   ├── render.zig        # raylib drawing, bloom
│   └── terrain.zig       # terrain generation
├── shaders/
│   ├── blur.fs
│   └── composite.fs
├── docs/
│   ├── design.md         # this file
│   └── reference.md      # quick reference
└── TODO.md
```
