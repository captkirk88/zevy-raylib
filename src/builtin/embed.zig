const std = @import("std");

const Util = @This();

/// Options for embedding assets into the binary.
pub const EmbedAssetsOptions = struct {
    /// Filesystem path that will be scanned for assets (relative to repository root).
    assets_dir: []const u8 = "src/embedded_assets",
    /// Import name that will be attached to the owning module.
    import_name: []const u8 = "embedded_assets",
    /// Generated Zig file path (relative inside zig cache) containing lookup helpers.
    generated_file: []const u8 = "embedded_assets/generated.zig",
};

/// Add a build dependency and return it.
pub fn addImport(b: *std.Build, dep_name: []const u8, args: anytype) !std.Build.Dependency {
    const dep = b.dependency(dep_name, args orelse .{});
    return dep;
}

/// List all build dependencies.
pub fn listBuildDependencies(b: *std.Build) void {
    std.debug.print("Stored dependencies:\n", .{});
    for (b.available_deps) |depid| {
        std.log.info("DEP: {s}", .{depid.@"0"});
        listDependencies(b.dependency(depid.@"0", .{}));
    }
}

/// List all dependencies of a given dependency.
pub fn listDependencies(dependency: *std.Build.Dependency) void {
    std.debug.print("Dependencies: {s}\n", .{dependency.builder.build_root.path orelse "unknown"});
    var iter = dependency.builder.modules.iterator();
    while (iter.next()) |entry| {
        std.log.info("- {s}", .{entry.key_ptr.*});
    }
}

/// List all dependencies of a given module.
pub fn listModuleDependencies(module: *std.Build.Module) void {
    std.debug.print("Module dependencies for {s}:\n", .{module.getGraph().names[0]});
    for (module.owner.available_deps) |dep| {
        std.log.info("  - {s}", .{dep.@"0"});
    }
}

/// Copy all files from a source folder to the build output directory.
pub fn copyFolder(b: *std.Build, src: []const u8) !void {
    const fs = std.fs;
    const allocator = b.allocator;

    var src_dir = try fs.cwd().openDir(b.path(src).cwd_relative, .{ .access_sub_paths = true, .iterate = true });
    defer src_dir.close();
    std.log.info("Copying assets from {s} to {s}", .{ b.path(src).cwd_relative, b.exe_dir });
    try copyDirRecursive(src_dir, b.exe_dir, allocator);
}

fn copyDirRecursive(dir: std.fs.Dir, dest_root: []const u8, allocator: std.mem.Allocator) !void {
    const fs = std.fs;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const src_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_root, entry.name });
        defer allocator.free(src_path);

        if (entry.kind == .file) {
            const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_root, entry.name });
            defer allocator.free(dest_path);

            try fs.cwd().makePath(std.fs.path.dirname(dest_path) orelse ".");
            var src_file = try dir.openFile(entry.name, .{ .mode = .read_only });
            defer src_file.close();
            const dest_file = try fs.cwd().createFile(dest_path, .{ .truncate = true });
            defer dest_file.close();
            var buffer: [4096]u8 = undefined;
            while (true) {
                const bytes_read = try src_file.read(&buffer);
                if (bytes_read == 0) break;
                _ = try dest_file.write(buffer[0..bytes_read]);
            }
        }
        // Ignore directories
    }
}

/// Add build steps and a module to embed assets from a specified directory into the binary.
pub fn addEmbeddedAssetsOption(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, assets_folder: []const u8) !void {
    var options = b.addOptions();

    var files = try std.ArrayList([]const u8).initCapacity(b.allocator, 16);
    defer files.deinit(b.allocator);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fs.cwd().realpath(assets_folder, buf[0..]);

    var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .file) {
            continue;
        }
        try files.append(b.allocator, b.dupe(file.name));
    }
    options.addOption([]const []const u8, "files", files.items);
    exe.step.dependOn(&options.step);

    const assets = b.addModule("assets", .{
        .root_source_file = options.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("embedded", assets);
}

/// Add a module that embeds assets from a specified directory into the binary.
pub fn addEmbeddedAssetsModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    owner: *std.Build.Module,
    options: EmbedAssetsOptions,
) anyerror!*std.Build.Module {
    const allocator = b.allocator;

    var asset_paths = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (asset_paths.items) |path| allocator.free(path);
        asset_paths.deinit(allocator);
    }

    const assets_root_opt = try collectEmbeddedAssets(allocator, options.assets_dir, &asset_paths);
    defer if (assets_root_opt) |root| allocator.free(root);

    const generated_file = try writeEmbeddedModule(b, options, asset_paths.items, assets_root_opt);

    const embedded_module = b.createModule(.{
        .root_source_file = generated_file,
        .optimize = optimize,
        .target = target,
    });

    owner.addImport(options.import_name, embedded_module);

    return embedded_module;
}

