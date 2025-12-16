# lofivor optimizations

organized by performance goal. see journal.txt for detailed benchmarks.

## current ceiling

- **~150k entities @ 60fps** (i5-6500T / HD 530 integrated)
- **~260k entities @ 60fps** (AMD Radeon discrete)
- bottleneck: GPU-bound (update loop stays <1ms even at 200k+)

---

## completed optimizations

### rendering pipeline (GPU)

#### baseline: individual drawCircle

- technique: `rl.drawCircle()` per entity
- result: ~5k entities @ 60fps
- problem: each call = separate GPU draw call

#### optimization 1: texture blitting

- technique: pre-render circle to 16x16 texture, `drawTexture()` per entity
- result: ~50k entities @ 60fps
- improvement: **10x** over baseline
- why it works: raylib batches same-texture draws internally

#### optimization 2: rlgl quad batching

- technique: bypass `drawTexture()`, submit vertices directly via `rl.gl`
- result: ~100k entities @ 60fps
- improvement: **2x** over texture blitting, **20x** total
- why it works: eliminates per-call overhead, vertices go straight to GPU buffer

#### optimization 3: increased batch buffer

- technique: increase raylib batch buffer from 8192 to 32768 vertices
- result: ~140k entities @ 60fps (i5-6500T)
- improvement: **~40%** over default buffer
- why it works: fewer GPU flushes per frame

#### optimization 4: GPU instancing (tested, minimal gain)

- technique: `drawMeshInstanced()` with per-entity transform matrices
- result: ~150k entities @ 60fps (i5-6500T) - similar to rlgl batching
- improvement: **negligible** on integrated graphics
- why it didn't help:
  - integrated GPU shares system RAM (no PCIe transfer savings)
  - 64-byte Matrix per entity vs ~80 bytes for rlgl vertices (similar bandwidth)
  - bottleneck is memory bandwidth, not draw call overhead
  - rlgl batching already minimizes draw calls effectively
- note: may help more on discrete GPUs with dedicated VRAM

---

## future optimizations

### milestone: push GPU ceiling higher

these target the rendering bottleneck since update loop is already fast.

| technique              | description                                                          | expected gain                   |
| ---------------------- | -------------------------------------------------------------------- | ------------------------------- |
| SSBO instance data     | pack (x, y, color) = 12 bytes instead of 64-byte matrices            | moderate (less bandwidth)       |
| compute shader updates | move entity positions to GPU entirely, avoid CPU→GPU sync            | significant                     |
| OpenGL vs Vulkan       | test raylib's Vulkan backend                                         | unknown                         |
| discrete GPU testing   | test on dedicated GPU where instancing/SSBO shine                    | significant (different hw)      |

#### rendering culling

| technique          | description                              | expected gain          |
| ------------------ | ---------------------------------------- | ---------------------- |
| frustum culling    | skip entities outside view               | depends on game design |
| LOD rendering      | reduce detail for distant/small entities | moderate               |
| temporal rendering | update/render subset per frame           | moderate               |

---

### milestone: push CPU ceiling (when it becomes the bottleneck)

currently not the bottleneck - update stays <1ms at 100k. these become relevant when adding game logic, AI, or collision.

#### collision detection

| technique          | description                               | expected gain          |
| ------------------ | ----------------------------------------- | ---------------------- |
| uniform grid       | spatial hash, O(1) neighbor lookup        | high for dense scenes  |
| quadtree           | adaptive spatial partitioning             | high for sparse scenes |
| broad/narrow phase | cheap AABB check before precise collision | moderate               |

#### update loop

| technique        | description                                     | expected gain       |
| ---------------- | ----------------------------------------------- | ------------------- |
| SIMD (AVX2/SSE)  | vectorized position/velocity math               | 2-4x on update      |
| struct-of-arrays | cache-friendly memory layout for SIMD           | enables better SIMD |
| multithreading   | thread pool for parallel entity updates         | scales with cores   |
| fixed-point math | integer math, deterministic, potentially faster | minor-moderate      |

#### memory layout

| technique             | description                           | expected gain               |
| --------------------- | ------------------------------------- | --------------------------- |
| cache-friendly layout | hot data together, cold data separate | reduces cache misses        |
| entity pools          | pre-allocated, reusable entity slots  | reduces allocation overhead |
| component packing     | minimize struct padding               | better cache utilization    |

---

## testing methodology

1. set target entity count
2. run for 30+ seconds
3. record frame times (target: stable 16.7ms)
4. note when 60fps breaks
5. compare update_ms vs render_ms to identify bottleneck

see journal.txt for raw benchmark data.
