const std = @import("std");
const builtin = @import("builtin");
const known_folders = @import("known_folders");

pub fn cacheDir(allocator: std.mem.Allocator) error{ ParseError, OutOfMemory }![]const u8 {
    const path = try known_folders.getPath(allocator, .cache);
    if (path) |p| return p;
    return try allocator.dupe(u8, ".");
}

pub fn homeDir(allocator: std.mem.Allocator) error{ ParseError, OutOfMemory }![]const u8 {
    const path = try known_folders.getPath(allocator, .home);
    if (path) |p| return p;
    return try allocator.dupe(u8, ".");
}

pub fn configDir(allocator: std.mem.Allocator) error{ ParseError, OutOfMemory }![]const u8 {
    const path = try known_folders.getPath(allocator, .local_configuration);
    if (path) |p| return p;
    return try allocator.dupe(u8, ".");
}

pub fn dataDir(allocator: std.mem.Allocator) error{ ParseError, OutOfMemory }![]const u8 {
    const path = try known_folders.getPath(allocator, .data);
    if (path) |p| return p;
    return try allocator.dupe(u8, ".");
}

/// Check if a path is absolute or relative to current working directory
pub fn isAbsolutePath(path: []const u8) bool {
    if (path.len == 0) return false;

    switch (builtin.os.tag) {
        .windows => {
            // Windows absolute paths:
            // - Start with drive letter: C:\, D:\, etc.
            // - Start with UNC path: \\server\share
            // - Start with device path: \\?\C:\
            if (path.len >= 2) {
                // Drive letter format: C:\ or C:/
                if (std.ascii.isAlphabetic(path[0]) and path[1] == ':') {
                    return true;
                }
                // UNC or device path: starts with \\
                if (path[0] == '\\' and path[1] == '\\') {
                    return true;
                }
            }
            return false;
        },
        else => {
            // Unix-like systems: absolute paths start with /
            return path[0] == '/';
        },
    }
}

/// Check if a path is relative to current working directory
pub fn isRelativePath(path: []const u8) bool {
    return !isAbsolutePath(path);
}

/// Extract the directory portion of a URI or path.
/// For URIs with schemes (e.g., "embedded://dir/file.xml"), returns "embedded://dir/"
/// For regular paths, returns the empty string (caller should use std.fs.path.dirname)
pub fn getDirectoryUri(path: []const u8) []const u8 {
    if (std.mem.indexOf(u8, path, "://")) |scheme_end| {
        var i: usize = path.len;
        while (i > scheme_end + 3) : (i -= 1) {
            if (path[i - 1] == '/') {
                return path[0..i];
            }
        }
    }
    return "";
}

/// Check if a path points to a directory
pub fn isDirectory(path: []const u8) !bool {
    if (path.len == 0) return false;

    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.AccessDenied => return false,
        error.IsDir => return true, // On Windows, statFile fails for directories with IsDir
        else => return err,
    };
    return stat.kind == .directory;
}

/// Check if a path points to a regular file
pub fn isFile(path: []const u8) !bool {
    if (path.len == 0) return false;

    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.AccessDenied => return false,
        error.IsDir => return false, // Not a file if it's a directory
        else => return err,
    };
    return stat.kind == .file;
}

/// Check if a path exists (file or directory)
pub fn exists(path: []const u8) bool {
    if (path.len == 0) return false;

    // Check for obviously invalid characters that could cause issues
    for (path) |c| {
        if (c == 0) return false; // Null byte
        // Avoid checking paths with certain problematic patterns on Windows
        if (c < 32 and c != '\t' and c != '\n' and c != '\r') return false; // Control characters
    }

    // Check for Windows-specific problematic patterns that cause unreachable code
    if (std.mem.startsWith(u8, path, "://")) return false; // Malformed URI without scheme
    if (std.mem.indexOf(u8, path, "://") != null and path.len < 4) return false; // Very short scheme

    const testf = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.AccessDenied => return true, // Exists but no access
        error.IsDir => return true, // Exists and is a directory
        else => return true, // Other errors imply existence
    };
    testf.close();
    return true;
}

