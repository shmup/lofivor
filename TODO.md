# lofivor - build roadmap

survivor-like optimized for weak hardware. finding the performance ceiling first, then building the game.

## phase 1: sandbox stress test

- [x] create sandbox.zig (separate from existing game code)
- [x] entity struct (x, y, vx, vy, color)
- [x] flat array storage for entities
- [x] spawn entities at random screen edges
- [x] update loop: move toward center, respawn on arrival
- [x] render: filled circles (4px radius, cyan)
- [x] metrics overlay (entity count, frame time, update time, render time)
- [x] controls: +/- 100, shift +/- 1000, space pause, r reset

## phase 2: find the ceiling

- [x] test on i5-6500T / HD 530 @ 1280x1024
- [x] record entity count where 60fps breaks
- [x] identify bottleneck (CPU update vs GPU render)
- [x] document findings

findings (AMD Radeon test):
- 60fps breaks at ~5000 entities
- render-bound: update stays <1ms even at 30k entities, render time dominates
- individual drawCircle calls are the bottleneck

## phase 3: optimization experiments

based on phase 2 results:

- [x] batch rendering via texture blitting (10x improvement)
- [x] rlgl quad batching (2x improvement on top)
- [x] ~~if cpu-bound: SIMD, struct-of-arrays, multithreading~~ (not needed)
- [x] re-test after each change

findings:
- texture blitting: pre-render circle to texture, drawTexture() per entity
- rlgl batching: submit vertices directly via rl.gl, bypass drawTexture overhead
- baseline: 60fps @ ~5k entities
- after texture blitting: 60fps @ ~50k entities
- after rlgl batching: 60fps @ ~100k entities
- total: ~20x improvement from baseline
- see journal.txt for detailed benchmarks

further options (if needed):
- increase raylib batch buffer (currently 8192 vertices = 2048 quads per flush)
- GPU instancing (single draw call for all entities)
- or just move on - 100k @ 60fps is a solid ceiling

## phase 4: spatial partitioning

- [ ] uniform grid collision
- [ ] quadtree comparison
- [ ] measure ceiling with n² collision checks enabled

## phase 5: rendering experiments

- [x] increase raylib batch buffer (currently 8192 vertices = 2048 quads)
- [x] GPU instancing (single draw call for all entities)
- [x] SSBO instance data (12 bytes vs 64-byte matrices)
- [ ] compute shader entity updates (if raylib supports)
- [ ] compare OpenGL vs Vulkan backend

findings (i5-6500T / HD 530):
- batch buffer increase: ~140k @ 60fps (was ~100k)
- GPU instancing: ~150k @ 60fps - negligible gain over rlgl batching
- instancing doesn't help on integrated graphics (shared RAM, no PCIe savings)
- bottleneck is memory bandwidth, not draw call overhead
- rlgl batching is already near-optimal for this hardware

## future optimization concepts

- [ ] SIMD entity updates (AVX2/SSE)
- [ ] struct-of-arrays vs array-of-structs benchmark
- [ ] multithreaded update loop (thread pool)
- [ ] cache-friendly memory layouts
- [ ] LOD rendering (skip distant entities or reduce detail)
- [ ] frustum culling (only render visible)
- [ ] temporal techniques (update subset per frame)
- [ ] fixed-point vs floating-point math