fn collectEmbeddedAssets(
    allocator: std.mem.Allocator,
    assets_dir_path: []const u8,
    asset_paths: *std.ArrayListUnmanaged([]const u8),
) anyerror!?[]const u8 {
    var dir = std.fs.cwd().openDir(assets_dir_path, .{ .iterate = true, .access_sub_paths = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer dir.close();

    const abs_dir = try std.fs.cwd().realpathAlloc(allocator, assets_dir_path);
    errdefer allocator.free(abs_dir);

    var path_buffer = std.ArrayListUnmanaged(u8){};
    defer path_buffer.deinit(allocator);

    try walkEmbeddedAssets(allocator, &dir, &path_buffer, asset_paths);

    if (asset_paths.items.len > 1) {
        std.sort.heap([]const u8, asset_paths.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
    }

    return abs_dir;
}

fn walkEmbeddedAssets(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    path_buffer: *std.ArrayListUnmanaged(u8),
    asset_paths: *std.ArrayListUnmanaged([]const u8),
) anyerror!void {
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const original_len = path_buffer.items.len;
                if (original_len != 0) try path_buffer.append(allocator, '/');
                try path_buffer.appendSlice(allocator, entry.name);
                var child = try dir.openDir(entry.name, .{ .iterate = true, .access_sub_paths = true });
                defer child.close();
                try walkEmbeddedAssets(allocator, &child, path_buffer, asset_paths);
                path_buffer.shrinkRetainingCapacity(original_len);
            },
            .file => {
                const original_len = path_buffer.items.len;
                if (original_len != 0) try path_buffer.append(allocator, '/');
                try path_buffer.appendSlice(allocator, entry.name);
                const relative_path = try allocator.dupe(u8, path_buffer.items);
                errdefer allocator.free(relative_path);
                try asset_paths.append(allocator, relative_path);
                path_buffer.shrinkRetainingCapacity(original_len);
            },
            else => {},
        }
    }
}

fn writeEmbeddedModule(
    b: *std.Build,
    options: EmbedAssetsOptions,
    asset_paths: []const []const u8,
    assets_root_opt: ?[]const u8,
) anyerror!std.Build.LazyPath {
    const allocator = b.allocator;

    if (asset_paths.len != 0 and assets_root_opt == null) {
        @panic("embedded assets root missing but files discovered");
    }

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    var embed_paths = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (embed_paths.items) |path| allocator.free(path);
        embed_paths.deinit(allocator);
    }

    const write_files = b.addWriteFiles();

    if (assets_root_opt) |abs_root| {
        for (asset_paths) |relative_path| {
            const embed_rel_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "assets/", relative_path });

            const copy_sub_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "embedded_assets/", embed_rel_path });
            defer allocator.free(copy_sub_path);

            const source_sub_path = b.pathJoin(&.{ abs_root, relative_path });
            _ = write_files.addCopyFile(.{ .cwd_relative = source_sub_path }, copy_sub_path);

            embed_paths.append(allocator, embed_rel_path) catch |err| {
                allocator.free(embed_rel_path);
                return err;
            };
        }
    }

    try buffer.appendSlice(
        allocator,
        "const std = @import(\"std\");\n" ++
            "pub const scheme = \"embedded://\";\n" ++
            "pub const Asset = struct { path: []const u8, data: []const u8 };\n" ++
            "pub fn get(path: []const u8) ?[]const u8 {\n" ++
            "    return assets.get(path);\n" ++
            "}\n" ++
            "pub fn getUri(uri: []const u8) ?[]const u8 {\n" ++
            "    if (!std.mem.startsWith(u8, uri, scheme)) return null;\n" ++
            "    return get(uri[scheme.len..]);\n" ++
            "}\n" ++
            "pub fn list() []const Asset {\n" ++
            "    return assets_list[0..];\n" ++
            "}\n" ++
            "pub fn contains(path: []const u8) bool {\n" ++
            "    return assets.has(path);\n" ++
            "}\n" ++
            "pub fn uriAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {\n" ++
            "    return std.fmt.allocPrint(allocator, \"{s}{s}\", .{ scheme, path });\n" ++
            "}\n" ++
            "const assets = std.StaticStringMap([]const u8).initComptime(.{\n",
    );

    if (assets_root_opt) |_| {
        for (asset_paths, embed_paths.items) |relative_path, embed_rel_path| {
            try buffer.appendSlice(allocator, "    .{ ");
            try appendStringLiteral(&buffer, allocator, relative_path);
            try buffer.appendSlice(allocator, ", @embedFile(");
            try appendStringLiteral(&buffer, allocator, embed_rel_path);
            try buffer.appendSlice(allocator, ") },\n");
        }
    }

    try buffer.appendSlice(allocator, "});\n\nconst assets_list = [_]Asset{\n");
    if (assets_root_opt) |_| {
        for (asset_paths, embed_paths.items) |relative_path, embed_rel_path| {
            try buffer.appendSlice(allocator, "    .{ .path = ");
            try appendStringLiteral(&buffer, allocator, relative_path);
            try buffer.appendSlice(allocator, ", .data = @embedFile(");
            try appendStringLiteral(&buffer, allocator, embed_rel_path);
            try buffer.appendSlice(allocator, ") },\n");
        }
    }
    try buffer.appendSlice(allocator, "};\n");

    const content = try buffer.toOwnedSlice(allocator);
    return write_files.add(options.generated_file, content);
}

