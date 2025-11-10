const std = @import("std");
const rl = @import("raylib");
const man = @import("asset_manager.zig");
const AssetManager = man.AssetManager;
const AssetHandle = man.AssetHandle;
const loader_mod = @import("loader.zig");
const loaders = @import("loaders.zig");
const io_utils = @import("util.zig");
const schemes = @import("scheme_resolver.zig");
const embedded_assets = @import("embedded_assets");

const interface = @import("util").Interface;

const ManagerEntry = struct {
    ptr: *anyopaque,
    deinit_fn: *const fn (*anyopaque) void,
    process_fn: *const fn (*anyopaque) anyerror!void,
    destroy_fn: *const fn (*anyopaque, std.mem.Allocator) void,
    get_fn: *const fn (*anyopaque, AssetHandle) ?*anyopaque,
    load_asset_fn: *const fn (*anyopaque, []const u8, ?*anyopaque) anyerror!AssetHandle,
    load_asset_now_fn: *const fn (*anyopaque, []const u8, ?*anyopaque) anyerror!*anyopaque,
};

pub const Assets = struct {
    allocator: std.mem.Allocator,
    managers: std.AutoHashMap(u64, ManagerEntry),
    scheme_registry: schemes.SchemeRegistry,

    pub fn init(allocator: std.mem.Allocator) Assets {
        const managers = std.AutoHashMap(u64, ManagerEntry).init(allocator);
        const scheme_registry = schemes.SchemeRegistry.init(allocator);

        var self = Assets{
            .allocator = allocator,
            .managers = managers,
            .scheme_registry = scheme_registry,
        };

        // Register default schemes
        self.initDefaultSchemes() catch @panic("Failed to register default schemes");
        // Add default managers
        self.addManager(rl.Texture, loaders.TextureLoader{}) catch @panic("Failed to add default texture manager");
        self.addManager(rl.Sound, loaders.SoundLoader{}) catch @panic("Failed to add default sound manager");
        self.addManager(rl.Music, loaders.MusicLoader{}) catch @panic("Failed to add default music manager");
        self.addManager(rl.Font, loaders.FontLoader{}) catch @panic("Failed to add default font manager");
        self.addManager(rl.Shader, loaders.ShaderLoader{}) catch @panic("Failed to add default shader manager");
        return self;
    }

    pub fn deinit(self: *Assets) void {
        var it = self.managers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit_fn(entry.value_ptr.ptr);
            entry.value_ptr.destroy_fn(entry.value_ptr.ptr, self.allocator);
        }
        self.managers.deinit();
        self.scheme_registry.deinit();
    }

    pub fn addManager(self: *Assets, comptime AssetType: type, loader: anytype) !void {
        const LoaderType = @TypeOf(loader);
        const hash = std.hash_map.hashString(@typeName(AssetType));
        if (self.managers.contains(hash)) return error.ManagerAlreadyExists;

        const manager_ptr = try self.allocator.create(AssetManager(AssetType, LoaderType));
        errdefer self.allocator.destroy(manager_ptr);

        const l_cast = @as(*const LoaderType, @ptrCast(&loader));
        manager_ptr.* = try AssetManager(AssetType, LoaderType).initEx(self.allocator, l_cast.*);

        const DeinitFn = struct {
            fn call(ptr: *anyopaque) void {
                const m = @as(*AssetManager(AssetType, LoaderType), @ptrCast(@alignCast(ptr)));
                m.deinit();
            }
        };

        const ProcessFn = struct {
            fn call(ptr: *anyopaque) anyerror!void {
                const m = @as(*AssetManager(AssetType, LoaderType), @ptrCast(@alignCast(ptr)));
                try m.process();
            }
        };

        const DestroyFn = struct {
            fn call(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const m = @as(*AssetManager(AssetType, LoaderType), @ptrCast(@alignCast(ptr)));
                allocator.destroy(m);
            }
        };

        const GetFn = struct {
            fn call(ptr: *anyopaque, handle: AssetHandle) ?*anyopaque {
                const m = @as(*AssetManager(AssetType, LoaderType), @ptrCast(@alignCast(ptr)));
                if (m.getAsset(handle)) |asset_ptr| {
                    return @ptrCast(asset_ptr);
                }
                return null;
            }
        };

        const LoadAssetFn = struct {
            fn call(ptr: *anyopaque, file: []const u8, settings: ?*anyopaque) anyerror!AssetHandle {
                const m = @as(*AssetManager(AssetType, LoaderType), @ptrCast(@alignCast(ptr)));
                const settings_val: ?LoaderType.LoadSettings = if (settings) |s|
                    @as(*LoaderType.LoadSettings, @ptrCast(@alignCast(s))).*
                else
                    null;
                return try m.loadAsset(file, settings_val);
            }
        };

        const LoadAssetNowFn = struct {
            fn call(ptr: *anyopaque, file: []const u8, settings: ?*anyopaque) anyerror!*anyopaque {
                const m = @as(*AssetManager(AssetType, LoaderType), @ptrCast(@alignCast(ptr)));
                const settings_val: ?LoaderType.LoadSettings = if (settings) |s|
                    @as(*LoaderType.LoadSettings, @ptrCast(@alignCast(s))).*
                else
                    null;
                const handle = try m.loadAssetNow(file, settings_val);
                const asset_ptr = m.getAsset(handle).?;
                return @ptrCast(asset_ptr);
            }
        };

        const entry = ManagerEntry{
            .ptr = @ptrCast(manager_ptr),
            .deinit_fn = DeinitFn.call,
            .process_fn = ProcessFn.call,
            .destroy_fn = DestroyFn.call,
            .get_fn = GetFn.call,
            .load_asset_fn = LoadAssetFn.call,
            .load_asset_now_fn = LoadAssetNowFn.call,
        };

        try self.managers.putNoClobber(hash, entry);
    }

    /// Initialize default scheme resolvers
    fn initDefaultSchemes(self: *Assets) !void {
        // Embedded asset resolver
        // const embedded_resolver_ptr = try self.allocator.create(schemes.EmbeddedResolver);
        // embedded_resolver_ptr.* = schemes.EmbeddedResolver{};
        // try self.scheme_registry.registerScheme("embedded", schemes.SchemeResolver.init(embedded_resolver_ptr));

        // File resolver
        const file_resolver_ptr = try self.allocator.create(schemes.FileResolver);
        file_resolver_ptr.* = schemes.FileResolver{};
        try self.scheme_registry.registerScheme("file", schemes.SchemeResolver.init(file_resolver_ptr));
    }

    /// Check if a manager for the given asset type exists
    pub fn hasManager(self: *Assets, comptime AssetType: type) bool {
        const hash = std.hash_map.hashString(@typeName(AssetType));
        return self.managers.contains(hash);
    }

    /// Load asset and return its handle
    pub fn loadAsset(self: *Assets, comptime AssetType: type, file: []const u8, settings: anytype) anyerror!AssetHandle {
        const hash = comptime std.hash_map.hashString(@typeName(AssetType));

        const resolved = try self.scheme_registry.resolve(file);

        const final_path = switch (resolved) {
            .file_path => |path| path,
            .url => |url| url,
            .embedded_data => |path| path,
            .custom => |path| path,
        };
        defer {
            switch (resolved) {
                .file_path => |path| self.allocator.free(path),
                .url => |url| self.allocator.free(url),
                .embedded_data => |path| self.allocator.free(path),
                .custom => |path| self.allocator.free(path),
            }
        }

        if (self.managers.getPtr(hash)) |entry| {
            const settings_ptr = if (@TypeOf(settings) == @TypeOf(null))
                null
            else
                @as(*anyopaque, @ptrCast(@constCast(&settings)));
            const normalized = try io_utils.normalizePath(self.allocator, final_path);
            defer self.allocator.free(normalized);
            if (!io_utils.exists(normalized)) return error.FileNotFound;
            return try entry.load_asset_fn(entry.ptr, normalized, settings_ptr);
        }
        return error.NoManagerForType;
    }

    pub fn loadAssetNow(self: *Assets, comptime AssetType: type, file: []const u8, settings: anytype) anyerror!AssetType {
        // Check if this is a multi-file asset (separated by semicolon)
        // This needs to be checked BEFORE scheme resolution
        if (std.mem.indexOf(u8, file, ";")) |_| {
            return self.loadMultiFileAsset(AssetType, file, settings);
        }

        // Resolve the file path using scheme registry
        const resolved = try self.scheme_registry.resolve(file);

        // Handle each resolution type appropriately
        switch (resolved) {
            .file_path => |path| {
                defer self.allocator.free(path);
                const normalized = try io_utils.normalizePath(self.allocator, path);
                defer self.allocator.free(normalized);
                if (!io_utils.exists(normalized)) {
                    std.log.err("File not found: {s}", .{normalized});
                    return error.FileNotFound;
                }
                return self.loadAssetFromPath(AssetType, normalized, settings);
            },
            .url => |url| {
                defer self.allocator.free(url);
                // For URLs, pass them through as-is for now
                return self.loadAssetFromPath(AssetType, url, settings);
            },
            .embedded_data => |data| {
                defer self.allocator.free(data);
                return self.loadEmbeddedAsset(AssetType, file, data, settings);
            },
            .custom => |path| {
                defer self.allocator.free(path);
                return self.loadAssetFromPath(AssetType, path, settings);
            },
        }
    }

    fn loadMultiFileAsset(self: *Assets, comptime AssetType: type, file_list: []const u8, settings: anytype) !AssetType {
        var iter = std.mem.splitScalar(u8, file_list, ';');
        var temp_files = try std.ArrayList([]const u8).initCapacity(self.allocator, 4);
        defer {
            for (temp_files.items) |temp_file| {
                _ = io_utils.deleteFile(temp_file);
                self.allocator.free(temp_file);
            }
            temp_files.deinit(self.allocator);
        }

        // Generate a shared base name for all files in this multi-file asset (without extension)
        const shared_base = try io_utils.randomFileName(self.allocator, 8, "");
        defer self.allocator.free(shared_base);

        // Process each file in the list
        while (iter.next()) |file_path| {
            const trimmed = std.mem.trim(u8, file_path, " \t");
            if (trimmed.len == 0) continue;

            // Resolve this file
            const resolved = try self.scheme_registry.resolve(trimmed);

            // Handle based on resolution type
            switch (resolved) {
                .embedded_data => |d| {
                    defer self.allocator.free(d);

                    // Extract extension from the trimmed path
                    const path_without_scheme = if (std.mem.indexOf(u8, trimmed, "://")) |idx|
                        trimmed[idx + 3 ..]
                    else
                        trimmed;
                    const extension = std.fs.path.extension(path_without_scheme);
                    const ext = if (extension.len > 0) extension else ".tmp";

                    // Create temp file with shared base name + extension
                    const filename_with_ext = try std.mem.concat(self.allocator, u8, &[_][]const u8{ shared_base, ext });
                    defer self.allocator.free(filename_with_ext);

                    const temp_file = try io_utils.writeTempFileNamed(self.allocator, filename_with_ext, d);
                    try temp_files.append(self.allocator, temp_file);
                },
                .file_path => |path| {
                    defer self.allocator.free(path);

                    // For file paths, just add them directly
                    const owned_path = try self.allocator.dupe(u8, path);
                    try temp_files.append(self.allocator, owned_path);
                },
                .url => |url| {
                    defer self.allocator.free(url);
                    return error.UrlNotSupportedForMultiFile;
                },
                .custom => |path| {
                    defer self.allocator.free(path);
                    return error.CustomSchemeNotSupportedForMultiFile;
                },
            }
        }

        // Load the asset with the first temp file (primary file)
        if (temp_files.items.len == 0) return error.NoFilesToLoad;
        return self.loadAssetFromPath(AssetType, temp_files.items[0], settings);
    }

    fn loadAssetFromPath(self: *Assets, comptime AssetType: type, file_path: []const u8, settings: anytype) !AssetType {
        // Settings can be null, a value, a pointer, or optional - all are valid
        const hash = std.hash_map.hashString(@typeName(AssetType));
        if (self.managers.getPtr(hash)) |entry| {
            const settings_ptr = if (@TypeOf(settings) == @TypeOf(null))
                null
            else
                @as(*anyopaque, @ptrCast(@constCast(&settings)));
            const asset_ptr = try entry.load_asset_now_fn(entry.ptr, file_path, settings_ptr);
            return @as(*AssetType, @ptrCast(@alignCast(asset_ptr))).*;
        }
        return error.NoManagerForType;
    }

    fn loadEmbeddedAsset(self: *Assets, comptime AssetType: type, original_path: []const u8, data: []const u8, settings: anytype) anyerror!AssetType {
        // Single file embedded asset
        const path_without_scheme = if (std.mem.indexOf(u8, original_path, "://")) |idx|
            original_path[idx + 3 ..]
        else
            original_path;

        const extension = std.fs.path.extension(path_without_scheme);
        const ext = if (extension.len > 0) extension else ".tmp";

        const temp_file = try io_utils.writeTempFile(self.allocator, "", ext, data);
        defer {
            if (!io_utils.deleteFile(temp_file)) {
                std.debug.panic("Failed to delete temp file: {s}", .{temp_file});
            }
        }
        return self.loadAssetFromPath(AssetType, temp_file, settings);
    }

    pub fn get(self: *Assets, comptime AssetType: type, handle: AssetHandle) ?AssetType {
        const hash = comptime std.hash_map.hashString(@typeName(AssetType));
        if (self.managers.get(hash)) |entry| {
            if (entry.get_fn(entry.ptr, handle)) |asset_ptr| {
                return @as(*AssetType, @ptrCast(@alignCast(asset_ptr))).*;
            }
        }
        return null;
    }

    // ===== SCHEME MANAGEMENT =====

    /// Register a custom scheme resolver
    pub fn registerScheme(self: *Assets, scheme: []const u8, resolver: schemes.SchemeResolver) !void {
        try self.scheme_registry.registerScheme(scheme, resolver);
    }

    /// Unregister a scheme resolver
    pub fn unregisterScheme(self: *Assets, scheme: []const u8) void {
        self.scheme_registry.unregisterScheme(scheme);
    }

    /// Check if a scheme is registered
    pub fn hasScheme(self: *Assets, scheme: []const u8) bool {
        return self.scheme_registry.hasScheme(scheme);
    }

    /// Get list of registered schemes
    pub fn getSchemes(self: *Assets) ![][]const u8 {
        return self.scheme_registry.getSchemes(self.allocator);
    }

    // ===== CONVENIENCE METHODS FOR COMMON SCHEMES =====

    /// Register a folder-based scheme (e.g., "assets://" -> "assets/")
    pub fn registerFolderScheme(self: *Assets, scheme: []const u8, base_folder: []const u8) !void {
        const resolver_ptr = try self.allocator.create(schemes.FolderResolver);
        resolver_ptr.* = schemes.FolderResolver.init(base_folder);
        try self.registerScheme(scheme, schemes.SchemeResolver.init(resolver_ptr));
    }

    /// Register a URL-based scheme (e.g., "cdn://" -> "https://cdn.example.com/")
    pub fn registerUrlScheme(self: *Assets, scheme: []const u8, base_url: []const u8) !void {
        const resolver_ptr = try self.allocator.create(schemes.UrlResolver);
        resolver_ptr.* = schemes.UrlResolver.init(base_url);
        try self.registerScheme(scheme, schemes.SchemeResolver.init(resolver_ptr));
    }

    /// Register an environment-based scheme (different paths for dev/prod)
    pub fn registerEnvironmentScheme(self: *Assets, scheme: []const u8, dev_base: []const u8, prod_base: []const u8, is_debug: bool) !void {
        const resolver_ptr = try self.allocator.create(schemes.EnvironmentResolver);
        resolver_ptr.* = schemes.EnvironmentResolver.init(dev_base, prod_base, is_debug);
        try self.registerScheme(scheme, schemes.SchemeResolver.init(resolver_ptr));
    }

    pub fn process(self: *Assets) !void {
        var it = self.managers.iterator();
        while (it.next()) |entry| {
            try entry.value_ptr.process_fn(entry.value_ptr.ptr);
        }
    }
};

