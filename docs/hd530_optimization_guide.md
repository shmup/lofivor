# intel hd 530 optimization guide for lofivor

based on hardware specs and empirical testing.

## hardware constraints

from `intel_hd_graphics_530.txt`:

| resource   | value               | implication                                 |
| ---------- | -------             | -------------                               |
| ROPs       | 3                   | fill rate limited - this is our ceiling     |
| TMUs       | 24                  | texture sampling is relatively fast         |
| memory     | shared DDR4 ~30GB/s | bandwidth is precious, no VRAM              |
| pixel rate | 2.85 GPixel/s       | max theoretical throughput                  |
| EUs        | 24 (192 ALUs)       | decent compute, weak vs discrete            |
| L3 cache   | 768 KB              | small, cache misses hurt                    |

the bottleneck is ROPs (fill rate), not vertices or compute.

## what works (proven)

### SSBO instance data
- 16 bytes per entity vs 64 bytes (matrices)
- minimizes bandwidth on shared memory bus
- result: ~5x improvement over instancing

### compute shader updates
- GPU does position/velocity updates
- no CPU→GPU sync per frame
- result: update time essentially free

### texture sampling
- 22.8 GTexel/s is fast relative to other units
- pre-baked circle texture beats procedural math
- result: 2x faster than procedural fragment shader

### instanced triangles/quads
- most optimized driver path
- intel mesa heavily optimizes this
- result: baseline, hard to beat

## what doesn't work (proven)

### point sprites
- theoretically 6x fewer vertices
- reality: 2.4x SLOWER on this hardware
- triangle rasterizer is more optimized
- see `docs/point_sprites_experiment.md`

### procedural fragment shaders
- `length()`, `smoothstep()`, `discard` are expensive
- EUs are weaker than discrete GPUs
- `discard` breaks early-z optimization
- result: 3.7x slower than texture sampling

### complex fragment math
- only 24 EUs, each running 8 ALUs
- transcendentals (sqrt, sin, cos) are 4x slower than FMAD
- avoid in hot path

## what to try next (theoretical)

### likely to help

| technique                            | why it should work                      | expected gain            |
| -----------                          | -------------------                     | ---------------          |
| frustum culling (GPU)                | reduce fill rate, which is bottleneck   | 10-30% depending on view |
| smaller points when zoomed out (LOD) | fewer pixels per entity = less ROP work | 20-40%                   |
| early-z / depth pre-pass             | skip fragment work for occluded pixels  | moderate                 |

### unlikely to help

| technique                | why it won't help                         |
| -----------              | ------------------                        |
| more vertex optimization | already fill rate bound, not vertex bound |
| SIMD on CPU              | updates already on GPU                    |
| multithreading           | CPU isn't the bottleneck                  |
| different vertex layouts | negligible vs fill rate                   |

### uncertain (need to test)

| technique           | notes                                                 |
| -----------         | -------                                               |
| vulkan backend      | might have less driver overhead, or might not matter  |
| indirect draw calls | GPU decides what to render, but we're not CPU bound   |
| fp16 in shaders     | HD 530 has 2:1 fp16 ratio, might help fragment shader |

## key insights

1. fill rate is king - with only 3 ROPs, everything comes down to how many
   pixels we're writing. optimizations that don't reduce pixel count won't
   help.

2. shared memory hurts - no dedicated VRAM means CPU and GPU compete for
   bandwidth. keep data transfers minimal.

3. driver optimization matters - the "common path" (triangles) is more
   optimized than alternatives (points). don't be clever.

4. texture sampling is cheap - 22.8 GTexel/s is fast. prefer texture
   lookups over ALU math in fragment shaders.

5. avoid discard - breaks early-z, causes pipeline stalls. alpha blending
   is faster than discard.

## current ceiling

~950k entities @ 57fps (SSBO + compute + quads)

to go higher, we need to reduce fill rate:
- cull offscreen entities
- reduce entity size when zoomed out
- or accept lower fps at higher counts

## references

- intel gen9 compute architecture whitepaper
- empirical benchmarks in `benchmark_current_i56500t.log`
- point sprites experiment in `docs/point_sprites_experiment.md`