fn appendStringLiteral(buffer: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: []const u8) error{OutOfMemory}!void {
    try buffer.append(allocator, '"');
    for (value) |byte| {
        switch (byte) {
            '\\' => try buffer.appendSlice(allocator, "\\\\"),
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            '"' => try buffer.appendSlice(allocator, "\\\""),
            else => if (byte < 0x20 or byte >= 0x7f) {
                const hex_str = try std.fmt.allocPrint(allocator, "\\x{X:0>2}", .{byte});
                defer allocator.free(hex_str);
                try buffer.appendSlice(allocator, hex_str);
            } else {
                try buffer.append(allocator, byte);
            },
        }
    }
    try buffer.append(allocator, '"');
}

/// Generate a Zig file that runs a specific example
pub fn generateExampleRunner(
    b: *std.Build,
    example_name: []const u8,
) error{OutOfMemory}!std.Build.LazyPath {
    const allocator = b.allocator;

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, "const std = @import(\"std\");\n");
    try buffer.appendSlice(allocator, "const example = @import(\"");
    try buffer.appendSlice(allocator, example_name);
    try buffer.appendSlice(allocator, "\");\n\n");
    try buffer.appendSlice(allocator, "pub fn main() !void {\n");
    try buffer.appendSlice(allocator, "    var instance = example{};\n");
    try buffer.appendSlice(allocator, "    try instance.run();\n");
    try buffer.appendSlice(allocator, "}\n");

    const content = try buffer.toOwnedSlice(allocator);
    const write_files = b.addWriteFiles();

    const generated_filename = try std.fmt.allocPrint(allocator, "generated_example_runner_{s}.zig", .{example_name});
    return write_files.add(generated_filename, content);
}

pub fn generateExamplesListFile(b: *std.Build, example_src_dir: []const u8) std.Build.LazyPath {
    var examples = std.ArrayList([]const u8).initCapacity(b.allocator, 8) catch @panic("OOM");
    defer examples.deinit(b.allocator);

    // Scan the examples directory
    var examples_path = std.fs.cwd().openDir(example_src_dir, .{ .iterate = true }) catch |err| {
        std.log.err("Failed to open examples directory '{s}': {}", .{ example_src_dir, err });
        @panic("Failed to open examples directory");
    };
    defer examples_path.close();

    var iterator = examples_path.iterate();
    while (iterator.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const name_without_ext = entry.name[0 .. entry.name.len - 4];
            examples.append(b.allocator, b.allocator.dupe(u8, name_without_ext) catch @panic("OOM")) catch @panic("OOM");
        }
    }

    // Generate the Zig file content
    var content = std.ArrayList(u8).initCapacity(b.allocator, 512) catch @panic("OOM");
    defer content.deinit(b.allocator);

    content.appendSlice(b.allocator, "const std = @import(\"std\");\n\n") catch @panic("OOM");
    content.appendSlice(b.allocator, "pub fn main() !void {\n") catch @panic("OOM");
    content.appendSlice(b.allocator, "    std.debug.print(\"Available examples:\\n\", .{});\n") catch @panic("OOM");

    for (examples.items) |example| {
        content.appendSlice(b.allocator, std.fmt.allocPrint(b.allocator, "    std.debug.print(\"  - {s}\\n\", .{{\"{s}\"}});\n", .{ "{s}", example }) catch @panic("OOM")) catch @panic("OOM");
    }

    content.appendSlice(b.allocator, "    std.debug.print(\"\\nUsage: zig build example <example_name>\\n\", .{});\n") catch @panic("OOM");
    content.appendSlice(b.allocator, "}\n") catch @panic("OOM");

    const generated_runner_content = content.toOwnedSlice(b.allocator) catch @panic("OOM");

    var write_files = b.addWriteFiles();
    return write_files.add("generated_examples_list.zig", generated_runner_content);
}
