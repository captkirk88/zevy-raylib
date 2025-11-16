const std = @import("std");

const Error = error{ InvalidArg, CommandFailed };

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch |err| {
        std.debug.print("Failed to get args: {s}\n", .{@errorName(err)});
        return err;
    };
    defer std.heap.page_allocator.free(args);

    var init = false;
    var remote = false;
    var dry_run = false;
    var path: ?[]const u8 = null;

    var i: usize = 1; // skip program name
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--init")) {
            init = true;
        } else if (std.mem.eql(u8, a, "--remote")) {
            remote = true;
        } else if (std.mem.eql(u8, a, "--path")) {
            if (i + 1 >= args.len) {
                std.debug.print("--path requires an argument\n", .{});
                return Error.InvalidArg;
            }
            i += 1;
            path = args[i];
        } else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "-?")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, a, "--dry-run")) {
            dry_run = true;
        } else {
            std.debug.print("Unknown arg: {s}\n", .{a});
            printHelp();
            return Error.InvalidArg;
        }
    }

    // default is init + remote update
    if (!init and !remote) {
        init = true;
        remote = true;
    }

    if (init) {
        try runGit(.{ "submodule", "update", "--init", "--recursive" }, dry_run);
    }

    if (remote) {
        if (path) |p| {
            try runGit(.{ "submodule", "update", "--remote", "--merge", p }, dry_run);
        } else {
            try runGit(.{ "submodule", "update", "--remote", "--merge", "--recursive" }, dry_run);
        }
    }

    std.debug.print("Done\n", .{});
}

fn runGit(args: anytype, dry_run: bool) !void {
    const resolved_args = .{"git"} ++ args;
    const T = @TypeOf(resolved_args);
    const type_info = @typeInfo(T);

    // Compile-time validation: args must be a tuple/struct
    if (type_info != .@"struct") {
        @compileError("runGit expects a tuple of []const u8, got: " ++ @typeName(T));
    }

    // Validate each field is a string type ([]const u8, string literal, etc.)
    inline for (type_info.@"struct".fields) |field| {
        const field_info = @typeInfo(field.type);
        const is_valid = switch (field_info) {
            .pointer => |ptr| blk: {
                // Accept slices of u8: []const u8
                if (ptr.size == .slice and ptr.child == u8) break :blk true;
                // Accept pointers to arrays of u8: *const [N:0]u8 (string literals)
                if (ptr.size == .one) {
                    const child_info = @typeInfo(ptr.child);
                    if (child_info == .array) {
                        const arr = child_info.array;
                        if (arr.child == u8) break :blk true;
                    }
                }
                break :blk false;
            },
            else => false,
        };
        if (!is_valid) {
            @compileError("runGit expects tuple elements to be string slices, found: " ++ @typeName(field.type) ++ " in field '" ++ field.name ++ "'");
        }
    }

    // Convert tuple to array of string slices
    const fields = type_info.@"struct".fields;
    var args_array: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, idx| {
        args_array[idx] = @field(resolved_args, field.name);
    }
    const args_slice: []const []const u8 = &args_array;

    std.debug.print("Running: ", .{});
    var first: bool = true;
    for (args_slice) |arg| {
        if (!first) std.debug.print(" ", .{});
        first = false;
        std.debug.print("{s}", .{arg});
    }
    if (dry_run) {
        std.debug.print(" (dry run)\n", .{});
        return;
    }
    std.debug.print("\n", .{});

    const res = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = args_slice,
    });
    defer std.heap.page_allocator.free(res.stdout);
    defer std.heap.page_allocator.free(res.stderr);

    if (res.term.Exited != 0) {
        std.debug.print("git command failed with exit: {}\n", .{res.term.Exited});
        if (res.stderr.len > 0) {
            std.debug.print("stderr: {s}\n", .{res.stderr});
        }
        return Error.CommandFailed;
    }
}

fn printHelp() void {
    std.debug.print("Usage: zig run update_submodules.zig [--init] [--remote] [--path <submodule_path>] [--dry-run]\n", .{});
    std.debug.print("Defaults to --init --remote if no flags are provided\n", .{});
}