/// Get the file/directory type if it exists
pub const PathType = enum {
    file,
    directory,
    symlink,
    block_device,
    character_device,
    named_pipe,
    unix_domain_socket,
    whiteout,
    door,
    event_port,
    unknown,
};

/// Get the type of path (file, directory, etc.) or null if it doesn't exist
pub fn getPathType(path: []const u8) ?PathType {
    if (path.len == 0) return null;

    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.IsDir => return .directory, // Handle Windows IsDir error
        else => return null,
    };
    return switch (stat.kind) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        .block_device => .block_device,
        .character_device => .character_device,
        .named_pipe => .named_pipe,
        .unix_domain_socket => .unix_domain_socket,
        .whiteout => .whiteout,
        .door => .door,
        .event_port => .event_port,
        .unknown => .unknown,
    };
}

/// Normalize path separators for the current platform
pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) error{OutOfMemory}![]u8 {
    const normalized = try allocator.dupe(u8, path);
    switch (builtin.os.tag) {
        .windows => {
            // Convert forward slashes to backslashes on Windows
            for (normalized) |*char| {
                if (char.* == '/') {
                    char.* = '\\';
                }
            }
        },
        else => {
            // Convert backslashes to forward slashes on Unix-like systems
            for (normalized) |*char| {
                if (char.* == '\\') {
                    char.* = '/';
                }
            }
        },
    }
    return normalized;
}

/// Join multiple path components with the appropriate separator for the platform
pub fn joinPath(allocator: std.mem.Allocator, components: []const []const u8) error{OutOfMemory}![]u8 {
    if (components.len == 0) return try allocator.dupe(u8, "");
    if (components.len == 1) return try allocator.dupe(u8, components[0]);

    const separator = switch (builtin.os.tag) {
        .windows => "\\",
        else => "/",
    };

    // Calculate total length needed
    var total_len: usize = 0;
    for (components, 0..) |component, i| {
        total_len += component.len;
        if (i > 0) total_len += separator.len;
    }

    // Build the joined path
    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (components, 0..) |component, i| {
        if (i > 0) {
            @memcpy(result[pos .. pos + separator.len], separator);
            pos += separator.len;
        }
        @memcpy(result[pos .. pos + component.len], component);
        pos += component.len;
    }

    return result;
}

/// Get the directory part of a path
pub fn dirname(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    if (path.len == 0) return null;

    const separator = switch (builtin.os.tag) {
        .windows => '\\',
        else => '/',
    };

    // Find the last separator
    var last_sep_pos: ?usize = null;
    for (path, 0..) |char, i| {
        if (char == separator or (builtin.os.tag == .windows and char == '/')) {
            last_sep_pos = i;
        }
    }

    if (last_sep_pos) |pos| {
        if (pos == 0) {
            // Root directory
            return try allocator.dupe(u8, path[0..1]);
        }
        return try allocator.dupe(u8, path[0..pos]);
    }

    // No separator found, return current directory
    return try allocator.dupe(u8, ".");
}

/// Get the filename part of a path (without directory)
pub fn basename(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return try allocator.dupe(u8, "");

    const separator = switch (builtin.os.tag) {
        .windows => '\\',
        else => '/',
    };

    // Find the last separator
    var last_sep_pos: ?usize = null;
    for (path, 0..) |char, i| {
        if (char == separator or (builtin.os.tag == .windows and char == '/')) {
            last_sep_pos = i;
        }
    }

    if (last_sep_pos) |pos| {
        return try allocator.dupe(u8, path[pos + 1 ..]);
    }

    // No separator found, return the whole path
    return try allocator.dupe(u8, path);
}

