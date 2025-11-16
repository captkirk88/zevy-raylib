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

    const known_folders = b.dependency("known_folders", .{
        .target = target,
        .optimize = optimize,
    });

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
            .{ .name = "known_folders", .module = known_folders.module("known-folders") },
            .{ .name = "zevy_ecs", .module = zevy_ecs_mod.module("zevy_ecs") },
            .{ .name = "raylib", .module = raylib.module("raylib") },
            .{ .name = "raygui", .module = raylib.module("raygui") },
            .{ .name = "plugins", .module = zevy_ecs_mod.module("plugins") },
        },
    });

    const embed = @import("src/builtin/embed.zig");
    const embed_opts: embed.EmbedAssetsOptions = .{
        .assets_dir = "embedded_assets/",
    };
    const embed_assets_mod = embed.addEmbeddedAssetsModule(b, target, optimize, mod, embed_opts) catch |err| {
        std.debug.panic("Failed to add embedded assets module: {s}\n", .{@errorName(err)});
    };

    _ = embed.addEmbeddedAssetsModule(b, target, optimize, mod, .{
        .assets_dir = "embedded_assets/",
        .import_name = "test_embedded_assets",
        .generated_file = "test_embedded_assets/generated.zig",
    }) catch |err| {
        std.debug.panic("Failed to add test embedded assets module: {s}\n", .{@errorName(err)});
    };

    // Example executable that showcases manual plugin integration
    const example_mod = b.createModule(.{
        .root_source_file = b.path("example_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_ecs", .module = zevy_ecs_mod.module("zevy_ecs") },
            .{ .name = "plugins", .module = zevy_ecs_mod.module("plugins") },
            .{ .name = "raylib", .module = raylib.module("raylib") },
            .{ .name = "raygui", .module = raylib.module("raygui") },
            .{ .name = "zevy_raylib", .module = mod },
            .{ .name = embed_opts.import_name, .module = embed_assets_mod },
        },
    });

    const example_exe = b.addExecutable(.{
        .name = "zevy_raylib_example",
        .root_module = example_mod,
    });

    example_exe.linkLibrary(raylib.artifact("raylib"));
    b.installArtifact(example_exe);

    const run_example = b.addRunArtifact(example_exe);
    run_example.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_example.addArgs(args);
    }

    const run_step = b.step("run", "Run the plugin integration example");
    run_step.dependOn(&run_example.step);

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