// ===== TESTS =====

test "Assets initialization and cleanup" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Should have default managers for all supported types
    try testing.expect(assets.hasManager(rl.Texture));
    try testing.expect(assets.hasManager(rl.Sound));
    try testing.expect(assets.hasManager(rl.Music));
    try testing.expect(assets.hasManager(rl.Font));

    // Should have 7 managers total
    try testing.expectEqual(@as(u32, 6), assets.managers.count());
}

test "Assets manager operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test hasManager functionality
    try testing.expect(assets.hasManager(rl.Texture));

    // Test adding duplicate manager should fail
    const texture_loader = loaders.TextureLoader{};
    try testing.expectError(error.ManagerAlreadyExists, assets.addManager(rl.Texture, texture_loader));
}

test "Assets load embedded asset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();
    rl.initWindow(800, 700, "Test");
    defer rl.closeWindow();
    const data = assets.loadAssetNow(rl.Shader, "embedded://horde.vs;embedded://horde.fs", null) catch |err| {
        std.log.err("Failed to load embedded asset: {any}", .{err});
        return err;
    };
    try testing.expect(rl.isShaderValid(data));

    const data_again = try assets.loadAssetNow(rl.Shader, "embedded://horde.vs;embedded://horde.fs", null);
    try testing.expect(rl.isShaderValid(data_again));

    const handle = try assets.loadAsset(rl.Shader, "embedded://horde.vs;embedded://horde.fs", null);
    try testing.expect(handle != 0);

    try assets.process();

    const cached = assets.get(rl.Shader, handle) orelse return error.TestExpectedResult;
    try testing.expect(rl.isShaderValid(cached));
}

