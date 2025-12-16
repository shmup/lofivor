// sandbox stress test entry point
// measures entity count ceiling on weak hardware

const std = @import("std");
const rl = @import("raylib");
const sandbox = @import("sandbox.zig");
const ui = @import("ui.zig");
const SsboRenderer = @import("ssbo_renderer.zig").SsboRenderer;

const SCREEN_WIDTH = sandbox.SCREEN_WIDTH;
const SCREEN_HEIGHT = sandbox.SCREEN_HEIGHT;

// colors
const BG_COLOR = rl.Color{ .r = 10, .g = 10, .b = 18, .a = 255 };
const CYAN = rl.Color{ .r = 0, .g = 255, .b = 255, .a = 255 };

// entity rendering
const ENTITY_RADIUS: f32 = 4.0;
const TEXTURE_SIZE: i32 = 16; // must be >= 2 * radius
const MESH_SIZE: f32 = @floatFromInt(TEXTURE_SIZE); // match texture size

// logging thresholds
const TARGET_FRAME_MS: f32 = 8.33; // 120fps
const THRESHOLD_MARGIN: f32 = 2.0; // hysteresis margin to avoid bounce
const JUMP_THRESHOLD_MS: f32 = 5.0; // log if frame time jumps by this much
const HEARTBEAT_INTERVAL: f32 = 10.0; // seconds between periodic logs

// auto-benchmark settings
const BENCH_RAMP_INTERVAL: f32 = 2.0; // seconds between entity ramps
const BENCH_RAMP_AMOUNT: usize = 50_000; // entities added per ramp
const BENCH_EXIT_THRESHOLD_MS: f32 = 25.0; // exit when frame time exceeds this
const BENCH_EXIT_SUSTAIN: f32 = 1.0; // must stay above threshold for this long

const BenchmarkLogger = struct {
    file: ?std.fs.File,
    last_logged_frame_ms: f32,
    was_above_target: bool,
    last_heartbeat: f32,
    start_time: i64,

    fn init() BenchmarkLogger {
        // create log in project root (where zig build runs from)
        const file = std.fs.cwd().createFile("benchmark.log", .{}) catch |err| blk: {
            std.debug.print("failed to create benchmark.log: {}\n", .{err});
            break :blk null;
        };
        if (file) |f| {
            const header = "# lofivor sandbox benchmark\n# time entities frame_ms update_ms render_ms note\n";
            f.writeAll(header) catch {};
            std.debug.print("logging to benchmark.log\n", .{});
        }
        return .{
            .file = file,
            .last_logged_frame_ms = 0,
            .was_above_target = false,
            .last_heartbeat = 0,
            .start_time = std.time.timestamp(),
        };
    }

    fn deinit(self: *BenchmarkLogger) void {
        if (self.file) |f| f.close();
    }

    fn log(self: *BenchmarkLogger, elapsed: f32, entity_count: usize, frame_ms: f32, update_ms: f32, render_ms: f32) void {
        const f = self.file orelse return;

        // hysteresis: need to cross threshold + margin to flip state
        var crossed_threshold = false;
        var now_above = self.was_above_target;
        if (self.was_above_target) {
            // need to drop below target to flip back
            if (frame_ms < TARGET_FRAME_MS) {
                now_above = false;
                crossed_threshold = true;
            }
        } else {
            // need to exceed target + margin to flip
            if (frame_ms > TARGET_FRAME_MS + THRESHOLD_MARGIN) {
                now_above = true;
                crossed_threshold = true;
            }
        }

        const big_jump = (frame_ms - self.last_logged_frame_ms) >= JUMP_THRESHOLD_MS;
        const heartbeat_due = (elapsed - self.last_heartbeat) >= HEARTBEAT_INTERVAL;

        if (!crossed_threshold and !big_jump and !heartbeat_due) return;

        const fps = if (frame_ms > 0) 1000.0 / frame_ms else 0;

        // determine note - show ! when below target fps
        var note_buf: [16]u8 = undefined;
        const note = if (now_above)
            std.fmt.bufPrint(&note_buf, "[!{d:.0}fps]", .{fps}) catch ""
        else
            std.fmt.bufPrint(&note_buf, "[{d:.0}fps]", .{fps}) catch "";

        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "[{d:.1}s] entities={d} frame={d:.1}ms update={d:.1}ms render={d:.1}ms {s}\n", .{
            elapsed,
            entity_count,
            frame_ms,
            update_ms,
            render_ms,
            note,
        }) catch return;

        f.writeAll(line) catch {};

        self.last_logged_frame_ms = frame_ms;
        self.was_above_target = now_above;
        if (heartbeat_due) self.last_heartbeat = elapsed;
    }
};