pub fn randomFileName(allocator: std.mem.Allocator, length: usize, extension: []const u8) error{OutOfMemory}![]u8 {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const charset_len = charset.len;

    const ext: usize = if (extension.len > 0 and extension[0] == '.') 0 else 1;
    var name = try allocator.alloc(u8, length + extension.len + ext);

    var prng = std.Random.DefaultPrng.init(0);
    var rng = prng.random();
    for (name[0..length]) |*char| {
        const idx = rng.int(u8) % charset_len;
        char.* = charset[idx];
    }

    if (ext == 1) {
        name[length] = '.';
        @memcpy(name[length + 1 .. length + 1 + extension.len], extension);
    } else {
        @memcpy(name[length .. length + extension.len], extension);
    }

    return name;
}

pub fn writeTempFile(allocator: std.mem.Allocator, prefix: []const u8, extension: []const u8, data: []const u8) anyerror![]const u8 {
    const tmp_dir_path = known_folders.getPath(allocator, .cache) catch return error.IOError;
    defer if (tmp_dir_path) |td| allocator.free(td);

    const temp_file_name = try randomFileName(allocator, 8, extension);
    defer allocator.free(temp_file_name);

    const temp_path = try joinPath(allocator, &[_][]const u8{ tmp_dir_path.?, prefix, temp_file_name });
    errdefer allocator.free(temp_path);

    var tmp_dir = try std.fs.openDirAbsolute(tmp_dir_path.?, .{});
    defer tmp_dir.close();
    var temp_file = try tmp_dir.createFile(temp_path, .{ .read = true });
    defer temp_file.close();

    _ = try temp_file.write(data);

    return temp_path;
}

/// Write a temporary file with a specific filename (no random generation)
pub fn writeTempFileNamed(allocator: std.mem.Allocator, filename: []const u8, data: []const u8) anyerror![]const u8 {
    const tmp_dir_path = known_folders.getPath(allocator, .cache) catch return error.IOError;
    defer if (tmp_dir_path) |td| allocator.free(td);

    var tmp_dir = try std.fs.openDirAbsolute(tmp_dir_path.?, .{});
    defer tmp_dir.close();
    var temp_file = try tmp_dir.createFile(filename, .{ .read = true });
    defer temp_file.close();

    _ = try temp_file.write(data);

    // Return the absolute path to the temp file
    const abs_path = try joinPath(allocator, &[_][]const u8{ tmp_dir_path.?, filename });
    return abs_path;
}

pub fn deleteFile(path: []const u8) bool {
    std.fs.deleteFileAbsolute(path) catch return false;
    return true;
}

test "randomFileName" {
    const allocator = std.testing.allocator;

    const name1 = try randomFileName(allocator, 10, "tmp");
    defer allocator.free(name1);
    try std.testing.expect(name1.len == 14); // 10 + 4 for ".tmp"

    const name2 = try randomFileName(allocator, 8, "dat");
    defer allocator.free(name2);
    try std.testing.expect(name2.len == 12); // 8 + 4 for ".dat"

    try std.testing.expect(!std.mem.eql(u8, name1, name2)); // Very low chance of collision
}

test "isAbsolutePath" {
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expect(isAbsolutePath("C:\\path\\to\\file"));
            try std.testing.expect(isAbsolutePath("D:/path/to/file"));
            try std.testing.expect(isAbsolutePath("\\\\server\\share"));
            try std.testing.expect(isAbsolutePath("\\\\?\\C:\\path"));
            try std.testing.expect(!isAbsolutePath("path\\to\\file"));
            try std.testing.expect(!isAbsolutePath("./relative"));
            try std.testing.expect(!isAbsolutePath("../parent"));
        },
        else => {
            try std.testing.expect(isAbsolutePath("/path/to/file"));
            try std.testing.expect(isAbsolutePath("/"));
            try std.testing.expect(!isAbsolutePath("path/to/file"));
            try std.testing.expect(!isAbsolutePath("./relative"));
            try std.testing.expect(!isAbsolutePath("../parent"));
        },
    }

    try std.testing.expect(!isAbsolutePath(""));
}