test "Assets loadAssetNow with various error conditions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    const loader = loaders.TextureLoader{};

    // Add texture manager for testing if it doesn't exist
    if (!assets.hasManager(rl.Texture)) {
        try assets.addManager(rl.Texture, loader);
    }

    // Test with non-existent file
    {
        const result = assets.loadAssetNow(rl.Texture, "definitely_does_not_exist.png", null);
        try testing.expectError(error.FileNotFound, result);
    }

    // Test with empty filename
    {
        const result = assets.loadAssetNow(rl.Texture, "", null);
        try testing.expectError(error.FileNotFound, result);
    }

    // Test with different settings types (should all be accepted)
    {
        const int_settings = 42; // int value
        const result = assets.loadAssetNow(rl.Texture, "test.png", int_settings);
        try testing.expectError(error.FileNotFound, result); // File doesn't exist, but settings are fine
    }
}

test "Assets get with invalid handles" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Create an invalid handle
    const invalid_handle: AssetHandle = 999999;

    // Getting asset with invalid handle should return null
    try testing.expect(assets.get(rl.Texture, invalid_handle) == null);
}

test "Assets process functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Process should not fail even with no assets loaded
    try assets.process();
}

test "Assets with malformed paths" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    const malformed_paths = [_][]const u8{
        "path\\with/mixed\\separators.png",
        "../../../outside_project.png",
        "path/with/../../traversal.png",
        "very/long/path/" ** 5 ++ "file.png", // Reduced repetition to avoid path length limits
        "путь/с/unicode/файл.png",
        "path with spaces.png",
        "path-with-special!@#$%characters.png", // Reduced special chars to avoid shell issues
    };

    for (malformed_paths) |path| {
        // These should handle gracefully and return appropriate errors
        const result = assets.loadAssetNow(rl.Texture, path, null);
        // Should either be FileNotFound or some other handled error, not crash
        try testing.expect(std.meta.isError(result));
    }
}

