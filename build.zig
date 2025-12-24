const std = @import("std");

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

    if (isSelf(b)) {
        setupExamples(b, &[_]std.Build.Module.Import{
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

/// Check if the build is running in this project
fn isSelf(b: *std.Build) bool {
    // Check for a file that only exists in the main zevy-ecs project
    if (std.fs.accessAbsolute(b.path("build.zig").getPath(b), .{})) {
        return true;
    } else |_| {
        return true;
    }
}

pub fn setupExamples(b: *std.Build, modules: []const std.Build.Module.Import, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // Examples
    const examples_step = b.step("examples", "Run all examples");

    var examples_dir = std.fs.openDirAbsolute(b.path("examples").getPath(b), .{ .iterate = true }) catch return;
    defer examples_dir.close();

    var examples_iter = examples_dir.iterate();
    while (examples_iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const example_name = std.fs.path.stem(entry.name);
            const example_path = std.fs.path.join(b.allocator, &.{ "examples", entry.name }) catch continue;
            defer b.allocator.free(example_path);

            const example_mod = b.addModule(example_name, .{
                .root_source_file = b.path(example_path),
                .target = target,
                .optimize = optimize,
            });

            // Add imports from the first module if any
            if (modules.len > 0) {
                for (modules) |module| {
                    example_mod.addImport(module.name, module.module);
                }
            }

            // Add each module
            for (modules) |item| {
                example_mod.addImport(item.name, item.module);
            }

            const example_exe = b.addExecutable(.{
                .name = example_name,
                .root_module = example_mod,
            });

            const run_example = b.addRunArtifact(example_exe);

            if (b.args) |args| {
                run_example.addArgs(args);
            }
            const example_step = b.step(example_name, b.fmt("Run the {s} example", .{example_name}));
            example_step.dependOn(&run_example.step);

            examples_step.dependOn(example_step);
        }
    }
}