fn createCircleTexture() ?rl.Texture2D {
    // create a render texture to draw circle into
    const target = rl.loadRenderTexture(TEXTURE_SIZE, TEXTURE_SIZE) catch return null;

    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); // transparent
    rl.drawCircle(
        @divTrunc(TEXTURE_SIZE, 2),
        @divTrunc(TEXTURE_SIZE, 2),
        ENTITY_RADIUS,
        rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 }, // white, tinted per-entity
    );
    rl.endTextureMode();

    return target.texture;
}

fn createOrthoCamera() rl.Camera3D {
    // orthographic camera looking down -Y axis at XZ plane
    // positioned to match 2D screen coordinates
    const hw = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2.0;
    const hh = @as(f32, @floatFromInt(SCREEN_HEIGHT)) / 2.0;
    return .{
        .position = .{ .x = hw, .y = 1000, .z = hh },
        .target = .{ .x = hw, .y = 0, .z = hh },
        .up = .{ .x = 0, .y = 0, .z = -1 }, // -Z is up to match screen Y
        .fovy = @floatFromInt(SCREEN_HEIGHT), // ortho uses fovy as height
        .projection = .orthographic,
    };
}

fn createInstanceMaterial(texture: rl.Texture2D) ?rl.Material {
    var material = rl.loadMaterialDefault() catch return null;
    rl.setMaterialTexture(&material, rl.MATERIAL_MAP_DIFFUSE, texture);
    return material;
}

