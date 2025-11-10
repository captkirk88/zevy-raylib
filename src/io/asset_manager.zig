const std = @import("std");
const rl = @import("raylib");
const AssetLoader = @import("loader.zig").AssetLoader;

/// Handle type for loaded assets
pub const AssetHandle = usize;

const embedded_scheme = "embedded://";

inline fn isEmbeddedPath(path: []const u8) bool {
    return std.mem.startsWith(u8, path, embedded_scheme);
}

// Validate that a path is suitable for asset loading
fn isValidAssetPath(path: []const u8) bool {
    if (path.len == 0) return false;

    // Reject obviously problematic paths
    if (std.mem.eql(u8, path, ".")) return false;
    if (std.mem.eql(u8, path, "..")) return false;
    if (std.mem.eql(u8, path, "\\")) return false;
    if (std.mem.eql(u8, path, "/")) return false;
    if (std.mem.eql(u8, path, "\\\\")) return false; // UNC root

    // Check for null bytes and control characters
    for (path) |c| {
        if (c == 0) return false; // Null byte
        if (c < 32 and c != '\t' and c != '\n' and c != '\r') return false;
    }

    // Reject paths that are just whitespace
    if (std.mem.trim(u8, path, " \t\n\r").len == 0) return false;

    // For embedded paths, they should have content after the scheme
    if (isEmbeddedPath(path)) {
        const content = path[embedded_scheme.len..];
        return content.len > 0 and !std.mem.eql(u8, content, ".") and !std.mem.eql(u8, content, "..");
    }

    return true;
}

// Helper function to resolve path to absolute path (resolve relative to CWD if needed)
fn resolveAbsolutePath(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    // Validate the input path first
    if (!isValidAssetPath(file_path)) {
        return error.InvalidPath;
    }

    if (isEmbeddedPath(file_path)) {
        return try allocator.dupe(u8, file_path);
    }

    if (std.fs.path.isAbsolute(file_path)) {
        return try allocator.dupe(u8, file_path);
    } else {
        // For relative paths, resolve against current working directory
        const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd);
        const resolved = try std.fs.path.join(allocator, &[_][]const u8{ cwd, file_path });

        // Double-check the resolved path isn't problematic
        const basename = std.fs.path.basename(resolved);
        if (std.mem.eql(u8, basename, ".") or std.mem.eql(u8, basename, "..")) {
            allocator.free(resolved);
            return error.InvalidPath;
        }

        return resolved;
    }
}

// FileResolver implementation functions - use the directory of the main asset file
fn fileResolverResolvePath(resolver: *const @import("loader.zig").FileResolver, allocator: std.mem.Allocator, relative_path: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fs.path.join(allocator, &[_][]const u8{ resolver.base_dir, relative_path });
}

fn fileResolverPathExists(resolver: *const @import("loader.zig").FileResolver, relative_path: []const u8) bool {
    const full_path = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ resolver.base_dir, relative_path }) catch return false;
    defer std.heap.page_allocator.free(full_path);

    const file = std.fs.openFileAbsolute(full_path, .{}) catch return false;
    file.close();
    return true;
}