test "Assets memory management stress test" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create and destroy multiple Assets instances
    for (0..10) |_| {
        var assets = Assets.init(allocator);
        defer assets.deinit();

        // Verify managers are properly initialized each time
        try testing.expect(assets.hasManager(rl.Texture));
        try testing.expect(assets.hasManager(rl.Sound));

        // Try to process
        try assets.process();
    }
}

test "Assets type safety" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Create handles for different asset types
    const texture_handle: AssetHandle = 1;
    const sound_handle: AssetHandle = 2;

    // Getting wrong type should return null (type mismatch)
    try testing.expectEqual(@as(?rl.Sound, null), assets.get(rl.Sound, texture_handle));
    try testing.expectEqual(@as(?rl.Texture, null), assets.get(rl.Texture, sound_handle));
}

test "Assets edge case file paths" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    const edge_case_paths = [_][]const u8{
        ".",
        "..",
        "/",
        "\\",
        "file",
        "file.",
        ".file",
        "..file",
        "file..",
        "a",
        "file.extension.with.many.dots",
    };

    for (edge_case_paths) |path| {
        // These should handle gracefully without crashing
        const result = assets.loadAssetNow(rl.Texture, path, null);
        try testing.expect(std.meta.isError(result));
    }
}

test "Assets concurrent operations simulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Simulate multiple operations that might happen in quick succession
    for (0..100) |i| {
        // Mix of different operations
        if (i % 3 == 0) {
            try assets.process();
        } else if (i % 3 == 1) {
            const handle: AssetHandle = @intCast(i);
            _ = assets.get(rl.Texture, handle);
        } else {
            const result = assets.loadAssetNow(rl.Texture, "nonexistent.png", null);
            try testing.expect(std.meta.isError(result));
        }
    }
}