pub fn main() !void {
    // parse args
    var bench_mode = false;
    var use_instancing = false;
    var use_ssbo = true;
    var use_vsync = false;
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    _ = args.skip(); // skip program name
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--bench")) {
            bench_mode = true;
        } else if (std.mem.eql(u8, arg, "--gpu")) {
            use_instancing = true;
            use_ssbo = false; // legacy GPU instancing path
        } else if (std.mem.eql(u8, arg, "--legacy")) {
            use_ssbo = false; // legacy rlgl batched path
        } else if (std.mem.eql(u8, arg, "--vsync")) {
            use_vsync = true;
        }
    }

    if (use_vsync) {
        rl.setConfigFlags(.{ .vsync_hint = true });
    }
    rl.initWindow(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT), "lofivor sandbox");
    defer rl.closeWindow();

    // use larger batch buffer: 16384 elements vs default 8192
    // fewer flushes = less driver overhead per frame
    const numElements: i32 = 8192 * 4; // quads = 4 verts
    var custom_batch = rl.gl.rlLoadRenderBatch(1, numElements);
    rl.gl.rlSetRenderBatchActive(&custom_batch);
    defer {
        rl.gl.rlSetRenderBatchActive(null); // restore default
        rl.gl.rlUnloadRenderBatch(custom_batch);
    }

    // create circle texture for batched rendering
    const circle_texture = createCircleTexture() orelse {
        std.debug.print("failed to create circle texture\n", .{});
        return;
    };
    defer rl.unloadTexture(circle_texture);

    // GPU instancing setup (only if --gpu flag)
    var quad_mesh: ?rl.Mesh = null;
    var instance_material: ?rl.Material = null;
    var ortho_camera: rl.Camera3D = undefined;

    // heap-allocated transforms buffer (64MB is too big for stack)
    var transforms: ?[]rl.Matrix = null;

    if (use_instancing) {
        transforms = std.heap.page_allocator.alloc(rl.Matrix, sandbox.MAX_ENTITIES) catch {
            std.debug.print("failed to allocate transforms buffer\n", .{});
            return;
        };
        // create quad mesh (XZ plane, will view from above)
        quad_mesh = rl.genMeshPlane(MESH_SIZE, MESH_SIZE, 1, 1);
        rl.uploadMesh(&quad_mesh.?, false); // upload to GPU

        // material with circle texture
        instance_material = createInstanceMaterial(circle_texture) orelse {
            std.debug.print("failed to create instance material\n", .{});
            return;
        };

        // orthographic camera for 2D-like rendering
        ortho_camera = createOrthoCamera();

        std.debug.print("GPU instancing mode enabled\n", .{});
    }

    defer {
        if (quad_mesh) |*m| rl.unloadMesh(m.*);
        if (instance_material) |mat| mat.unload();
        if (transforms) |t| std.heap.page_allocator.free(t);
    }

    // SSBO rendering setup (only if --ssbo flag)
    var ssbo_renderer: ?SsboRenderer = null;

    if (use_ssbo) {
        ssbo_renderer = SsboRenderer.init(circle_texture) orelse {
            std.debug.print("failed to initialize SSBO renderer\n", .{});
            return;
        };
        std.debug.print("SSBO instancing mode enabled\n", .{});
    }

    defer {
        if (ssbo_renderer) |*r| r.deinit();
    }

    // load UI font (embedded)
    const font_data = @embedFile("verdanab.ttf");
    const ui_font = rl.loadFontFromMemory(".ttf", font_data, 32, null) catch {
        std.debug.print("failed to load embedded font\n", .{});
        return;
    };
    defer rl.unloadFont(ui_font);

    var entities = sandbox.Entities.init();
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    var rng = prng.random();

    var paused = false;
    var logger = BenchmarkLogger.init();
    defer logger.deinit();

    // timing
    var update_time_us: i64 = 0;
    var render_time_us: i64 = 0;
    var elapsed: f32 = 0;

    // auto-benchmark state
    var last_ramp_time: f32 = 0;
    var above_threshold_time: f32 = 0;
    var smoothed_frame_ms: f32 = 16.7;

    if (bench_mode) {
        std.debug.print("auto-benchmark mode: ramping to failure or 1M entities\n", .{});
    }

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        elapsed += dt;
        const frame_ms = dt * 1000.0;

        // smooth frame time for stable exit detection
        smoothed_frame_ms = smoothed_frame_ms * 0.9 + frame_ms * 0.1;

        // auto-benchmark logic
        if (bench_mode) {
            // check exit condition: sustained poor performance
            if (smoothed_frame_ms > BENCH_EXIT_THRESHOLD_MS) {
                above_threshold_time += dt;
                if (above_threshold_time >= BENCH_EXIT_SUSTAIN) {
                    std.debug.print("benchmark complete: {d} entities @ {d:.1}ms avg frame\n", .{ entities.count, smoothed_frame_ms });
                    break;
                }
            } else {
                above_threshold_time = 0;
            }

            // check exit: hit max entities
            if (entities.count >= sandbox.MAX_ENTITIES) {
                std.debug.print("benchmark complete: hit max {d} entities\n", .{sandbox.MAX_ENTITIES});
                break;
            }

            // ramp entities
            if (elapsed - last_ramp_time >= BENCH_RAMP_INTERVAL) {
                for (0..BENCH_RAMP_AMOUNT) |_| entities.add(&rng);
                last_ramp_time = elapsed;
            }
        } else {
            // manual controls
            handleInput(&entities, &rng, &paused);
        }

        // update
        if (!paused) {
            const update_start = std.time.microTimestamp();
            sandbox.update(&entities, &rng);
            update_time_us = std.time.microTimestamp() - update_start;
        }

        // render
        const render_start = std.time.microTimestamp();

        rl.beginDrawing();
        rl.clearBackground(BG_COLOR);

        if (use_ssbo) {
            // SSBO instanced rendering path (12 bytes per entity)
            ssbo_renderer.?.render(&entities);
        } else if (use_instancing) {
            // GPU instancing path (64 bytes per entity)
            const xforms = transforms.?;
            // fill transforms array with entity positions
            for (entities.items[0..entities.count], 0..) |entity, i| {
                // entity (x, y) maps to 3D (x, 0, y) on XZ plane
                xforms[i] = rl.Matrix.translate(entity.x, 0, entity.y);
            }

            // draw all entities with single instanced call
            ortho_camera.begin();
            rl.drawMeshInstanced(quad_mesh.?, instance_material.?, xforms[0..entities.count]);
            ortho_camera.end();
        } else {
            // rlgl quad batching path (original)
            const size = @as(f32, @floatFromInt(TEXTURE_SIZE));
            const half = size / 2.0;

            rl.gl.rlSetTexture(circle_texture.id);
            rl.gl.rlBegin(rl.gl.rl_quads);

            for (entities.items[0..entities.count]) |entity| {
                // extract RGB from entity color (0xRRGGBB)
                const r: u8 = @truncate(entity.color >> 16);
                const g: u8 = @truncate(entity.color >> 8);
                const b: u8 = @truncate(entity.color);
                rl.gl.rlColor4ub(r, g, b, 255);

                const x1 = entity.x - half;
                const y1 = entity.y - half;
                const x2 = entity.x + half;
                const y2 = entity.y + half;

                // quad vertices: bottom-left, bottom-right, top-right, top-left
                rl.gl.rlTexCoord2f(0, 0);
                rl.gl.rlVertex2f(x1, y2);
                rl.gl.rlTexCoord2f(1, 0);
                rl.gl.rlVertex2f(x2, y2);
                rl.gl.rlTexCoord2f(1, 1);
                rl.gl.rlVertex2f(x2, y1);
                rl.gl.rlTexCoord2f(0, 1);
                rl.gl.rlVertex2f(x1, y1);
            }

            rl.gl.rlEnd();
            rl.gl.rlSetTexture(0);
        }

        // metrics overlay (skip in bench mode for cleaner headless run)
        if (!bench_mode) {
            ui.drawMetrics(&entities, update_time_us, render_time_us, paused, ui_font);
        }

        rl.endDrawing();

        render_time_us = std.time.microTimestamp() - render_start;

        // smart logging
        const update_ms = @as(f32, @floatFromInt(update_time_us)) / 1000.0;
        const render_ms = @as(f32, @floatFromInt(render_time_us)) / 1000.0;
        logger.log(elapsed, entities.count, frame_ms, update_ms, render_ms);
    }
}

