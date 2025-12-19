# lofivor optimizations

organized by performance goal. see journal.txt for detailed benchmarks.

## current ceiling

- **~700k entities @ 60fps** (i5-6500T / HD 530 integrated, SSBO)
- **~950k entities @ ~57fps** (i5-6500T / HD 530 integrated, SSBO)
- bottleneck: GPU-bound (update loop stays <5ms even at 950k)

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

#### optimization 5: SSBO instance data

- technique: pack entity data (x, y, color) into 12-byte struct, upload via SSBO
- result: **~700k entities @ 60fps** (i5-6500T / HD 530)
- improvement: **~5x** over previous best, **~140x** total from baseline
- comparison:
  - batch buffer (0.3.1): 60fps @ ~140k
  - GPU instancing (0.4.0): 60fps @ ~150k
  - SSBO: 60fps @ ~700k, ~57fps @ 950k
- why it works:
  - 12 bytes vs 64 bytes (matrices) = 5.3x less bandwidth
  - 12 bytes vs 80 bytes (rlgl vertices) = 6.7x less bandwidth
  - no CPU-side matrix calculations
  - GPU does NDC conversion and color unpacking
- implementation notes:
  - custom vertex shader reads from SSBO using `gl_InstanceID`
  - single `rlDrawVertexArrayInstanced()` call for all entities
  - gotcha: don't use `rlSetUniformSampler()` for custom GL code - use `rlSetUniform()` with int type instead (see `docs/raylib_rlSetUniformSampler_bug.md`)

---

## future optimizations

### milestone: push GPU ceiling higher

these target the rendering bottleneck since update loop is already fast.

| technique              | description                                                          | expected gain                   |
| ---------------------- | -------------------------------------------------------------------- | ------------------------------- |
| SSBO instance data     | pack (x, y, color) = 12 bytes instead of 64-byte matrices            | done - see optimization 5       |
| compute shader updates | move entity positions to GPU entirely, avoid CPU→GPU sync            | done - see optimization 6       |
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

#### estimated gains summary

| Optimization           | Expected Gain | Why                                               |
|------------------------|---------------|---------------------------------------------------|
| SIMD updates           | 0%            | Update already on GPU                             |
| Multithreaded update   | 0%            | Update already on GPU                             |
| Cache-friendly layouts | 0%            | CPU doesn't iterate entities                      |
| Fixed-point math       | 0% or worse   | GPUs are optimized for float                      |
| SoA vs AoS             | ~5%           | Only helps data upload, not bottleneck            |
| Frustum culling        | 5-15%         | Most entities converge to center anyway           |
| └─ caveat              | worse zoomed  | Culls entities but survivors are 100x larger pixels + overdraw |
| └─ fix: cap quad size  | untested      | Don't let quads grow past N pixels when zoomed    |
| └─ fix: skip near center | untested    | Entities about to respawn anyway, skip render     |
| └─ fix: opaque fallback | tested       | See frustum_culling branch notes below            |

---

### frustum_culling branch experiments

testing at 1M entities, comparing 1x zoom vs 10x zoom

#### baseline (main branch, no frustum culling)
- 1x zoom: ~56 FPS (18ms)
- 10x zoom: not tested on main

#### vertex shader frustum culling
- technique: discard off-screen entities by setting `gl_Position.z = -2.0`
- 1x zoom: 56 FPS (18ms) - no change, all entities visible anyway
- 10x zoom: 10 FPS (101ms) - **worse than expected**
- why it hurts zoomed in:
  - culling works (only ~1% of entities rendered)
  - but survivors are 10x larger = 100x more pixels per entity
  - massive overdraw from overlapping alpha-blended circles

#### attempt 1: alpha-test with discard
- technique: `if (alpha < 0.5) discard;` + disable blending
- 10x zoom: 9 FPS (107ms) - **slightly worse**
- why it failed:
  - `discard` defeats early-Z optimization
  - GPU must run fragment shader to know what to discard
  - no fragments skipped before shading

#### attempt 2: solid squares (no texture, no discard)
- technique: skip texture lookup entirely, output solid color
- 10x zoom: 14 FPS (70ms) - **~30% better**
- why it helped somewhat:
  - no discard = early-Z can work
  - no texture fetch = simpler shader
- why it's still slow:
  - still rasterizing massive overlapping quads
  - early-Z helps but doesn't eliminate all overdraw
  - fill rate limited on HD 530

#### remaining ideas to try
| idea | expected | notes |
|------|----------|-------|
| cap quad size | moderate | clamp max pixels, entities stop growing past Nx zoom |
| back-to-front sort | high | proper early-Z, but CPU sorting cost |
| depth pre-pass | high | 2 passes: depth-only then color, complex |
| point sprites | high | 1 vertex instead of 6, needs GL_POINTS |
| reduce entity density | high | fewer entities when zoomed = less overdraw |
| skip center entities | low | center is sparse anyway (black hole) |

#### current thinking
the core problem is **fill rate** - at 10x zoom we're trying to shade billions of pixels.
frustum culling reduces entity count but increases per-entity cost.
real fix probably needs to limit total pixels shaded, not just entity count.

---

| LOD rendering          | 20-40%        | Real gains - fewer fragments for distant entities |
| Temporal techniques    | ~50%          | But with visual artifacts (flickering)            |

Realistic total if you did everything: ~30-50% improvement

That'd take you from ~1.4M @ 38fps to maybe ~1.8-2M @ 38fps, or ~1.4M @ 50-55fps.

What would actually move the needle:
- GPU-side frustum culling in compute shader (cull before render, not after)
- Point sprites instead of quads for distant entities (4 vertices → 1)
- Indirect draw calls (GPU decides what to render, CPU never touches entity data)

Your real bottleneck is fill rate and vertex throughput on HD 530 integrated
graphics. The CPU side is already essentially free.



---

## testing methodology

1. set target entity count
2. run for 30+ seconds
3. record frame times (target: stable 16.7ms)
4. note when 60fps breaks
5. compare update_ms vs render_ms to identify bottleneck

see journal.txt for raw benchmark data.