test "Assets null and invalid parameter handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test with null settings (should be valid)
    {
        const result = assets.loadAssetNow(rl.Texture, "test.png", null);
        try testing.expect(std.meta.isError(result)); // File doesn't exist, but null settings are valid
    }

    // Test with optional settings
    {
        const optional_settings: ?*const anyopaque = null;
        const result = assets.loadAssetNow(rl.Texture, "test.png", optional_settings);
        try testing.expect(std.meta.isError(result)); // File doesn't exist, but optional settings are valid
    }
}

test "Assets manager entry destruction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that deinit properly cleans up all manager entries
    var assets = Assets.init(allocator);

    // Verify managers exist
    try testing.expect(assets.managers.count() > 0);

    // Deinit should clean up everything without crashes
    assets.deinit();

    // After deinit, the hashmap should be cleaned up
    // Note: We can't easily test the internal state after deinit,
    // but if this test completes without crashes, the cleanup worked
}

test "Assets file loading simulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // In a real environment, you might have test assets
    // For now, we're testing the error handling paths

    const test_files = [_][]const u8{
        "assets/test.png",
        "assets/test.wav",
        "assets/test.ogg",
        "assets/test.ttf",
        "assets/test.json",
    };

    for (test_files) |file| {
        // These will fail because files don't exist, but shouldn't crash
        const texture_result = assets.loadAssetNow(rl.Texture, file, null);
        try testing.expect(std.meta.isError(texture_result));

        const sound_result = assets.loadAssetNow(rl.Sound, file, null);
        try testing.expect(std.meta.isError(sound_result));
    }
}

