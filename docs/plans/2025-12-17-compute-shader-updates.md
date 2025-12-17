# compute shader entity updates

move entity position math to GPU, eliminate CPU→GPU sync per frame.

## context

current bottleneck: per-frame `rlUpdateShaderBuffer()` uploads all entity data from CPU to GPU. at 950k entities that's 19MB/frame. targeting 10M entities would be 160MB/frame.

solution: keep entity data on GPU entirely. compute shader updates positions, vertex shader renders. CPU just dispatches.

## data structures

**GpuEntity (16 bytes, std430):**
```glsl
struct Entity {
    float x;        // world position
    float y;
    int packedVel;  // vx high 16 bits, vy low 16 bits (fixed-point 8.8)
    uint color;     // 0xRRGGBB
};
```

**zig side:**
```zig
const GpuEntity = extern struct {
    x: f32,
    y: f32,
    packed_vel: i32,
    color: u32,
};

fn packVelocity(vx: f32, vy: f32) i32 {
    const vx_fixed: i16 = @intFromFloat(vx * 256.0);
    const vy_fixed: i16 = @intFromFloat(vy * 256.0);
    return (@as(i32, vx_fixed) << 16) | (@as(i32, vy_fixed) & 0xFFFF);
}
```

## compute shader

`src/shaders/entity_update.comp`:
```glsl
#version 430
layout(local_size_x = 256) in;

layout(std430, binding = 0) buffer Entities {
    Entity entities[];
};

uniform uint entityCount;
uniform uint frameNumber;
uniform vec2 screenSize;
uniform vec2 center;
uniform float respawnRadius;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= entityCount) return;

    Entity e = entities[id];

    // unpack velocity
    float vx = float(e.packedVel >> 16) / 256.0;
    float vy = float((e.packedVel << 16) >> 16) / 256.0;

    // update position
    e.x += vx;
    e.y += vy;

    // respawn check
    float dx = e.x - center.x;
    float dy = e.y - center.y;
    if (dx*dx + dy*dy < respawnRadius * respawnRadius) {
        // GPU RNG
        uint seed = id * 1103515245u + frameNumber * 12345u;
        seed = seed * 747796405u + 2891336453u;

        uint edge = seed & 3u;
        float t = float((seed >> 2) & 0xFFFFu) / 65535.0;

        // spawn on edge with velocity toward center
        // (full edge logic in implementation)
    }

    entities[id] = e;
}
```

## integration

raylib doesn't wrap compute shaders. use raw GL calls via `compute.zig`:

```zig
pub fn dispatch(entity_count: u32, frame: u32) void {
    gl.glUseProgram(program);
    gl.glUniform1ui(entity_count_loc, entity_count);
    gl.glUniform1ui(frame_loc, frame);
    // ... other uniforms

    const groups = (entity_count + 255) / 256;
    gl.glDispatchCompute(groups, 1, 1);
    gl.glMemoryBarrier(gl.GL_SHADER_STORAGE_BARRIER_BIT);
}
```

## frame flow

**before:**
```
CPU: update positions (5ms at 950k)
CPU: copy to gpu_buffer
CPU→GPU: rlUpdateShaderBuffer() ← bottleneck
GPU: render
```

**after:**
```
GPU: compute dispatch (~0ms CPU time)
GPU: memory barrier
GPU: render
```

## implementation steps

each step is a commit point if desired.

### step 1: GpuEntity struct expansion
- modify `GpuEntity` in sandbox.zig: add `packed_vel` field
- add `packVelocity()` helper
- update ssbo_renderer to handle 16-byte stride
- verify existing rendering still works

### step 2: compute shader infrastructure
- create `src/compute.zig` with GL bindings
- create `src/shaders/entity_update.comp` (position update only, no respawn yet)
- load and compile compute shader in sandbox_main.zig
- dispatch before render, verify positions update

### step 3: respawn logic
- add GPU RNG to compute shader
- implement edge spawning + velocity calculation
- remove CPU update loop from sandbox.zig

### step 4: cleanup
- remove dead code (cpu update, per-frame upload)
- add `--compute` flag to toggle (keep old path for comparison)
- benchmark and document results

## files changed

**new:**
- `src/shaders/entity_update.comp`
- `src/compute.zig`

**modified:**
- `src/sandbox.zig` — GpuEntity struct, packVelocity(), remove CPU update
- `src/ssbo_renderer.zig` — remove per-frame upload
- `src/sandbox_main.zig` — init compute, dispatch in frame loop

## risks

1. **driver quirks** — intel HD 530 compute support is fine but older, may hit edge cases
2. **debugging** — GPU code harder to debug, start with small counts
3. **fallback** — keep `--compute` flag to A/B test against existing SSBO path

## expected results

- CPU update time: ~5ms → ~0ms
- no per-frame buffer upload
- target: 1M+ entities, pushing toward 10M ceiling