test "isRelativePath" {
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expect(!isRelativePath("C:\\path\\to\\file"));
            try std.testing.expect(!isRelativePath("D:/path/to/file"));
            try std.testing.expect(isRelativePath("path\\to\\file"));
            try std.testing.expect(isRelativePath("./relative"));
            try std.testing.expect(isRelativePath("../parent"));
        },
        else => {
            try std.testing.expect(!isRelativePath("/path/to/file"));
            try std.testing.expect(isRelativePath("path/to/file"));
            try std.testing.expect(isRelativePath("./relative"));
            try std.testing.expect(isRelativePath("../parent"));
        },
    }

    try std.testing.expect(isRelativePath(""));
}

test "joinPath" {
    const allocator = std.testing.allocator;

    {
        const joined = try joinPath(allocator, &[_][]const u8{ "path", "to", "file" });
        defer allocator.free(joined);

        switch (builtin.os.tag) {
            .windows => try std.testing.expectEqualStrings("path\\to\\file", joined),
            else => try std.testing.expectEqualStrings("path/to/file", joined),
        }
    }

    {
        const joined = try joinPath(allocator, &[_][]const u8{"single"});
        defer allocator.free(joined);
        try std.testing.expectEqualStrings("single", joined);
    }

    {
        const joined = try joinPath(allocator, &[_][]const u8{});
        defer allocator.free(joined);
        try std.testing.expectEqualStrings("", joined);
    }
}

test "basename and dirname" {
    const allocator = std.testing.allocator;

    switch (builtin.os.tag) {
        .windows => {
            {
                const base = try basename(allocator, "C:\\path\\to\\file.txt");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("file.txt", base);

                const dir = try dirname(allocator, "C:\\path\\to\\file.txt");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("C:\\path\\to", dir.?);
            }

            {
                const base = try basename(allocator, "file.txt");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("file.txt", base);

                const dir = try dirname(allocator, "file.txt");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings(".", dir.?);
            }
        },
        else => {
            {
                const base = try basename(allocator, "/path/to/file.txt");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("file.txt", base);

                const dir = try dirname(allocator, "/path/to/file.txt");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("/path/to", dir.?);
            }

            {
                const base = try basename(allocator, "file.txt");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("file.txt", base);

                const dir = try dirname(allocator, "file.txt");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings(".", dir.?);
            }
        },
    }
}

test "exists functionality" {
    // Test with known existing paths
    try std.testing.expect(exists("src"));
    try std.testing.expect(exists("build.zig"));

    // Test with non-existing paths
    try std.testing.expect(!exists("definitely_does_not_exist_file.xyz"));
    try std.testing.expect(!exists("non/existent/deep/path"));

    // Test edge cases
    try std.testing.expect(!exists(""));
}

test "isDirectory and isFile functionality" {
    // Test with known directory
    try std.testing.expect(try isDirectory("src"));
    try std.testing.expect(!(try isFile("src")));

    // Test with known file
    try std.testing.expect(try isFile("build.zig"));
    try std.testing.expect(!(try isDirectory("build.zig")));

    // Test with non-existing paths - should return false
    try std.testing.expect(!(try isDirectory("non_existent_dir")));
    try std.testing.expect(!(try isFile("non_existent_file.txt")));

    // Test edge cases
    try std.testing.expect(!(try isDirectory("")));
    try std.testing.expect(!(try isFile("")));
}

test "getPathType functionality" {
    // Test with known directory
    try std.testing.expectEqual(PathType.directory, getPathType("src").?);

    // Test with known file
    try std.testing.expectEqual(PathType.file, getPathType("build.zig").?);

    // Test with non-existing path
    try std.testing.expectEqual(@as(?PathType, null), getPathType("non_existent_path"));

    // Test edge cases
    try std.testing.expectEqual(@as(?PathType, null), getPathType(""));
}