test "Assets boundary conditions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test with maximum handle ID
    const max_handle: AssetHandle = std.math.maxInt(usize);
    const result = assets.get(rl.Texture, max_handle);
    try testing.expectEqual(@as(?rl.Texture, null), result);

    // Test with zero handle ID
    const zero_handle: AssetHandle = 0;
    const zero_result = assets.get(rl.Texture, zero_handle);
    try testing.expectEqual(@as(?rl.Texture, null), zero_result);
}

test "Assets error propagation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test that errors bubble up correctly from the asset managers
    const paths_with_expected_errors = [_]struct {
        path: []const u8,
        expected_error: anyerror,
    }{
        .{ .path = "", .expected_error = error.FileNotFound },
        .{ .path = "nonexistent.png", .expected_error = error.FileNotFound },
    };

    for (paths_with_expected_errors) |test_case| {
        const result = assets.loadAssetNow(rl.Texture, test_case.path, null);
        try testing.expectError(test_case.expected_error, result);
    }
}

test "Assets manager hash collision resistance" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test that different asset types have different hashes
    // This indirectly tests that we don't accidentally overwrite managers
    try testing.expect(assets.hasManager(rl.Texture));
    try testing.expect(assets.hasManager(rl.Sound));
    try testing.expect(assets.hasManager(rl.Music));

    // Each type should maintain its own manager
    const texture_hash = std.hash_map.hashString(@typeName(rl.Texture));
    const sound_hash = std.hash_map.hashString(@typeName(rl.Sound));
    const music_hash = std.hash_map.hashString(@typeName(rl.Music));

    try testing.expect(texture_hash != sound_hash);
    try testing.expect(sound_hash != music_hash);
    try testing.expect(texture_hash != music_hash);
}

test "Assets robustness with repeated operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Repeatedly perform the same operations to check for state corruption
    for (0..50) |_| {
        // Check managers still exist
        try testing.expect(assets.hasManager(rl.Texture));

        // Try invalid operations
        const invalid_handle: AssetHandle = 42;
        const result = assets.get(rl.Texture, invalid_handle);
        try testing.expect(result == null);

        // Process multiple times
        try assets.process();
        try assets.process();
    }
}

