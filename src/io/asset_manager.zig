const std = @import("std");
const schemes = @import("scheme_resolver.zig");
const loader_contracts = @import("loader.zig");
const AssetLoaderTemplate = loader_contracts.AssetLoaderTemplate;
const AssetUnloaderTemplate = loader_contracts.AssetUnloaderTemplate;
const FileResolver = loader_contracts.FileResolver;
const AssetProcessorTemplate = @import("processor.zig").AssetProcessorTemplate;

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
        var threaded = std.Io.Threaded.init_single_threaded;
        const io = threaded.io();
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator);
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
fn fileResolverResolvePath(resolver: *const FileResolver, allocator: std.mem.Allocator, relative_path: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fs.path.join(allocator, &[_][]const u8{ resolver.base_dir, relative_path });
}

fn fileResolverPathExists(resolver: *const FileResolver, relative_path: []const u8) bool {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();
    var dir = std.Io.Dir.openDirAbsolute(io, resolver.base_dir, .{}) catch return false;
    defer dir.close(io);

    const file = dir.openFile(io, relative_path, .{ .mode = .read_only }) catch return false;
    file.close(io);
    return true;
}

/// AssetManager without post-load processor support.
///
/// Parameters:
///   - AssetType: The asset type returned by the loader (and optionally modified by the processor)
///   - LoaderType: The loader type implementing the load interface
pub fn AssetManager(comptime AssetType: type, comptime LoaderType: type) type {
    return AssetManagerWithProcessor(AssetType, LoaderType, void);
}

