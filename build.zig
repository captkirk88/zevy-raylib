const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const zevy_ecs_mod = b.dependency("zevy_ecs", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("zevy_raylib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_ecs", .module = zevy_ecs_mod.module("zevy_ecs") },
            .{ .name = "raylib", .module = raylib.module("raylib") },
            .{ .name = "raygui", .module = raylib.module("raygui") },
            .{ .name = "plugins", .module = zevy_ecs_mod.module("plugins") },
        },
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