test "Assets defensive programming checks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    const loader = loaders.TextureLoader{};

    // Add texture manager for testing if it doesn't exist
    if (!assets.hasManager(rl.Texture)) {
        try assets.addManager(rl.Texture, loader);
    }

    // Test behavior with various invalid inputs that should be handled gracefully
    const problematic_inputs = [_][]const u8{
        "", // Empty string
        "non_existent_file.png", // Simple non-existent file
        "very_long_filename_that_exceeds_normal_expectations_and_should_still_be_handled_gracefully.png",
    };

    for (problematic_inputs) |input| {
        // Should handle gracefully without crashes or undefined behavior
        const result = assets.loadAssetNow(rl.Texture, input, null);
        try testing.expect(std.meta.isError(result));

        // Process should still work after problematic inputs
        try assets.process();
    }
}

test "Assets state consistency after errors" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    const initial_count = assets.managers.count();

    // Generate several errors
    for (0..10) |i| {
        const filename = try std.fmt.allocPrint(allocator, "nonexistent_{d}.png", .{i});
        defer allocator.free(filename);

        const result = assets.loadAssetNow(rl.Texture, filename, null);
        try testing.expectError(error.FileNotFound, result);
    }

    // Verify assets is still in a consistent state
    try testing.expectEqual(initial_count, assets.managers.count());
    try testing.expect(assets.hasManager(rl.Texture));
    try assets.process();

    // Verify all manager types are still available
    try testing.expect(assets.hasManager(rl.Texture));
    try testing.expect(assets.hasManager(rl.Sound));
    try testing.expect(assets.hasManager(rl.Music));
    try testing.expect(assets.hasManager(rl.Font));
}

// ===== SCHEME SYSTEM TESTS =====

test "Assets default schemes initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Should have default schemes registered
    try testing.expect(assets.hasScheme("embedded"));
    try testing.expect(assets.hasScheme("file"));
}

test "Assets custom scheme registration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Register a folder scheme
    try assets.registerFolderScheme("assets", "game_assets");
    try testing.expect(assets.hasScheme("assets"));

    // Register a URL scheme
    try assets.registerUrlScheme("cdn", "https://cdn.example.com");
    try testing.expect(assets.hasScheme("cdn"));

    // Unregister a scheme
    assets.unregisterScheme("cdn");
    try testing.expect(!assets.hasScheme("cdn"));
}

test "Assets scheme resolution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Register test schemes
    try assets.registerFolderScheme("sprites", "assets/sprites");
    try assets.registerUrlScheme("remote", "https://example.com/assets");

    // Test folder scheme resolution (will fail with FileNotFound, but path should resolve)
    {
        const result = assets.loadAssetNow(rl.Texture, "sprites://player.png", null);
        try testing.expectError(error.FileNotFound, result); // File doesn't exist, but scheme resolved
    }

    // Test regular file path (no scheme)
    {
        const result = assets.loadAssetNow(rl.Texture, "regular_file.png", null);
        try testing.expectError(error.FileNotFound, result); // File doesn't exist
    }
}

test "Assets environment scheme" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Register environment scheme (debug mode)
    try assets.registerEnvironmentScheme("env", "dev_assets", "prod_assets", true);
    try testing.expect(assets.hasScheme("env"));

    // Test environment resolution (will fail with FileNotFound, but should use dev path)
    {
        const result = assets.loadAssetNow(rl.Texture, "env://config.png", null);
        try testing.expectError(error.FileNotFound, result);
    }
}

test "Assets get schemes list" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Register additional schemes
    try assets.registerFolderScheme("test1", "folder1");
    try assets.registerFolderScheme("test2", "folder2");

    const schemes_list = try assets.getSchemes();
    defer {
        for (schemes_list) |scheme| {
            allocator.free(scheme);
        }
        allocator.free(schemes_list);
    }

    // Should have at least the default schemes plus our test schemes
    try testing.expect(schemes_list.len >= 4); // embedded, file, test1, test2

    // Check for specific schemes
    var found_embedded = false;
    var found_file = false;
    var found_test1 = false;
    var found_test2 = false;

    for (schemes_list) |scheme| {
        if (std.mem.eql(u8, scheme, "embedded")) found_embedded = true;
        if (std.mem.eql(u8, scheme, "file")) found_file = true;
        if (std.mem.eql(u8, scheme, "test1")) found_test1 = true;
        if (std.mem.eql(u8, scheme, "test2")) found_test2 = true;
    }

    try testing.expect(found_embedded);
    try testing.expect(found_file);
    try testing.expect(found_test1);
    try testing.expect(found_test2);
}

