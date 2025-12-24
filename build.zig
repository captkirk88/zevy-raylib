const std = @import("std");
const ecs_build = @import("zevy_ecs");

/// Builtin asset embedding utilities.
pub const embed = @import("src/build/embed.zig");

const ModuleImport = struct {
    name: []const u8,
    module: *std.Build.Module,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const known_folders_dep = b.lazyDependency("known_folders", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.KnownFolders_DepNotFound;

    const xml_dep = b.lazyDependency("xml", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.XML_DepNotFound;

    const zevy_ecs_dep = b.lazyDependency("zevy_ecs", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.ZevyECS_DepNotFound;

    const zevy_mem_dep = b.lazyDependency("zevy_mem", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.ZevyMem_DepNotFound;

    const zevy_reflect_dep = b.lazyDependency("zevy_reflect", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.ZevyReflect_DepNotFound;

    const raylib_dep = b.lazyDependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.RaylibZig_DepNotFound;

    _ = b.addModule("embed", .{
        .root_source_file = b.path("build/embed.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("zevy_raylib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "known_folders", .module = known_folders_dep.module("known-folders") },
            .{ .name = "zevy_ecs", .module = zevy_ecs_dep.module("zevy_ecs") },
            .{ .name = "raylib", .module = raylib_dep.module("raylib") },
            .{ .name = "raygui", .module = raylib_dep.module("raygui") },
            .{ .name = "plugins", .module = zevy_ecs_dep.module("plugins") },
            .{ .name = "xml", .module = xml_dep.module("xml") },
            .{ .name = "zevy_reflect", .module = zevy_reflect_dep.module("zevy_reflect") },
            .{ .name = "zevy_mem", .module = zevy_mem_dep.module("zevy_mem") },
        },
    });

    const embed_opts: embed.EmbedAssetsOptions = .{
        .assets_dir = "embedded_assets/",
    };

    const embed_assets_mod = embed.addEmbeddedAssetsModule(b, target, optimize, mod, embed_opts) catch |err| {
        std.debug.panic("Failed to add embedded assets module: {s}\n", .{@errorName(err)});
    };

    const example_embed_opts: embed.EmbedAssetsOptions = .{
        .assets_dir = "example_embed_assets/",
        .import_name = "example_embedded",
    };

    const example_embed_assets_mod = embed.addEmbeddedAssetsModule(b, target, optimize, mod, example_embed_opts) catch |err| {
        std.debug.panic("Failed to add example embedded assets module: {s}\n", .{@errorName(err)});
    };

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    if (ecs_build.isSelf(b)) {
        ecs_build.setupExamples(b, &[_]std.Build.Module.Import{
            .{ .name = "raylib", .module = raylib_dep.module("raylib") },
            .{ .name = "raygui", .module = raylib_dep.module("raygui") },
            .{ .name = "zevy_raylib", .module = mod },
            .{ .name = "zevy_ecs", .module = zevy_ecs_dep.module("zevy_ecs") },
            .{ .name = "plugins", .module = zevy_ecs_dep.module("plugins") },
            .{ .name = embed_opts.import_name, .module = embed_assets_mod },
            .{ .name = example_embed_opts.import_name, .module = example_embed_assets_mod },
        }, target, optimize);
    }
}
