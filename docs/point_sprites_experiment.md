# point sprites experiment

branch: `point-sprites` (point-sprites work)
date: 2024-12
hardware: intel hd 530 (skylake gt2, i5-6500T)

## hypothesis

point sprites should be faster than quads because:
- 1 vertex per entity instead of 6 (quad = 2 triangles)
- less vertex throughput
- `gl_PointCoord` provides texture coords automatically

## implementation

### vertex shader changes
- removed quad vertex attributes (position, texcoord)
- use `gl_PointSize = 16.0 * zoom` for size control
- position calculated from SSBO data only

### fragment shader changes
- use `gl_PointCoord` instead of vertex texcoord
- sample circle texture for alpha

### renderer changes
- load `glEnable` and `glDrawArraysInstanced` via `rlGetProcAddress`
- enable `GL_PROGRAM_POINT_SIZE`
- draw with `glDrawArraysInstanced(GL_POINTS, 0, 1, count)`
- removed VBO (no vertex data needed)

## results

### attempt 1: procedural circle in fragment shader

```glsl
vec2 coord = gl_PointCoord - vec2(0.5);
float dist = length(coord);
float alpha = 1.0 - smoothstep(0.4, 0.5, dist);
if (alpha < 0.01) discard;
```

**benchmark @ 350k entities:**
- point sprites: 23ms render, 43fps
- quads (main): 6.2ms render, 151fps
- **result: 3.7x SLOWER**

**why:** `discard` breaks early-z optimization, `length()` and `smoothstep()` are ALU-heavy, intel integrated GPUs are weak at fragment shader math.

### attempt 2: texture sampling

```glsl
float alpha = texture(circleTexture, gl_PointCoord).r;
finalColor = vec4(fragColor, alpha);
```

**benchmark @ 450k entities:**
- point sprites: 19.1ms render, 52fps
- quads (main): 8.0ms render, 122fps
- **result: 2.4x SLOWER**

better than procedural, but still significantly slower than quads.

## analysis

the theoretical advantage (1/6 vertices) doesn't translate to real performance because:

1. **triangle path is more optimized** - intel's driver heavily optimizes the standard triangle rasterization path. point sprites use a less-traveled code path.

2. **fill rate is the bottleneck** - HD 530 has only 3 ROPs. we're bound by how fast we can write pixels, not by vertex count. reducing vertices from 6 to 1 doesn't help when fill rate is the constraint.

3. **point size overhead** - each point requires computing `gl_PointSize` and setting up the point sprite rasterization, which may have per-vertex overhead.

4. **texture cache behavior** - `gl_PointCoord` may have worse cache locality than explicit vertex texcoords.

## conclusion

**point sprites are a regression on intel hd 530.**

the optimization makes theoretical sense but fails in practice on this hardware. the quad/triangle path is simply more optimized in intel's mesa driver.

**keep this branch for testing on discrete GPUs** where point sprites might actually help (nvidia/amd have different optimization priorities).

## lessons learned

1. always benchmark, don't assume
2. "fewer vertices" doesn't always mean faster
3. integrated GPU optimization is different from discrete
4. the most optimized path is usually the most common path (triangles)
5. fill rate matters more than vertex count at high entity counts
