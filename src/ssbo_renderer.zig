// SSBO-based instanced rendering for entities
// reduces per-entity GPU bandwidth from 64 bytes (matrices) to 12 bytes (x, y, color)

const std = @import("std");
const rl = @import("raylib");
const ztracy = @import("ztracy");
const sandbox = @import("sandbox.zig");

const SCREEN_WIDTH = sandbox.SCREEN_WIDTH;
const SCREEN_HEIGHT = sandbox.SCREEN_HEIGHT;

// shaders embedded at build time
const vert_source = @embedFile("shaders/entity.vert");
const frag_source = @embedFile("shaders/entity.frag");

pub const SsboRenderer = struct {
    shader_id: u32,
    vao_id: u32,
    vbo_id: u32,
    ssbo_id: u32,
    screen_size_loc: i32,
    circle_texture_loc: i32,
    zoom_loc: i32,
    pan_loc: i32,
    circle_texture_id: u32,
    gpu_buffer: []sandbox.GpuEntity,

    const QUAD_SIZE: f32 = 16.0;

    // quad vertices: position (x, y) and texcoord (u, v)
    // centered at origin, size 1x1
    const quad_vertices = [_]f32{
        // pos        // texcoord
        -0.5, -0.5, 0.0, 1.0, // bottom-left
        0.5, -0.5, 1.0, 1.0, // bottom-right
        0.5, 0.5, 1.0, 0.0, // top-right
        -0.5, -0.5, 0.0, 1.0, // bottom-left
        0.5, 0.5, 1.0, 0.0, // top-right
        -0.5, 0.5, 0.0, 0.0, // top-left
    };

    pub fn init(circle_texture: rl.Texture2D) ?SsboRenderer {
        // allocate GPU buffer for entity data
        const gpu_buffer = std.heap.page_allocator.alloc(sandbox.GpuEntity, sandbox.MAX_ENTITIES) catch {
            std.debug.print("ssbo: failed to allocate gpu_buffer\n", .{});
            return null;
        };

        const shader_id = rl.gl.rlLoadShaderCode(vert_source, frag_source);
        if (shader_id == 0) {
            std.debug.print("ssbo: failed to compile shaders\n", .{});
            std.heap.page_allocator.free(gpu_buffer);
            return null;
        }

        // get uniform locations
        const screen_size_loc = rl.gl.rlGetLocationUniform(shader_id, "screenSize");
        const circle_texture_loc = rl.gl.rlGetLocationUniform(shader_id, "circleTexture");
        const zoom_loc = rl.gl.rlGetLocationUniform(shader_id, "zoom");
        const pan_loc = rl.gl.rlGetLocationUniform(shader_id, "pan");

        if (screen_size_loc < 0) {
            std.debug.print("ssbo: warning - screenSize uniform not found\n", .{});
        }
        if (circle_texture_loc < 0) {
            std.debug.print("ssbo: warning - circleTexture uniform not found\n", .{});
        }

        // create VAO
        const vao_id = rl.gl.rlLoadVertexArray();
        if (vao_id == 0) {
            std.debug.print("ssbo: failed to create VAO\n", .{});
            rl.gl.rlUnloadShaderProgram(shader_id);
            std.heap.page_allocator.free(gpu_buffer);
            return null;
        }
        _ = rl.gl.rlEnableVertexArray(vao_id);

        // create VBO with quad vertices
        const vbo_id = rl.gl.rlLoadVertexBuffer(&quad_vertices, @sizeOf(@TypeOf(quad_vertices)), false);
        if (vbo_id == 0) {
            std.debug.print("ssbo: failed to create VBO\n", .{});
            rl.gl.rlUnloadVertexArray(vao_id);
            rl.gl.rlUnloadShaderProgram(shader_id);
            std.heap.page_allocator.free(gpu_buffer);
            return null;
        }

        // IMPORTANT: bind VBO before setting vertex attributes
        // glVertexAttribPointer records the currently bound VBO
        rl.gl.rlEnableVertexBuffer(vbo_id);

        // setup vertex attributes
        // position: location 0, 2 floats
        rl.gl.rlSetVertexAttribute(0, 2, rl.gl.rl_float, false, 4 * @sizeOf(f32), 0);
        rl.gl.rlEnableVertexAttribute(0);

        // texcoord: location 1, 2 floats
        rl.gl.rlSetVertexAttribute(1, 2, rl.gl.rl_float, false, 4 * @sizeOf(f32), 2 * @sizeOf(f32));
        rl.gl.rlEnableVertexAttribute(1);

        // create SSBO for entity data (16 bytes per entity, 1M entities = 16MB)
        const ssbo_size: u32 = @intCast(sandbox.MAX_ENTITIES * @sizeOf(sandbox.GpuEntity));
        const ssbo_id = rl.gl.rlLoadShaderBuffer(ssbo_size, null, rl.gl.rl_dynamic_draw);
        if (ssbo_id == 0) {
            std.debug.print("ssbo: failed to create SSBO\n", .{});
            rl.gl.rlUnloadVertexBuffer(vbo_id);
            rl.gl.rlUnloadVertexArray(vao_id);
            rl.gl.rlUnloadShaderProgram(shader_id);
            std.heap.page_allocator.free(gpu_buffer);
            return null;
        }

        // unbind VAO
        _ = rl.gl.rlEnableVertexArray(0);

        return .{
            .shader_id = shader_id,
            .vao_id = vao_id,
            .vbo_id = vbo_id,
            .ssbo_id = ssbo_id,
            .screen_size_loc = screen_size_loc,
            .circle_texture_loc = circle_texture_loc,
            .zoom_loc = zoom_loc,
            .pan_loc = pan_loc,
            .circle_texture_id = circle_texture.id,
            .gpu_buffer = gpu_buffer,
        };
    }

    pub fn deinit(self: *SsboRenderer) void {
        rl.gl.rlUnloadShaderBuffer(self.ssbo_id);
        rl.gl.rlUnloadVertexBuffer(self.vbo_id);
        rl.gl.rlUnloadVertexArray(self.vao_id);
        rl.gl.rlUnloadShaderProgram(self.shader_id);
        std.heap.page_allocator.free(self.gpu_buffer);
    }

    pub fn render(self: *SsboRenderer, entities: *const sandbox.Entities, zoom: f32, pan: @Vector(2, f32)) void {
        if (entities.count == 0) return;

        // flush raylib's internal render batch before our custom GL calls
        rl.gl.rlDrawRenderBatchActive();

        // copy entity data to GPU buffer (position + packed velocity + color)
        {
            const zone = ztracy.ZoneN(@src(), "ssbo_copy");
            defer zone.End();
            for (entities.items[0..entities.count], 0..) |entity, i| {
                self.gpu_buffer[i] = .{
                    .x = entity.x,
                    .y = entity.y,
                    .packed_vel = sandbox.packVelocity(entity.vx, entity.vy),
                    .color = entity.color,
                };
            }
        }

        // upload to SSBO
        {
            const zone = ztracy.ZoneN(@src(), "ssbo_upload");
            defer zone.End();
            const data_size: u32 = @intCast(entities.count * @sizeOf(sandbox.GpuEntity));
            rl.gl.rlUpdateShaderBuffer(self.ssbo_id, self.gpu_buffer.ptr, data_size, 0);
        }

        // bind shader
        rl.gl.rlEnableShader(self.shader_id);

        // set screenSize uniform
        const screen_size = [2]f32{ @floatFromInt(SCREEN_WIDTH), @floatFromInt(SCREEN_HEIGHT) };
        rl.gl.rlSetUniform(self.screen_size_loc, &screen_size, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_vec2), 1);

        // set zoom uniform
        rl.gl.rlSetUniform(self.zoom_loc, &zoom, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_float), 1);

        // set pan uniform
        const pan_arr = [2]f32{ pan[0], pan[1] };
        rl.gl.rlSetUniform(self.pan_loc, &pan_arr, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_vec2), 1);

        // bind texture
        rl.gl.rlActiveTextureSlot(0);
        rl.gl.rlEnableTexture(self.circle_texture_id);
        // use rlSetUniform with int type instead of rlSetUniformSampler
        const tex_unit: i32 = 0;
        rl.gl.rlSetUniform(self.circle_texture_loc, &tex_unit, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_int), 1);

        // bind SSBO to binding point 0
        rl.gl.rlBindShaderBuffer(self.ssbo_id, 0);

        // enable blending for transparency
        rl.gl.rlEnableColorBlend();
        rl.gl.rlSetBlendMode(@intFromEnum(rl.gl.rlBlendMode.rl_blend_alpha));

        // bind VAO and draw
        {
            const zone = ztracy.ZoneN(@src(), "ssbo_draw");
            defer zone.End();
            _ = rl.gl.rlEnableVertexArray(self.vao_id);
            rl.gl.rlEnableVertexBuffer(self.vbo_id);
            rl.gl.rlDrawVertexArrayInstanced(0, 6, @intCast(entities.count));
        }

        // cleanup - restore raylib's expected state
        rl.gl.rlDisableVertexArray();
        rl.gl.rlDisableVertexBuffer();
        rl.gl.rlBindShaderBuffer(0, 0); // unbind SSBO
        rl.gl.rlDisableTexture();

        // re-enable raylib's default shader
        rl.gl.rlEnableShader(rl.gl.rlGetShaderIdDefault());
    }
};
