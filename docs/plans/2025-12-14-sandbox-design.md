# lofivor sandbox - stress test design

a minimal harness for finding entity count ceilings on weak hardware before designing game systems.

## goals

**purpose:** answer "how many simple entities can we update and render at 60fps?"

**target hardware:**
- primary: intel i5-6500T + HD 530 (thinkcentre m900) @ 1280x1024
- secondary: windows laptop for dev iteration

**what it does:**
- spawns colored circles that drift toward screen center
- manual controls to add/remove entities in real-time
- on-screen metrics: entity count, frame time (ms), update time, render time
- circles respawn at random edge when reaching center

**what it doesn't do (yet):**
- no collision detection
- no player input beyond entity count controls
- no game logic, damage, spawning waves
- no particles or visual effects

**success criteria:**
- locked 60fps with some meaningful entity count (finding that number is the goal)
- clear breakdown of where frame time goes (CPU update vs GPU render)
- stable enough to leave running while tweaking counts

## data structures

```zig
const Entity = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    color: u32,
};
```

simple flat array of entities. no ECS, no spatial partitioning, no indirection. measuring the baseline - fancy structures come later.

**memory budget:** 20 bytes per entity. 10k entities = 200KB (fits in L2 cache on skylake).

## update loop

```
for each entity:
    x += vx
    y += vy
    if distance_to_center < threshold:
        respawn at random edge
        recalculate vx, vy toward center
```

~5 float ops per entity per frame. no collision, no branching beyond respawn check.

**velocity:** on spawn, compute normalized direction to center, multiply by constant speed, store vx/vy.

## rendering

each frame:
1. clear screen (dark background #0a0a12)
2. draw all entities as filled circles (4px radius)
3. draw metrics overlay

**entity color:** cyan (#00ffff) - bright against dark background

**metrics overlay (top-left):**
```
entities: 5000
frame:    12.4ms
update:   8.2ms
render:   4.1ms
```

## controls

| key | action |
|-----|--------|
| `=` / `+` | add 100 entities |
| `-` | remove 100 entities |
| `shift + =` | add 1000 entities |
| `shift + -` | remove 1000 entities |
| `space` | pause update loop (render continues) |
| `r` | reset to 0 entities |

pause isolates render cost from update cost.

## what we're measuring

**key questions:**
1. what's the entity ceiling at 60fps? (where frame time crosses 16.6ms)
2. is it CPU-bound or GPU-bound? (compare update vs render time)
3. where does it fall apart? (gradual degradation or sudden cliff?)

**hypotheses to test:**
- HD 530 might struggle with thousands of individual draw calls (GPU-bound)
- if CPU-bound, update loop needs SIMD or better memory access
- skylake's 4 cores are untouched - parallelism is a future lever

## next steps based on results

| bottleneck | next experiment |
|------------|-----------------|
| render (draw calls) | batch rendering - instancing, sprite batches |
| update (CPU) | SIMD, struct-of-arrays layout, multithreading |
| both equally | optimize either for gains |

## stretch measurements

- memory bandwidth (cache-bound?)
- draw call count vs batched draws
- fixed-point vs float update cost comparison