pub fn AssetManager(comptime AssetType: type, comptime LoaderType: type) type {
    const AssetEntry = struct {
        id: usize,
        asset: AssetType,
    };

    const LoadRequest = struct {
        file: []u8,
        id: usize,
        settings: ?LoaderType.LoadSettings = null,
    };

    return struct {
        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        assets: std.StringHashMap(AssetEntry),
        queue: std.ArrayList(LoadRequest),
        loader: LoaderType,

        pub fn initEx(allocator: std.mem.Allocator, loader: LoaderType) !@This() {
            return @This(){
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
                .assets = std.StringHashMap(AssetEntry).init(allocator),
                .queue = try std.ArrayList(LoadRequest).initCapacity(allocator, 0),
                .loader = loader,
            };
        }

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return @This(){
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
                .assets = std.StringHashMap(AssetEntry).init(allocator),
                .queue = try std.ArrayList(LoadRequest).initCapacity(allocator, 0),
                .loader = LoaderType{},
            };
        }

        pub fn deinit(self: *@This()) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // First unload all assets and free their keys
            var it = self.assets.iterator();
            while (it.next()) |entry| {
                self.loader.unload(entry.value_ptr.asset);
                self.allocator.free(@constCast(entry.key_ptr.*)); // Free the owned key
            }
            self.assets.deinit();

            // Free any remaining queue items
            for (self.queue.items) |req| {
                self.allocator.free(req.file);
            }
            self.queue.deinit(self.allocator);
        }

        pub fn count(self: *@This()) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.assets.len;
        }

        pub fn amount(self: *@This()) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.queue.items.len;
        }

        pub fn loadAsset(self: *@This(), file: []const u8, settings: anytype) error{ OutOfMemory, InvalidPath }!AssetHandle {

            // Check if already loaded using direct string comparison
            if (self.assets.get(file)) |entry| {
                return entry.id;
            }

            const id = generateHandle(file);

            const req = LoadRequest{
                .file = try self.allocator.dupe(u8, file),
                .id = id,
                .settings = settings,
            };

            self.mutex.lock();
            defer self.mutex.unlock();
            self.queue.append(self.allocator, req) catch {
                self.allocator.free(req.file); // Free the owned file string on failure
                //self.mutex.unlock();
                return error.OutOfMemory;
            };

            return id;
        }

        pub fn process(self: *@This()) anyerror!void {
            // First, safely get a request from the queue
            const req = blk: {
                self.mutex.lock();
                defer self.mutex.unlock();

                if (self.queue.items.len == 0) {
                    return;
                }
                break :blk self.queue.pop();
            };

            if (req == null) {
                return;
            }

            if (self.assets.get(req.?.file)) |_| {
                // Already loaded while in queue - just free the request
                self.allocator.free(req.?.file);
                return;
            }

            // Convert to absolute path with validation
            const absolute_path = resolveAbsolutePath(self.allocator, req.?.file) catch |err| {
                self.allocator.free(req.?.file); // Free the owned file string
                return err;
            };
            defer self.allocator.free(absolute_path);

            if (!@import("util.zig").exists(absolute_path)) {
                self.allocator.free(req.?.file); // Free the owned file string
                return error.FileNotFound;
            }
            // Create FileResolver for complex loaders - use the directory containing this asset
            const embedded = isEmbeddedPath(absolute_path);
            var resolver_storage: @import("loader.zig").FileResolver = undefined;
            const resolver_ptr: ?*const @import("loader.zig").FileResolver = if (!embedded) blk: {
                const asset_dir = std.fs.path.dirname(absolute_path) orelse ".";
                resolver_storage = .{
                    .base_dir = asset_dir,
                    .resolve_path = fileResolverResolvePath,
                    .path_exists = fileResolverPathExists,
                };
                break :blk &resolver_storage;
            } else null;

            // Convert settings to pointer if not null
            const settings_ptr = if (req.?.settings) |s| &s else null;
            const asset = try self.loader.load(absolute_path, resolver_ptr, settings_ptr);

            // Now safely store the result
            self.mutex.lock();
            defer self.mutex.unlock();

            const entry = AssetEntry{
                .id = req.?.id,
                .asset = asset,
            };

            // Transfer ownership of req.file to the HashMap
            try self.assets.put(req.?.file, entry);
        }

        pub fn unloadAsset(self: *@This(), handle: AssetHandle) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var it = self.assets.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.id == handle) {
                    self.loader.unload(entry.value_ptr.asset);
                    const key_to_free = entry.key_ptr.*;
                    _ = self.assets.remove(key_to_free);
                    self.allocator.free(@constCast(key_to_free)); // Free the owned key
                    return;
                }
            }
        }

        pub fn getAsset(self: *@This(), handle: AssetHandle) ?*AssetType {
            self.mutex.lock();
            defer self.mutex.unlock();

            var it = self.assets.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.id == handle) {
                    return &entry.value_ptr.asset;
                }
            }
            return null;
        }

        pub fn isLoaded(self: *@This(), handle: AssetHandle) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            var it = self.assets.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.id == handle) {
                    return true;
                }
            }
            return false;
        }

        pub fn loadAssetNow(self: *@This(), file: []const u8, settings: ?LoaderType.LoadSettings) anyerror!AssetHandle {
            // Validate path early, before taking mutex
            if (!isValidAssetPath(file)) {
                return error.InvalidPath;
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            // Check if already loaded using direct string comparison
            if (self.assets.get(file)) |entry| {
                return entry.id;
            }

            // Convert to absolute path
            const absolute_path = try resolveAbsolutePath(self.allocator, file);
            defer self.allocator.free(absolute_path);

            // Create FileResolver for complex loaders - use the directory containing this asset
            const embedded = isEmbeddedPath(absolute_path);
            var resolver_storage: @import("loader.zig").FileResolver = undefined;
            const resolver_ptr: ?*const @import("loader.zig").FileResolver = if (!embedded) blk: {
                const asset_dir = std.fs.path.dirname(absolute_path) orelse ".";
                resolver_storage = .{
                    .base_dir = asset_dir,
                    .resolve_path = fileResolverResolvePath,
                    .path_exists = fileResolverPathExists,
                };
                break :blk &resolver_storage;
            } else null;

            // Convert settings to pointer if not null
            const settings_ptr = if (settings) |s| &s else null;
            const asset = try self.loader.load(absolute_path, resolver_ptr, settings_ptr);
            const id = generateHandle(file);

            const entry = AssetEntry{
                .id = id,
                .asset = asset,
            };

            // Create owned key for HashMap
            const owned_key = try self.allocator.dupe(u8, file);
            try self.assets.put(owned_key, entry);

            return id;
        }
    };
}