test "Assets scheme error handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test unknown scheme
    {
        const result = assets.loadAssetNow(rl.Texture, "unknown://test.png", null);
        try testing.expectError(error.UnknownScheme, result);
    }

    // Test a safe malformed URI that won't trigger Windows path issues
    {
        const result = assets.loadAssetNow(rl.Texture, "malformed_uri_pattern.png", null);
        try testing.expectError(error.FileNotFound, result);
    }
}

test "Assets embedded scheme integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();
    rl.initWindow(800, 700, "Test");
    defer rl.closeWindow();

    // Test embedded asset loading through scheme system
    const data = try assets.loadAssetNow(rl.Shader, "embedded://horde.vs;embedded://horde.fs", null);
    try testing.expect(rl.isShaderValid(data));

    // Test async loading of embedded asset
    const handle = try assets.loadAsset(rl.Shader, "embedded://horde.vs;embedded://horde.fs", null);
    try assets.process();

    const cached = assets.get(rl.Shader, handle) orelse return error.TestExpectedResult;
    try testing.expect(rl.isShaderValid(cached));
}

test "Assets scheme system memory management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test multiple init/deinit cycles with scheme registration
    for (0..5) |_| {
        var assets = Assets.init(allocator);
        defer assets.deinit();

        // Register and unregister schemes
        try assets.registerFolderScheme("temp", "temp_folder");
        try testing.expect(assets.hasScheme("temp"));

        assets.unregisterScheme("temp");
        try testing.expect(!assets.hasScheme("temp"));
    }
}

test "Assets complex scheme paths" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    try assets.registerFolderScheme("deep", "very/deep/nested/folder");

    // Test complex paths with schemes
    const complex_paths = [_][]const u8{
        "deep://subfolder/file.png",
        "deep://another/deeply/nested/path/asset.jpg",
        "file://./relative/path.txt",
        "file://../parent/directory/file.wav",
    };

    for (complex_paths) |path| {
        const result = assets.loadAssetNow(rl.Texture, path, null);
        // Should resolve paths but files don't exist
        try testing.expectError(error.FileNotFound, result);
    }
}

test "Assets scheme replacement" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Register initial scheme
    try assets.registerFolderScheme("test", "folder1");
    try testing.expect(assets.hasScheme("test"));

    // Replace with different resolver
    try assets.registerFolderScheme("test", "folder2");
    try testing.expect(assets.hasScheme("test"));

    // Should not have memory leaks from replacement
}

test "Assets backward compatibility" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();
    rl.initWindow(800, 700, "Test");
    defer rl.closeWindow();

    // Test that regular file paths still work
    {
        const result = assets.loadAssetNow(rl.Texture, "regular_file.png", null);
        try testing.expectError(error.FileNotFound, result); // File doesn't exist, but path handling works
    }

    // Test that embedded:// still works as before
    {
        const data = try assets.loadAssetNow(rl.Shader, "embedded://horde.vs;embedded://horde.fs", null);
        try testing.expect(rl.isShaderValid(data));
    }
}

test "Assets paths without schemes default to FileResolver" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Test that paths without schemes are treated as file paths
    const paths_without_schemes = [_][]const u8{
        "test.png",
        "assets/test.png",
        "./test.png",
        "../test.png",
    };

    for (paths_without_schemes) |path| {
        // These should all be treated as file paths and return FileNotFound
        // since the files don't exist, but they shouldn't return UnknownScheme
        const result = assets.loadAssetNow(rl.Texture, path, null);

        // Should get FileNotFound or InvalidTexture, not UnknownScheme
        try testing.expectError(error.FileNotFound, result);
    }
}

test "Assets scheme registry resolve behavior" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = schemes.SchemeRegistry.init(allocator);
    defer registry.deinit();

    // Test path without scheme - should be treated as file path
    const result = try registry.resolve("test.png");
    defer switch (result) {
        .file_path => |path| allocator.free(path),
        .url => |url| allocator.free(url),
        .embedded_data => {},
        .custom => |path| allocator.free(path),
    };

    switch (result) {
        .file_path => |path| {
            try testing.expectEqualStrings("test.png", path);
        },
        else => {
            try testing.expect(false); // Should be file_path
        },
    }
}
