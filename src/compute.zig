// compute shader module for GPU entity updates
// wraps raw GL calls that raylib doesn't expose directly

const std = @import("std");
const rl = @import("raylib");
const sandbox = @import("sandbox.zig");

const comp_source = @embedFile("shaders/entity_update.comp");

// GL constants not exposed by raylib-zig
const GL_SHADER_STORAGE_BARRIER_BIT: u32 = 0x00002000;

// function pointer type for glMemoryBarrier
const GlMemoryBarrierFn = *const fn (barriers: u32) callconv(.c) void;

pub const ComputeShader = struct {
    program_id: u32,
    entity_count_loc: i32,
    frame_number_loc: i32,
    screen_size_loc: i32,
    center_loc: i32,
    respawn_radius_loc: i32,
    entity_speed_loc: i32,
    glMemoryBarrier: GlMemoryBarrierFn,

    pub fn init() ?ComputeShader {
        // load glMemoryBarrier dynamically
        const barrier_ptr = rl.gl.rlGetProcAddress("glMemoryBarrier");
        const glMemoryBarrier: GlMemoryBarrierFn = @ptrCast(barrier_ptr);

        // compile compute shader
        const shader_id = rl.gl.rlCompileShader(comp_source, rl.gl.rl_compute_shader);
        if (shader_id == 0) {
            std.debug.print("compute: failed to compile compute shader\n", .{});
            return null;
        }

        // link compute program
        const program_id = rl.gl.rlLoadComputeShaderProgram(shader_id);
        if (program_id == 0) {
            std.debug.print("compute: failed to link compute program\n", .{});
            return null;
        }

        // get uniform locations
        const entity_count_loc = rl.gl.rlGetLocationUniform(program_id, "entityCount");
        const frame_number_loc = rl.gl.rlGetLocationUniform(program_id, "frameNumber");
        const screen_size_loc = rl.gl.rlGetLocationUniform(program_id, "screenSize");
        const center_loc = rl.gl.rlGetLocationUniform(program_id, "center");
        const respawn_radius_loc = rl.gl.rlGetLocationUniform(program_id, "respawnRadius");
        const entity_speed_loc = rl.gl.rlGetLocationUniform(program_id, "entitySpeed");

        std.debug.print("compute: shader loaded\n", .{});

        return .{
            .program_id = program_id,
            .entity_count_loc = entity_count_loc,
            .frame_number_loc = frame_number_loc,
            .screen_size_loc = screen_size_loc,
            .center_loc = center_loc,
            .respawn_radius_loc = respawn_radius_loc,
            .entity_speed_loc = entity_speed_loc,
            .glMemoryBarrier = glMemoryBarrier,
        };
    }

    pub fn deinit(self: *ComputeShader) void {
        rl.gl.rlUnloadShaderProgram(self.program_id);
    }

    pub fn dispatch(self: *ComputeShader, ssbo_id: u32, entity_count: u32, frame_number: u32) void {
        if (entity_count == 0) return;

        // constants from sandbox.zig
        const screen_w: f32 = @floatFromInt(sandbox.SCREEN_WIDTH);
        const screen_h: f32 = @floatFromInt(sandbox.SCREEN_HEIGHT);
        const center_x: f32 = screen_w / 2.0;
        const center_y: f32 = screen_h / 2.0;
        const respawn_radius: f32 = 10.0; // RESPAWN_THRESHOLD
        const entity_speed: f32 = 2.0; // ENTITY_SPEED

        // bind compute shader
        rl.gl.rlEnableShader(self.program_id);

        // set uniforms
        rl.gl.rlSetUniform(self.entity_count_loc, &entity_count, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_uint), 1);
        rl.gl.rlSetUniform(self.frame_number_loc, &frame_number, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_uint), 1);

        const screen_size = [2]f32{ screen_w, screen_h };
        rl.gl.rlSetUniform(self.screen_size_loc, &screen_size, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_vec2), 1);

        const center = [2]f32{ center_x, center_y };
        rl.gl.rlSetUniform(self.center_loc, &center, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_vec2), 1);

        rl.gl.rlSetUniform(self.respawn_radius_loc, &respawn_radius, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_float), 1);
        rl.gl.rlSetUniform(self.entity_speed_loc, &entity_speed, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_float), 1);

        // bind SSBO to binding point 0
        rl.gl.rlBindShaderBuffer(ssbo_id, 0);

        // dispatch compute workgroups: ceil(entity_count / 256)
        const groups = (entity_count + 255) / 256;
        rl.gl.rlComputeShaderDispatch(groups, 1, 1);

        // memory barrier - ensure compute writes are visible to vertex shader
        self.glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);

        // unbind
        rl.gl.rlBindShaderBuffer(0, 0);
    }
};