fn generateHandle(file_path: []const u8) AssetHandle {
    return std.hash_map.hashString(file_path);
}

test "AssetManager multiple assets" {
    const TestAsset = usize;

    const TestLoader = struct {
        pub const LoadSettings = struct {};

        pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const @import("loader.zig").FileResolver, _settings: ?*const LoadSettings) anyerror!TestAsset {
            _ = _settings;
            _ = _file_resolver;
            const filename = std.fs.path.basename(absolute_path);
            return filename.len; // Mock: return filename length
        }

        pub fn extensions() []const []const u8 {
            return &[_][]const u8{".txt"};
        }

        pub fn unload(_: @This(), asset: TestAsset) void {
            _ = asset; // usize doesn't need cleanup
        }
    };

    var manager = try AssetManager(TestAsset, TestLoader).init(std.testing.allocator);
    defer manager.deinit();

    // Test with different settings types
    const settings1 = TestLoader.LoadSettings{};
    const handle1 = try manager.loadAsset("a.txt", settings1); // proper LoadSettings value
    const handle2 = try manager.loadAsset("bb.txt", null); // null settings

    try std.testing.expect(!manager.isLoaded(handle1));
    try std.testing.expect(!manager.isLoaded(handle2));
    try std.testing.expectError(error.FileNotFound, manager.process());
    try std.testing.expect(!manager.isLoaded(handle1));
    try std.testing.expect(!manager.isLoaded(handle2));
    try std.testing.expectError(error.FileNotFound, manager.process());
    try std.testing.expect(!manager.isLoaded(handle1));
    try std.testing.expect(!manager.isLoaded(handle2));

    try std.testing.expect(manager.getAsset(handle1) == null);
    try std.testing.expect(manager.getAsset(handle2) == null);
}

test "AssetManager loadAssetNow" {
    const TestAsset = []u8;

    const TestLoader = struct {
        pub const LoadSettings = struct {};

        pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const @import("loader.zig").FileResolver, _settings: ?*const LoadSettings) anyerror!TestAsset {
            _ = _settings;
            _ = _file_resolver;
            const filename = std.fs.path.basename(absolute_path);
            return std.testing.allocator.dupe(u8, filename);
        }

        pub fn extensions() []const []const u8 {
            return &[_][]const u8{".txt"};
        }

        pub fn unload(_: @This(), asset: TestAsset) void {
            std.testing.allocator.free(asset);
        }
    };

    var manager = try AssetManager(TestAsset, TestLoader).init(std.testing.allocator);
    defer manager.deinit();

    // Load immediately with proper settings type
    const handle = try manager.loadAssetNow("immediate.txt", null);

    // Should be loaded without processing
    try std.testing.expect(manager.isLoaded(handle));
    try std.testing.expect(manager.queue.items.len == 0); // No queue

    if (manager.getAsset(handle)) |asset| {
        try std.testing.expectEqualStrings("immediate.txt", asset.*);
        // Asset is owned by AssetManager, don't free it manually
    } else {
        try std.testing.expect(false);
    }

    // Load same again with null settings
    const handle2 = try manager.loadAssetNow("immediate.txt", null);
    try std.testing.expect(handle == handle2);
}

test "AssetManager path validation" {
    const TestAsset = usize;
    const TestLoader = struct {
        pub const LoadSettings = struct {};
        pub fn load(_: @This(), _: []const u8, _: ?*const @import("loader.zig").FileResolver, _: ?*const LoadSettings) anyerror!TestAsset {
            return 42;
        }
        pub fn extensions() []const []const u8 {
            return &[_][]const u8{".txt"};
        }
        pub fn unload(_: @This(), _: TestAsset) void {}
    };

    var manager = try AssetManager(TestAsset, TestLoader).init(std.testing.allocator);
    defer manager.deinit();

    // Test loadAssetNow with invalid paths
    try std.testing.expectError(error.InvalidPath, manager.loadAssetNow(".", null));
    try std.testing.expectError(error.InvalidPath, manager.loadAssetNow("..", null));
    try std.testing.expectError(error.InvalidPath, manager.loadAssetNow("\\", null));
}
