const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
        .opengl_version = .gl_4_3,
    });

    // sandbox executable
    const sandbox_exe = b.addExecutable(.{
        .name = "sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sandbox_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    sandbox_exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
    sandbox_exe.linkLibrary(raylib_dep.artifact("raylib"));

    b.installArtifact(sandbox_exe);

    const sandbox_run_cmd = b.addRunArtifact(sandbox_exe);
    sandbox_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        sandbox_run_cmd.addArgs(args);
    }

    const sandbox_step = b.step("sandbox", "run the sandbox stress test");
    sandbox_step.dependOn(&sandbox_run_cmd.step);

    // make sandbox the default run target
    const run_step = b.step("run", "run the sandbox");
    run_step.dependOn(&sandbox_run_cmd.step);

    // test step (doesn't need raylib)
    const test_step = b.step("test", "run unit tests");

    const test_files = [_][]const u8{
        "src/sandbox.zig",
    };

    for (test_files) |file| {
        const unit_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_test = b.addRunArtifact(unit_test);
        test_step.dependOn(&run_test.step);
    }
}