const REPEAT_DELAY: f32 = 0.4; // initial delay before repeat
const REPEAT_RATE: f32 = 0.05; // repeat interval

var add_timer: f32 = 0;
var sub_timer: f32 = 0;

fn handleInput(entities: *sandbox.Entities, rng: *std.Random, paused: *bool) void {
    const dt = rl.getFrameTime();
    const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    const add_count: usize = if (shift) 50_000 else 10_000;

    const add_held = rl.isKeyDown(.equal) or rl.isKeyDown(.kp_add);
    const sub_held = rl.isKeyDown(.minus) or rl.isKeyDown(.kp_subtract);

    // add entities: = or +
    if (rl.isKeyPressed(.equal) or rl.isKeyPressed(.kp_add)) {
        for (0..add_count) |_| entities.add(rng);
        add_timer = REPEAT_DELAY;
    } else if (add_held) {
        add_timer -= dt;
        if (add_timer <= 0) {
            for (0..add_count) |_| entities.add(rng);
            add_timer = REPEAT_RATE;
        }
    } else {
        add_timer = 0;
    }

    // remove entities: - or _
    if (rl.isKeyPressed(.minus) or rl.isKeyPressed(.kp_subtract)) {
        entities.remove(add_count);
        sub_timer = REPEAT_DELAY;
    } else if (sub_held) {
        sub_timer -= dt;
        if (sub_timer <= 0) {
            entities.remove(add_count);
            sub_timer = REPEAT_RATE;
        }
    } else {
        sub_timer = 0;
    }

    // reset: r
    if (rl.isKeyPressed(.r)) {
        entities.reset();
    }

    // pause: space
    if (rl.isKeyPressed(.space)) {
        paused.* = !paused.*;
    }
}