test "normalizePath functionality" {
    const allocator = std.testing.allocator;

    switch (builtin.os.tag) {
        .windows => {
            // Test forward to backslash conversion
            {
                const normalized = try normalizePath(allocator, "path/to/file");
                defer allocator.free(normalized);
                try std.testing.expectEqualStrings("path\\to\\file", normalized);
            }

            // Test mixed separators
            {
                const normalized = try normalizePath(allocator, "path\\to/mixed/separators");
                defer allocator.free(normalized);
                try std.testing.expectEqualStrings("path\\to\\mixed\\separators", normalized);
            }

            // Test already normalized path
            {
                const normalized = try normalizePath(allocator, "path\\to\\file");
                defer allocator.free(normalized);
                try std.testing.expectEqualStrings("path\\to\\file", normalized);
            }
        },
        else => {
            // Test backslash to forward slash conversion
            {
                const normalized = try normalizePath(allocator, "path\\to\\file");
                defer allocator.free(normalized);
                try std.testing.expectEqualStrings("path/to/file", normalized);
            }

            // Test mixed separators
            {
                const normalized = try normalizePath(allocator, "path/to\\mixed\\separators");
                defer allocator.free(normalized);
                try std.testing.expectEqualStrings("path/to/mixed/separators", normalized);
            }

            // Test already normalized path
            {
                const normalized = try normalizePath(allocator, "path/to/file");
                defer allocator.free(normalized);
                try std.testing.expectEqualStrings("path/to/file", normalized);
            }
        },
    }

    // Test edge cases
    {
        const normalized = try normalizePath(allocator, "");
        defer allocator.free(normalized);
        try std.testing.expectEqualStrings("", normalized);
    }

    {
        const normalized = try normalizePath(allocator, "single");
        defer allocator.free(normalized);
        try std.testing.expectEqualStrings("single", normalized);
    }
}

test "basename edge cases" {
    const allocator = std.testing.allocator;

    // Test empty string
    {
        const base = try basename(allocator, "");
        defer allocator.free(base);
        try std.testing.expectEqualStrings("", base);
    }

    // Test root paths
    switch (builtin.os.tag) {
        .windows => {
            {
                const base = try basename(allocator, "C:\\");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("", base);
            }

            {
                const base = try basename(allocator, "\\\\server\\share\\");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("", base);
            }

            // Test mixed separators
            {
                const base = try basename(allocator, "C:/path\\to/file.txt");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("file.txt", base);
            }
        },
        else => {
            {
                const base = try basename(allocator, "/");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("", base);
            }

            {
                const base = try basename(allocator, "/path/");
                defer allocator.free(base);
                try std.testing.expectEqualStrings("", base);
            }
        },
    }

    // Test paths with no extension
    {
        const base = try basename(allocator, "path/to/filename");
        defer allocator.free(base);
        try std.testing.expectEqualStrings("filename", base);
    }

    // Test paths with multiple dots
    {
        const base = try basename(allocator, "path/to/file.tar.gz");
        defer allocator.free(base);
        try std.testing.expectEqualStrings("file.tar.gz", base);
    }
}

test "dirname edge cases" {
    const allocator = std.testing.allocator;

    // Test empty string
    try std.testing.expectEqual(@as(?[]u8, null), try dirname(allocator, ""));

    // Test root paths
    switch (builtin.os.tag) {
        .windows => {
            {
                const dir = try dirname(allocator, "C:\\");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("C:", dir.?);
            }

            {
                const dir = try dirname(allocator, "\\\\server\\share");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("\\\\server", dir.?);
            }

            // Test mixed separators
            {
                const dir = try dirname(allocator, "C:/path\\to/file.txt");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("C:/path\\to", dir.?);
            }
        },
        else => {
            {
                const dir = try dirname(allocator, "/");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("/", dir.?);
            }

            {
                const dir = try dirname(allocator, "/path");
                defer if (dir) |d| allocator.free(d);
                try std.testing.expectEqualStrings("/", dir.?);
            }
        },
    }

    // Test single component paths
    {
        const dir = try dirname(allocator, "filename");
        defer if (dir) |d| allocator.free(d);
        try std.testing.expectEqualStrings(".", dir.?);
    }
}

