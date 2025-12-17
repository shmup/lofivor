// compute shader module for GPU entity updates
// wraps raw GL calls that raylib doesn't expose directly

const std = @import("std");
const rl = @import("raylib");

const comp_source = @embedFile("shaders/entity_update.comp");

// GL constants not exposed by raylib-zig
const GL_SHADER_STORAGE_BARRIER_BIT: u32 = 0x00002000;

// function pointer type for glMemoryBarrier
const GlMemoryBarrierFn = *const fn (barriers: u32) callconv(.c) void;

pub const ComputeShader = struct {
    program_id: u32,
    entity_count_loc: i32,
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
        if (entity_count_loc < 0) {
            std.debug.print("compute: warning - entityCount uniform not found\n", .{});
        }

        std.debug.print("compute: shader loaded successfully (program_id={})\n", .{program_id});

        return .{
            .program_id = program_id,
            .entity_count_loc = entity_count_loc,
            .glMemoryBarrier = glMemoryBarrier,
        };
    }

    pub fn deinit(self: *ComputeShader) void {
        rl.gl.rlUnloadShaderProgram(self.program_id);
    }

    pub fn dispatch(self: *ComputeShader, ssbo_id: u32, entity_count: u32) void {
        if (entity_count == 0) return;

        // bind compute shader
        rl.gl.rlEnableShader(self.program_id);

        // set entityCount uniform
        rl.gl.rlSetUniform(self.entity_count_loc, &entity_count, @intFromEnum(rl.gl.rlShaderUniformDataType.rl_shader_uniform_uint), 1);

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