/// AssetManager with post-load processor support.
///
/// Parameters:
///   - AssetType: The asset type returned by the loader (and optionally modified by the processor)
///   - LoaderType: The loader type implementing the load interface
///   - ProcessorType: Optional processor type. Pass `void` for no processing.
///                    The processor modifies the asset in-place.
pub fn AssetManagerWithProcessor(comptime AssetType: type, comptime LoaderType: type, comptime ProcessorType: type) type {
    const LoaderTemplate = AssetLoaderTemplate(AssetType);
    const UnloaderTemplate = AssetUnloaderTemplate(AssetType);
    const has_processor = ProcessorType != void;

    LoaderTemplate.validate(LoaderType);
    UnloaderTemplate.validate(LoaderType);

    const ProcessorTemplate = if (has_processor) AssetProcessorTemplate(AssetType) else void;
    if (has_processor) ProcessorTemplate.validate(ProcessorType);
    const AssetProcessor = if (has_processor) ProcessorTemplate.InterfaceFor(ProcessorType) else void;

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
        scheme_registry: ?*schemes.SchemeRegistry,
        mutex: std.Thread.Mutex,
        assets: std.StringHashMap(AssetEntry),
        queue: std.ArrayList(LoadRequest),
        loader: LoaderType,
        processor: AssetProcessor,
        processor_settings: if (has_processor) ?ProcessorType.ProcessSettings else void,

        const Self = @This();

        fn initBase(allocator: std.mem.Allocator, loader: LoaderType, scheme_registry: ?*schemes.SchemeRegistry) error{OutOfMemory}!Self {
            return Self{
                .allocator = allocator,
                .scheme_registry = scheme_registry,
                .mutex = std.Thread.Mutex{},
                .assets = std.StringHashMap(AssetEntry).init(allocator),
                .queue = try std.ArrayList(LoadRequest).initCapacity(allocator, 0),
                .loader = loader,
                .processor = if (has_processor) undefined else void,
                .processor_settings = if (has_processor) null else {},
            };
        }

        /// Initialize an AssetManager without a processor
        pub fn init(allocator: std.mem.Allocator, loader: LoaderType) error{OutOfMemory}!Self {
            if (has_processor) {
                @compileError("AssetManager with ProcessorType requires initWithProcessor()");
            }
            return initBase(allocator, loader, null);
        }

        pub fn initWithSchemeRegistry(allocator: std.mem.Allocator, loader: LoaderType, scheme_registry: *schemes.SchemeRegistry) error{OutOfMemory}!Self {
            if (has_processor) {
                @compileError("AssetManager with ProcessorType requires initWithProcessor() or initWithProcessorAndSchemeRegistry()");
            }
            return initBase(allocator, loader, scheme_registry);
        }

        /// Initialize an AssetManager with a processor
        pub fn initWithProcessor(allocator: std.mem.Allocator, loader: LoaderType, processor: ProcessorType, processor_settings: ?ProcessorType.ProcessSettings) error{OutOfMemory}!Self {
            if (!has_processor) {
                @compileError("AssetManager without a ProcessorType cannot use initWithProcessor()");
            }

            var self = try initBase(allocator, loader, null);
            ProcessorTemplate.populate(&self.processor, &processor);
            self.processor_settings = processor_settings;
            return self;
        }

        pub fn initWithProcessorAndSchemeRegistry(allocator: std.mem.Allocator, loader: LoaderType, processor: ProcessorType, processor_settings: ?ProcessorType.ProcessSettings, scheme_registry: *schemes.SchemeRegistry) error{OutOfMemory}!Self {
            if (!has_processor) {
                @compileError("AssetManager without a ProcessorType cannot use initWithProcessorAndSchemeRegistry()");
            }

            var self = try initBase(allocator, loader, scheme_registry);
            ProcessorTemplate.populate(&self.processor, &processor);
            self.processor_settings = processor_settings;
            return self;
        }

        pub fn deinit(self: *Self) void {
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

        pub fn count(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.assets.len;
        }

        pub fn amount(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.queue.items.len;
        }

        pub fn loadAsset(self: *Self, file: []const u8, settings: anytype) error{ InvalidPath, OutOfMemory }!AssetHandle {
            // Check if already loaded — must hold the mutex here to avoid a
            // data race: another thread may concurrently call process() which
            // writes to self.assets.  (loadAssetNow uses the same pattern.)
            self.mutex.lock();
            if (self.assets.get(file)) |entry| {
                const existing = entry.id;
                self.mutex.unlock();
                return existing;
            }
            self.mutex.unlock();

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
                return error.OutOfMemory;
            };

            return id;
        }

        pub fn process(self: *Self) anyerror!void {
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

            self.mutex.lock();
            const already_loaded = self.assets.get(req.?.file) != null;
            self.mutex.unlock();

            if (already_loaded) {
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

            const embedded = isEmbeddedPath(req.?.file);
            if (!embedded and !@import("util.zig").exists(absolute_path)) {
                self.allocator.free(req.?.file); // Free the owned file string
                return error.FileNotFound;
            }
            // Create FileResolver for complex loaders
            // For embedded paths, preserve the original URI for relative path resolution
            const asset_dir = if (!embedded) std.fs.path.dirname(absolute_path) orelse "." else "";
            var resolver_storage: FileResolver = .{
                .base_dir = asset_dir,
                .original_uri = if (embedded) req.?.file else null,
                .scheme_registry = self.scheme_registry,
                .resolve_path = fileResolverResolvePath,
                .path_exists = fileResolverPathExists,
            };
            const resolver_ptr: *const FileResolver = &resolver_storage;

            // Convert settings to pointer if not null
            const settings_ptr = if (req.?.settings) |s| &s else null;
            var raw_asset = try self.loader.load(absolute_path, resolver_ptr, settings_ptr);

            // Run processor if configured (modifies asset in-place)
            if (has_processor) {
                const proc_settings_ptr = if (self.processor_settings) |s| &s else null;
                self.processor.process(&raw_asset, self.allocator, resolver_ptr, proc_settings_ptr) catch |err| {
                    // If processing fails, unload the raw asset
                    self.loader.unload(raw_asset);
                    return err;
                };
            }

            // Now safely store the result
            const entry = AssetEntry{
                .id = req.?.id,
                .asset = raw_asset,
            };

            self.mutex.lock();
            if (self.assets.get(req.?.file)) |_| {
                self.mutex.unlock();
                self.loader.unload(raw_asset);
                self.allocator.free(req.?.file);
                return;
            }
            self.assets.put(req.?.file, entry) catch |err| {
                self.mutex.unlock();
                self.loader.unload(raw_asset);
                self.allocator.free(req.?.file);
                return err;
            };
            self.mutex.unlock();
        }

        pub fn unloadAsset(self: *Self, handle: AssetHandle) void {
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

        pub fn getAsset(self: *Self, handle: AssetHandle) ?*AssetType {
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

        pub fn isLoaded(self: *Self, handle: AssetHandle) bool {
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

        pub fn loadAssetNow(self: *Self, file: []const u8, settings: ?LoaderType.LoadSettings) anyerror!AssetHandle {
            // Validate path early, before taking mutex
            if (!isValidAssetPath(file)) {
                return error.InvalidPath;
            }

            // Quick check with mutex if already loaded
            self.mutex.lock();
            if (self.assets.get(file)) |entry| {
                const existing = entry.id;
                self.mutex.unlock();
                return existing;
            }
            // We will perform the potentially expensive loader.load OUTSIDE the mutex
            self.mutex.unlock();

            // Convert to absolute path
            const absolute_path = try resolveAbsolutePath(self.allocator, file);
            defer self.allocator.free(absolute_path);

            // Create FileResolver for complex loaders
            // For embedded paths, preserve the original URI for relative path resolution
            const embedded = isEmbeddedPath(file);
            const asset_dir = if (!embedded) std.fs.path.dirname(absolute_path) orelse "." else "";
            var resolver_storage: FileResolver = .{
                .base_dir = asset_dir,
                .original_uri = if (embedded) file else null,
                .scheme_registry = self.scheme_registry,
                .resolve_path = fileResolverResolvePath,
                .path_exists = fileResolverPathExists,
            };
            const resolver_ptr: *const FileResolver = &resolver_storage;

            // Convert settings to pointer if not null
            const settings_ptr = if (settings) |s| &s else null;
            var raw_asset = try self.loader.load(absolute_path, resolver_ptr, settings_ptr);

            // Run processor if configured (modifies asset in-place)
            if (has_processor) {
                const proc_settings_ptr = if (self.processor_settings) |s| &s else null;
                self.processor.process(&raw_asset, self.allocator, resolver_ptr, proc_settings_ptr) catch |err| {
                    // If processing fails, unload the raw asset
                    self.loader.unload(raw_asset);
                    return err;
                };
            }

            const id = generateHandle(file);

            const entry = AssetEntry{
                .id = id,
                .asset = raw_asset,
            };

            // Ensure no other thread loaded the same asset in the meantime
            self.mutex.lock();
            if (self.assets.get(file)) |existing_entry| {
                // Someone else loaded it while we were loading; drop our asset and return existing id
                const existing_id = existing_entry.id;
                self.mutex.unlock();
                // Unload the asset we created since manager will own the duplicate
                self.loader.unload(raw_asset);
                return existing_id;
            }

            // Create owned key for HashMap and store the asset
            const owned_key = try self.allocator.dupe(u8, file);
            self.assets.put(owned_key, entry) catch |err| {
                self.mutex.unlock();
                self.allocator.free(owned_key);
                self.loader.unload(raw_asset);
                return err;
            };
            self.mutex.unlock();

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

        pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const FileResolver, _settings: ?*const LoadSettings) anyerror!TestAsset {
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
    var manager = try AssetManagerWithProcessor(TestAsset, TestLoader, void).init(std.testing.allocator, TestLoader{});
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

        pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const FileResolver, _settings: ?*const LoadSettings) anyerror!TestAsset {
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
    var manager = try AssetManager(TestAsset, TestLoader).init(std.testing.allocator, TestLoader{});
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
        pub fn load(_: @This(), _: []const u8, _: ?*const FileResolver, _: ?*const LoadSettings) anyerror!TestAsset {
            return 42;
        }
        pub fn extensions() []const []const u8 {
            return &[_][]const u8{".txt"};
        }
        pub fn unload(_: @This(), _: TestAsset) void {}
    };
    var manager = try AssetManager(TestAsset, TestLoader).init(std.testing.allocator, TestLoader{});
    defer manager.deinit();

    // Test loadAssetNow with invalid paths
    try std.testing.expectError(error.InvalidPath, manager.loadAssetNow(".", null));
    try std.testing.expectError(error.InvalidPath, manager.loadAssetNow("..", null));
    try std.testing.expectError(error.InvalidPath, manager.loadAssetNow("\\", null));
}