test "joinPath edge cases" {
    const allocator = std.testing.allocator;

    // Test with empty components
    {
        const joined = try joinPath(allocator, &[_][]const u8{ "path", "", "file" });
        defer allocator.free(joined);

        switch (builtin.os.tag) {
            .windows => try std.testing.expectEqualStrings("path\\\\file", joined),
            else => try std.testing.expectEqualStrings("path//file", joined),
        }
    }

    // Test with all empty components
    {
        const joined = try joinPath(allocator, &[_][]const u8{ "", "", "" });
        defer allocator.free(joined);

        switch (builtin.os.tag) {
            .windows => try std.testing.expectEqualStrings("\\\\", joined),
            else => try std.testing.expectEqualStrings("//", joined),
        }
    }

    // Test with absolute and relative components mixed
    switch (builtin.os.tag) {
        .windows => {
            const joined = try joinPath(allocator, &[_][]const u8{ "C:", "path", "file" });
            defer allocator.free(joined);
            try std.testing.expectEqualStrings("C:\\path\\file", joined);
        },
        else => {
            const joined = try joinPath(allocator, &[_][]const u8{ "/", "path", "file" });
            defer allocator.free(joined);
            try std.testing.expectEqualStrings("//path/file", joined);
        },
    }
}

test "isAbsolutePath edge cases" {
    // Test Windows edge cases
    switch (builtin.os.tag) {
        .windows => {
            // Test invalid drive letters
            try std.testing.expect(!isAbsolutePath("1:\\path"));
            try std.testing.expect(!isAbsolutePath("@:\\path"));

            // Test single character paths
            try std.testing.expect(!isAbsolutePath("C"));
            try std.testing.expect(!isAbsolutePath(":"));
            try std.testing.expect(!isAbsolutePath("\\"));

            // Test UNC edge cases
            try std.testing.expect(!isAbsolutePath("\\"));
            try std.testing.expect(!isAbsolutePath("\\single"));

            // Test valid cases with forward slashes
            try std.testing.expect(isAbsolutePath("C:/path"));
            try std.testing.expect(isAbsolutePath("z:/file.txt"));
        },
        else => {
            // Test Unix edge cases
            try std.testing.expect(isAbsolutePath("/"));
            try std.testing.expect(isAbsolutePath("//"));
            try std.testing.expect(isAbsolutePath("///"));

            // Test relative-looking paths
            try std.testing.expect(!isAbsolutePath("./absolute"));
            try std.testing.expect(!isAbsolutePath("../absolute"));
            try std.testing.expect(!isAbsolutePath("~absolute"));
        },
    }

    // Test very long paths
    const long_path = "very" ** 100;
    try std.testing.expect(!isAbsolutePath(long_path));
}

test "file system operations with special characters" {
    // Test paths with special characters (these shouldn't crash)
    try std.testing.expect(!exists("file with spaces.txt"));
    try std.testing.expect(!exists("file-with-dashes.txt"));
    try std.testing.expect(!exists("file_with_underscores.txt"));
    try std.testing.expect(!exists("file.with.dots.txt"));

    // Test paths with unicode characters (shouldn't crash)
    try std.testing.expect(!exists("файл.txt"));
    try std.testing.expect(!exists("文件.txt"));
    try std.testing.expect(!exists("tiedosto.txt"));

    // Test moderately long non-existent paths (avoid system limits)
    const long_filename = "a" ** 50; // Reduced from 300 to avoid Windows path length limits
    try std.testing.expect(!exists(long_filename));
}

test "path operations memory safety" {
    const allocator = std.testing.allocator;

    // Test multiple allocations and deallocations
    for (0..10) |i| {
        const path = try std.fmt.allocPrint(allocator, "test_path_{d}", .{i});
        defer allocator.free(path);

        const base = try basename(allocator, path);
        defer allocator.free(base);

        const dir = try dirname(allocator, path);
        defer if (dir) |d| allocator.free(d);

        const normalized = try normalizePath(allocator, path);
        defer allocator.free(normalized);

        // Verify the operations worked correctly
        try std.testing.expectEqualStrings(path, base);
        try std.testing.expectEqualStrings(".", dir.?);
    }
}
