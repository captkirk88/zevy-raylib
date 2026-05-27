const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const reflect = @import("zevy_reflect");
const io_utils = @import("util.zig");
const schemes = @import("scheme_resolver.zig");
const types = @import("types.zig");
const xml = @import("xml.zig");
const icons_parser = @import("../input/icons_parser.zig");

const SKIP_IN_DEBUG = true;
const is_debug = builtin.mode == .Debug;
const should_skip = if (SKIP_IN_DEBUG and is_debug) true else false;

pub const AssetHandle = u64;

/// Context passed to loaders - contains everything needed to load an asset
/// and resolve relative paths correctly (preserves original URI scheme)
pub const LoadContext = struct {
    allocator: std.mem.Allocator,
    /// Original URI (e.g., "embedded://path/to/file.xml")
    uri: []const u8,
    /// Reference to scheme registry for resolving URIs
    scheme_registry: *schemes.SchemeRegistry,
    /// Reference back to Assets for loading related assets
    assets: *anyopaque,

    /// Read the main asset's data as bytes
    pub fn readData(self: *const LoadContext) ![]const u8 {
        var result = try self.scheme_registry.resolve(self.allocator, self.uri);
        switch (result) {
            .embedded_data => |data| {
                return data; // Caller owns this memory
            },
            .file_path => |path| {
                defer result.deinit(self.allocator);
                var threaded = std.Io.Threaded.init_single_threaded;
                const io = threaded.io();
                const dir_path = std.fs.path.dirname(path) orelse ".";
                const base_name = std.fs.path.basename(path);
                var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{}) catch |err| {
                    if (err == error.FileNotFound) return error.FileNotFound;
                    return err;
                };
                defer dir.close(io);

                var file = dir.openFile(io, base_name, .{}) catch |err| {
                    if (err == error.FileNotFound) return error.FileNotFound;
                    return err;
                };
                defer file.close(io);

                var buffer: [4096]u8 = undefined;
                var file_reader = file.reader(io, &buffer);
                return file_reader.interface.allocRemaining(self.allocator, .limited(50 * 1024 * 1024));
            },
            .url => {
                result.deinit(self.allocator);
                return error.UrlNotSupported;
            },
            .raw => {
                result.deinit(self.allocator);
                return error.CustomSchemeNotSupported;
            },
        }
    }

    /// Get the parent directory URI (e.g., "embedded://path/to/" from "embedded://path/to/file.xml")
    pub fn getParentUri(self: *const LoadContext) []const u8 {
        var i: usize = self.uri.len;
        while (i > 0) : (i -= 1) {
            if (self.uri[i - 1] == '/') {
                return self.uri[0..i];
            }
        }
        return self.uri;
    }

    /// Resolve a relative path to a full URI using the parent's scheme
    pub fn resolveRelative(self: *const LoadContext, allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
        const parent_uri = self.getParentUri();
        return std.mem.concat(allocator, u8, &[_][]const u8{ parent_uri, relative_path });
    }

    /// Load a asset of the given type using the same base URI for resolving relative paths
    pub fn loadDependency(self: *const LoadContext, comptime T: type, relative_path: []const u8) !*T {
        const full_uri = try self.resolveRelative(self.allocator, relative_path);
        defer self.allocator.free(full_uri);
        const assets_ptr: *Assets = @ptrCast(@alignCast(self.assets));
        return assets_ptr.loadAssetNow(T, full_uri, null);
    }
};

/// Type-erased loader entry for storage in hash map
const LoaderEntry = struct {
    ptr: *anyopaque,
    load_fn: *const fn (*anyopaque, *const LoadContext, ?*const anyopaque) anyerror!*anyopaque,
    unload_fn: *const fn (*anyopaque, *anyopaque, std.mem.Allocator) void,
    destroy_fn: *const fn (*anyopaque, std.mem.Allocator) void,
};

/// Embedded asset resolver
const EmbeddedResolver = struct {
    pub fn resolve(_: *EmbeddedResolver, allocator: std.mem.Allocator, path: []const u8) !schemes.ResolveResult {
        const embedded_assets = @import("embedded_assets");
        const file = embedded_assets.get(path) orelse return error.AssetNotFound;
        const data = try allocator.dupe(u8, file);
        return schemes.ResolveResult{ .embedded_data = data };
    }
};

/// Main asset management system - simplified and unified
pub const Assets = struct {
    allocator: std.mem.Allocator,
    scheme_registry: schemes.SchemeRegistry,
    loaders: std.AutoHashMap(u64, LoaderEntry),
    /// Cached assets by URI hash
    cache: std.AutoHashMap(AssetHandle, CacheEntry),
    queue_mutex: std.atomic.Mutex,
    queue: std.ArrayList(LoadRequest),
    io: std.Io,
    /// Monotonic counter for handles issued by `insert`.
    /// High bit is set to distinguish from URI-hash-based handles.
    next_handle_id: u64 = 0,

    const CacheEntry = struct {
        ptr: *anyopaque,
        type_hash: u64,
    };

    const LoadRequest = struct {
        handle: AssetHandle,
        type_hash: u64,
        uri: []u8,
        settings_ptr: ?*anyopaque = null,
        destroy_settings_fn: ?*const fn (*anyopaque, std.mem.Allocator) void = null,
    };

    pub fn init(io: std.Io, allocator: std.mem.Allocator) Assets {
        var self = Assets{
            .allocator = allocator,
            .io = io,
            .scheme_registry = schemes.SchemeRegistry.init(allocator),
            .loaders = std.AutoHashMap(AssetHandle, LoaderEntry).init(allocator),
            .cache = std.AutoHashMap(u64, CacheEntry).init(allocator),
            .queue_mutex = .unlocked,
            .queue = std.ArrayList(LoadRequest).empty,
        };

        // Register default schemes
        self.initDefaultSchemes() catch @panic("Failed to register default schemes");

        // Register default loaders
        self.addLoader(rl.Texture, TextureLoader, .{}) catch @panic("Failed to add texture loader");
        self.addLoader(rl.Sound, SoundLoader, .{}) catch @panic("Failed to add sound loader");
        self.addLoader(rl.Music, MusicLoader, .{}) catch @panic("Failed to add music loader");
        self.addLoader(rl.Font, FontLoader, .{}) catch @panic("Failed to add font loader");
        self.addLoader(rl.Shader, ShaderLoader, .{}) catch @panic("Failed to add shader loader");
        self.addLoader(ShaderSource, ShaderSourceLoader, .{}) catch @panic("Failed to add shader source loader");
        self.addLoader(xml.XmlDocument, XmlDocumentLoader, .{}) catch @panic("Failed to add xml loader");
        self.addLoader(types.IconAtlas, IconAtlasLoader, .{}) catch @panic("Failed to add icon atlas loader");

        return self;
    }

    pub fn deinit(self: *Assets) void {
        // Clean up cached assets
        var cache_it = self.cache.iterator();
        while (cache_it.next()) |entry| {
            if (self.loaders.get(entry.value_ptr.type_hash)) |loader| {
                loader.unload_fn(loader.ptr, entry.value_ptr.ptr, self.allocator);
            }
        }
        self.cache.deinit();

        // Destroy all loaders
        var it = self.loaders.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.destroy_fn(entry.value_ptr.ptr, self.allocator);
        }
        self.loaders.deinit();

        self.lockQueue();
        defer self.unlockQueue();
        for (self.queue.items) |*req| {
            self.deinitLoadRequest(req);
        }
        self.queue.deinit(self.allocator);

        self.scheme_registry.deinit();
    }

    fn deinitLoadRequest(self: *Assets, req: *LoadRequest) void {
        self.allocator.free(req.uri);
        if (req.settings_ptr) |settings_ptr| {
            req.destroy_settings_fn.?(settings_ptr, self.allocator);
        }
    }

    fn lockQueue(self: *Assets) void {
        while (!self.queue_mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlockQueue(self: *Assets) void {
        self.queue_mutex.unlock();
    }

    fn initDefaultSchemes(self: *Assets) !void {
        const embedded_resolver_ptr = try self.allocator.create(EmbeddedResolver);
        embedded_resolver_ptr.* = EmbeddedResolver{};
        try self.scheme_registry.registerScheme("embedded", schemes.SchemeResolver.initOwned(embedded_resolver_ptr));
        try self.scheme_registry.registerScheme("embed", schemes.SchemeResolver.initOwned(embedded_resolver_ptr));

        const file_resolver_ptr = try self.allocator.create(schemes.FileResolver);
        file_resolver_ptr.* = schemes.FileResolver{};
        try self.scheme_registry.registerScheme("file", schemes.SchemeResolver.initOwned(file_resolver_ptr));
    }

    /// Add a loader for an asset type.
    ///
    /// The loader must declare `pub const LoadSettings` and implement:
    /// - `load(self: *LoaderType, ctx: *const LoadContext, settings: ?*const LoadSettings) anyerror!AssetType`
    /// - `unload(self: *LoaderType, asset: AssetType) void`
    pub fn addLoader(self: *Assets, comptime AssetType: type, comptime LoaderType: type, loader: LoaderType) error{ LoaderAlreadyExists, OutOfMemory }!void {
        const LoaderTemplate = reflect.Template(struct {
            pub const Name: []const u8 = "AssetsLoader";
            pub const LoadSettings = reflect.TemplateDeclType("LoadSettings");

            pub fn load(_: *@This(), ctx: *const LoadContext, settings: ?*const LoadSettings) anyerror!AssetType {
                _ = ctx;
                _ = settings;
                unreachable;
            }
        });

        const UnloaderTemplate = reflect.Template(struct {
            pub const Name: []const u8 = "AssetsUnloader";

            pub fn unload(_: *@This(), asset: AssetType) void {
                _ = asset;
                unreachable;
            }
        });

        LoaderTemplate.validate(LoaderType);
        UnloaderTemplate.validate(LoaderType);

        const hash = std.hash_map.hashString(@typeName(AssetType));

        if (self.loaders.contains(hash)) return error.LoaderAlreadyExists;

        const loader_ptr = try self.allocator.create(LoaderType);
        loader_ptr.* = loader;

        const Wrapper = struct {
            fn load(ptr: *anyopaque, ctx: *const LoadContext, settings: ?*const anyopaque) anyerror!*anyopaque {
                const self_ptr: *LoaderType = @ptrCast(@alignCast(ptr));
                const typed_settings: ?*const LoaderType.LoadSettings = if (settings) |s|
                    @ptrCast(@alignCast(s))
                else
                    null;
                const asset = try self_ptr.load(ctx, typed_settings);
                const asset_ptr = try ctx.allocator.create(AssetType);
                asset_ptr.* = asset;
                return @ptrCast(asset_ptr);
            }

            fn unload(ptr: *anyopaque, asset_ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self_ptr: *LoaderType = @ptrCast(@alignCast(ptr));
                const typed_asset: *AssetType = @ptrCast(@alignCast(asset_ptr));
                self_ptr.unload(typed_asset.*);
                allocator.destroy(typed_asset);
            }

            fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self_ptr: *LoaderType = @ptrCast(@alignCast(ptr));
                allocator.destroy(self_ptr);
            }
        };

        try self.loaders.put(hash, .{
            .ptr = @ptrCast(loader_ptr),
            .load_fn = Wrapper.load,
            .unload_fn = Wrapper.unload,
            .destroy_fn = Wrapper.destroy,
        });
    }

    /// Check if a loader for the given asset type exists
    pub fn hasLoader(self: *Assets, comptime AssetType: type) bool {
        const hash = std.hash_map.hashString(@typeName(AssetType));
        return self.loaders.contains(hash);
    }

    pub fn amount(self: *const Assets) usize {
        @constCast(self).lockQueue();
        defer @constCast(self).unlockQueue();
        return self.queue.items.len;
    }

    fn performLoad(self: *Assets, handle: AssetHandle, type_hash: u64, uri: []const u8, settings_ptr: ?*const anyopaque) anyerror!*anyopaque {
        if (self.cache.get(handle)) |entry| {
            if (entry.type_hash == type_hash) {
                return entry.ptr;
            }
        }

        const loader = self.loaders.get(type_hash) orelse return error.NoManagerForType;
        const ctx = LoadContext{
            .allocator = self.allocator,
            .uri = uri,
            .scheme_registry = &self.scheme_registry,
            .assets = self,
        };

        const asset_ptr = try loader.load_fn(loader.ptr, &ctx, settings_ptr);
        errdefer loader.unload_fn(loader.ptr, asset_ptr, self.allocator);

        try self.cache.put(handle, .{
            .ptr = asset_ptr,
            .type_hash = type_hash,
        });

        return asset_ptr;
    }

    /// Store an already-created asset value and return a unique handle.
    /// The asset will be unloaded via the registered loader's `unload` callback
    /// when `unload(AssetType, handle)` is called or when `Assets.deinit` runs.
    /// Requires that a loader for `AssetType` has been registered.
    pub fn insert(self: *Assets, comptime AssetType: type, value: AssetType) error{OutOfMemory}!AssetHandle {
        const type_hash = std.hash_map.hashString(@typeName(AssetType));
        self.next_handle_id += 1;
        // High bit set so these handles never collide with URI-derived hashes.
        const handle: AssetHandle = 0x8000_0000_0000_0000 | self.next_handle_id;
        const asset_ptr = try self.allocator.create(AssetType);
        asset_ptr.* = value;
        errdefer self.allocator.destroy(asset_ptr);
        try self.cache.put(handle, .{ .ptr = @ptrCast(asset_ptr), .type_hash = type_hash });
        return handle;
    }

    /// Load an asset synchronously and return a pointer to it.
    ///
    /// If the same asset is already queued via `loadAsset`, the pending request is
    /// removed from the queue and executed immediately using its queued settings.
    pub fn loadAssetNow(self: *Assets, comptime AssetType: type, uri: []const u8, settings: anytype) anyerror!*AssetType {
        const type_hash = std.hash_map.hashString(@typeName(AssetType));

        // Resolve the URI to get consistent cache key
        const resolved_uri = try self.resolveUri(uri);
        defer self.allocator.free(resolved_uri);

        const cache_key = std.hash_map.hashString(resolved_uri);

        // Check cache first
        if (self.cache.get(cache_key)) |entry| {
            if (entry.type_hash == type_hash) {
                return @ptrCast(@alignCast(entry.ptr));
            }
        }

        const queued_req = blk: {
            self.lockQueue();
            defer self.unlockQueue();

            var queue_index: usize = 0;
            while (queue_index < self.queue.items.len) : (queue_index += 1) {
                const req = &self.queue.items[queue_index];
                if (req.handle == cache_key and req.type_hash == type_hash) {
                    break :blk self.queue.swapRemove(queue_index);
                }
            }

            break :blk null;
        };

        if (queued_req) |req| {
            var owned_req = req;
            defer self.deinitLoadRequest(&owned_req);

            const asset_ptr = try self.performLoad(owned_req.handle, owned_req.type_hash, owned_req.uri, if (owned_req.settings_ptr) |ptr| ptr else null);
            return @ptrCast(@alignCast(asset_ptr));
        }

        const settings_ptr: ?*const anyopaque = if (@TypeOf(settings) == @TypeOf(null))
            null
        else
            @ptrCast(&settings);

        const asset_ptr = try self.performLoad(cache_key, type_hash, resolved_uri, settings_ptr);

        return @ptrCast(@alignCast(asset_ptr));
    }

    /// Load an asset and return a handle (for queued loading)
    pub fn loadAsset(self: *Assets, comptime AssetType: type, uri: []const u8, settings: anytype) anyerror!AssetHandle {
        const type_hash = std.hash_map.hashString(@typeName(AssetType));
        const resolved = try self.resolveUri(uri);
        var keep_resolved = false;
        defer if (!keep_resolved) self.allocator.free(resolved);

        const handle = std.hash_map.hashString(resolved);

        if (self.cache.get(handle)) |entry| {
            if (entry.type_hash == type_hash) {
                return handle;
            }
        }

        self.lockQueue();
        for (self.queue.items) |req| {
            if (req.handle == handle and req.type_hash == type_hash) {
                self.unlockQueue();
                return handle;
            }
        }
        self.unlockQueue();

        const settings_storage = blk: {
            if (@TypeOf(settings) == @TypeOf(null)) {
                break :blk .{ .ptr = @as(?*anyopaque, null), .destroy = @as(?*const fn (*anyopaque, std.mem.Allocator) void, null) };
            }

            const SettingsType = @TypeOf(settings);
            if (@typeInfo(SettingsType) == .pointer) {
                @compileError("Assets.loadAsset requires settings to be a value or null because queued requests copy settings into owned storage");
            }

            const settings_ptr = try self.allocator.create(SettingsType);
            settings_ptr.* = settings;

            const DestroySettings = struct {
                fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                    const typed_ptr: *SettingsType = @ptrCast(@alignCast(ptr));
                    allocator.destroy(typed_ptr);
                }
            };

            break :blk .{
                .ptr = @as(?*anyopaque, @ptrCast(settings_ptr)),
                .destroy = @as(?*const fn (*anyopaque, std.mem.Allocator) void, DestroySettings.destroy),
            };
        };
        errdefer if (settings_storage.ptr) |settings_ptr| settings_storage.destroy.?(settings_ptr, self.allocator);

        self.lockQueue();
        defer self.unlockQueue();

        for (self.queue.items) |req| {
            if (req.handle == handle and req.type_hash == type_hash) {
                if (settings_storage.ptr) |settings_ptr| {
                    settings_storage.destroy.?(settings_ptr, self.allocator);
                }
                return handle;
            }
        }

        try self.queue.append(self.allocator, .{
            .handle = handle,
            .type_hash = type_hash,
            .uri = resolved,
            .settings_ptr = settings_storage.ptr,
            .destroy_settings_fn = settings_storage.destroy,
        });

        keep_resolved = true;

        return handle;
    }

    pub fn process(self: *Assets) anyerror!void {
        self.lockQueue();
        const maybe_req = self.queue.pop();
        self.unlockQueue();
        if (maybe_req == null) {
            return;
        }

        var req = maybe_req.?;
        defer self.deinitLoadRequest(&req);

        _ = try self.performLoad(req.handle, req.type_hash, req.uri, if (req.settings_ptr) |ptr| ptr else null);
    }

    pub fn unload(self: *Assets, comptime AssetType: type, handle: AssetHandle) void {
        if (self.cache.get(handle)) |entry| {
            if (entry.type_hash == std.hash_map.hashString(@typeName(AssetType))) {
                if (self.loaders.get(entry.type_hash)) |loader| {
                    loader.unload_fn(loader.ptr, entry.ptr, self.allocator);
                }
                _ = self.cache.remove(handle);
            }
        }
    }

    /// Get a cached asset by handle
    pub fn get(self: *const Assets, comptime AssetType: type, handle: AssetHandle) ?*const AssetType {
        const type_hash = std.hash_map.hashString(@typeName(AssetType));
        if (self.cache.get(handle)) |entry| {
            if (entry.type_hash == type_hash) {
                return @ptrCast(@alignCast(entry.ptr));
            }
        }
        return null;
    }

    /// Resolve URI (handle paths without scheme)
    fn resolveUri(self: *Assets, uri: []const u8) ![]u8 {
        if (uri.len == 0) return error.FileNotFound;

        if (std.mem.indexOf(u8, uri, "://") != null) {
            return self.allocator.dupe(u8, uri);
        }

        if (std.fs.path.isAbsolute(uri)) {
            return self.allocator.dupe(u8, uri);
        }

        const io = self.io;
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", self.allocator);
        defer self.allocator.free(cwd);
        return std.fs.path.join(self.allocator, &[_][]const u8{ cwd, uri });
    }

    // ===== SCHEME MANAGEMENT =====

    pub fn registerScheme(self: *Assets, scheme: []const u8, resolver: schemes.SchemeResolver) !void {
        try self.scheme_registry.registerScheme(scheme, resolver);
    }

    pub fn unregisterScheme(self: *Assets, scheme: []const u8) void {
        self.scheme_registry.unregisterScheme(scheme);
    }

    pub fn hasScheme(self: *Assets, scheme: []const u8) bool {
        return self.scheme_registry.hasScheme(scheme);
    }

    pub fn getSchemes(self: *Assets) ![][]const u8 {
        return self.scheme_registry.getSchemes(self.allocator);
    }

    pub fn resolve(self: *Assets, allocator: std.mem.Allocator, uri: []const u8) anyerror!schemes.ResolveResult {
        return self.scheme_registry.resolve(allocator, uri);
    }

    // ===== CONVENIENCE METHODS =====

    pub fn registerFolderScheme(self: *Assets, scheme: []const u8, base_folder: []const u8) !void {
        const resolver_ptr = try self.allocator.create(schemes.FolderResolver);
        resolver_ptr.* = schemes.FolderResolver.init(base_folder);
        try self.registerScheme(scheme, schemes.SchemeResolver.initOwned(resolver_ptr));
    }

    pub fn registerUrlScheme(self: *Assets, scheme: []const u8, base_url: []const u8) !void {
        const resolver_ptr = try self.allocator.create(schemes.UrlResolver);
        resolver_ptr.* = schemes.UrlResolver.init(base_url);
        try self.registerScheme(scheme, schemes.SchemeResolver.initOwned(resolver_ptr));
    }
};

// ===== BUILT-IN LOADERS =====

pub const TextureLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *TextureLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!rl.Texture {
        // Raylib requires a render device to load fonts, so we must check this before attempting to load
        if (!rl.isWindowReady()) return error.NoRenderDevice;

        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, if (ext.len > 0) ext else ".png", data);
                defer _ = io_utils.deleteFile(temp_path);
                defer ctx.allocator.free(temp_path);

                const path_z = try std.heap.c_allocator.dupeZ(u8, temp_path);
                defer std.heap.c_allocator.free(path_z);
                const tex = try rl.loadTexture(path_z);
                if (!rl.isTextureValid(tex)) return error.InvalidTexture;
                return tex;
            },
            .file_path => |path| {
                // Check file exists before calling raylib
                if (!io_utils.exists(path)) return error.FileNotFound;

                const path_z = try std.heap.c_allocator.dupeZ(u8, path);
                defer std.heap.c_allocator.free(path_z);
                const tex = try rl.loadTexture(path_z);
                if (!rl.isTextureValid(tex)) return error.InvalidTexture;
                return tex;
            },
            else => return error.UnsupportedScheme,
        }
    }

    pub fn unload(_: *TextureLoader, texture: rl.Texture) void {
        rl.unloadTexture(texture);
    }
};

pub const SoundLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *SoundLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!rl.Sound {
        // Raylib requires an audio device to load sounds, so we must check this before attempting to load
        if (!rl.isAudioDeviceReady()) return error.NoAudioDevice;

        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, if (ext.len > 0) ext else ".wav", data);
                defer ctx.allocator.free(temp_path);

                const path_z = try std.heap.c_allocator.dupeZ(u8, temp_path);
                defer std.heap.c_allocator.free(path_z);
                const sound = try rl.loadSound(path_z);
                if (!rl.isSoundValid(sound)) return error.InvalidSound;
                return sound;
            },
            .file_path => |path| {
                const path_z = try std.heap.c_allocator.dupeZ(u8, path);
                defer std.heap.c_allocator.free(path_z);
                const sound = try rl.loadSound(path_z);
                if (!rl.isSoundValid(sound)) return error.InvalidSound;
                return sound;
            },
            else => return error.UnsupportedScheme,
        }
    }

    pub fn unload(_: *SoundLoader, sound: rl.Sound) void {
        rl.unloadSound(sound);
    }
};

pub const MusicLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *MusicLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!rl.Music {
        // Raylib requires an audio device to load music, so we must check this before attempting to load
        if (!rl.isAudioDeviceReady()) return error.NoAudioDevice;

        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, if (ext.len > 0) ext else ".mp3", data);
                defer ctx.allocator.free(temp_path);

                const path_z = try std.heap.c_allocator.dupeZ(u8, temp_path);
                defer std.heap.c_allocator.free(path_z);
                const music = try rl.loadMusicStream(path_z);
                if (!rl.isMusicValid(music)) return error.InvalidMusic;
                return music;
            },
            .file_path => |path| {
                const path_z = try std.heap.c_allocator.dupeZ(u8, path);
                defer std.heap.c_allocator.free(path_z);
                const music = try rl.loadMusicStream(path_z);
                if (!rl.isMusicValid(music)) return error.InvalidMusic;
                return music;
            },
            else => return error.UnsupportedScheme,
        }
    }

    pub fn unload(_: *MusicLoader, music: rl.Music) void {
        rl.unloadMusicStream(music);
    }
};

pub const FontLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *FontLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!rl.Font {
        // Raylib requires a render device to load fonts, so we must check this before attempting to load
        if (!rl.isWindowReady()) return error.NoRenderDevice;

        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, if (ext.len > 0) ext else ".ttf", data);
                defer ctx.allocator.free(temp_path);

                const path_z = try std.heap.c_allocator.dupeZ(u8, temp_path);
                defer std.heap.c_allocator.free(path_z);
                const font = try rl.loadFont(path_z);
                if (!rl.isFontValid(font)) return error.InvalidFont;
                return font;
            },
            .file_path => |path| {
                const path_z = try std.heap.c_allocator.dupeZ(u8, path);
                defer std.heap.c_allocator.free(path_z);
                const font = try rl.loadFont(path_z);
                if (!rl.isFontValid(font)) return error.InvalidFont;
                return font;
            },
            else => return error.UnsupportedScheme,
        }
    }

    pub fn unload(_: *FontLoader, font: rl.Font) void {
        rl.unloadFont(font);
    }
};

pub const ShaderLoader = struct {
    pub const Stage = enum(u32) { frag, vert };

    /// Identifies which shader stage the URI points to.
    /// Use the shorthands `LoadSettings.frag` or `LoadSettings.vert`.
    pub const LoadSettings = struct {
        stage: Stage,
        /// Fragment shader — vertex defaults to raylib's built-in.
        pub const frag: LoadSettings = .{ .stage = .frag };
        /// Vertex shader — fragment defaults to raylib's built-in.
        pub const vert: LoadSettings = .{ .stage = .vert };
    };

    pub fn load(_: *ShaderLoader, ctx: *const LoadContext, settings: ?*const LoadSettings) anyerror!rl.Shader {
        const allocator = ctx.allocator;
        if (!rl.isWindowReady()) return error.NoRenderDevice;
        const stage = if (settings) |s| s.stage else return error.ShaderLoaderSettingsRequired;

        var resolved = try ctx.scheme_registry.resolve(allocator, ctx.uri);
        defer resolved.deinit(allocator);
        const source_z = try stageSource(allocator, resolved);
        defer allocator.free(source_z);

        return switch (stage) {
            .frag => rl.loadShaderFromMemory(null, source_z),
            .vert => rl.loadShaderFromMemory(source_z, null),
        };
    }

    /// Resolve a shader stage to its null-terminated GLSL source string (caller frees).
    /// For file paths, reads via std.Io.File. For embedded/raw, duplicates bytes directly.
    fn stageSource(allocator: std.mem.Allocator, resolved: schemes.ResolveResult) anyerror![:0]u8 {
        return switch (resolved) {
            .file_path => |path| blk: {
                const dir_path = std.fs.path.dirname(path) orelse ".";
                const base_name = std.fs.path.basename(path);
                var threaded = std.Io.Threaded.init_single_threaded;
                const io = threaded.io();
                var dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{});
                defer dir.close(io);
                var file = try dir.openFile(io, base_name, .{});
                defer file.close(io);
                var buf: [4096]u8 = undefined;
                var reader = file.reader(io, &buf);
                const data = try reader.interface.allocRemaining(allocator, .limited(50 * 1024 * 1024));
                defer allocator.free(data);
                break :blk try allocator.dupeZ(u8, data);
            },
            .embedded_data => |data| try allocator.dupeZ(u8, data),
            .raw => |data| try allocator.dupeZ(u8, data),
            else => error.UnsupportedScheme,
        };
    }

    pub fn unload(_: *ShaderLoader, shader: rl.Shader) void {
        rl.unloadShader(shader);
    }
};

/// Raw shader source text loaded from a file or embedded asset.
/// Use `ShaderSourceLoader` with the Assets system to load these.
pub const ShaderSource = struct {
    source: [:0]u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ShaderSource) void {
        self.allocator.free(self.source);
    }
};

/// Asset loader for raw shader source text files (GLSL, HLSL, etc.).
/// Register with Assets before loading shader sources:
///   try assets.addLoader(ShaderSource, ShaderSourceLoader, .{});
/// Then queue individual vertex or fragment sources via:
///   const handle = try assets.loadAsset(ShaderSource, "file://shaders/my.frag.glsl", null);
///   try assets.process();
pub const ShaderSourceLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *ShaderSourceLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!ShaderSource {
        if (!rl.isWindowReady()) return error.NoRenderDevice;

        const data = try ctx.readData();
        defer ctx.allocator.free(data);

        const source = try ctx.allocator.dupeZ(u8, data);
        return ShaderSource{
            .source = source,
            .allocator = ctx.allocator,
        };
    }

    pub fn unload(_: *ShaderSourceLoader, source: ShaderSource) void {
        var s = source;
        s.deinit();
    }
};

pub const XmlDocumentLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *XmlDocumentLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!xml.XmlDocument {
        const data = try ctx.readData();
        return xml.XmlDocument.initFromSlice(ctx.allocator, data, .{});
    }

    pub fn unload(_: *XmlDocumentLoader, doc: xml.XmlDocument) void {
        var d = doc;
        d.deinit();
    }
};

pub const IconAtlasLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: *IconAtlasLoader, ctx: *const LoadContext, _: ?*const LoadSettings) anyerror!types.IconAtlas {
        // Raylib requires a render device to load fonts, so we must check this before attempting to load
        if (!rl.isWindowReady()) {
            return error.NoRenderDevice;
        }

        // Read and parse XML data
        const data = try ctx.readData();
        var doc = try xml.XmlDocument.initFromSlice(ctx.allocator, data, .{});
        defer doc.deinit();

        const parsed = try icons_parser.parseTextureAtlas(&doc, ctx.allocator);
        const rel_image_path = parsed.image_path orelse return error.MissingImagePath;
        defer ctx.allocator.free(rel_image_path);

        // Load texture using relative path resolution - KEY FIX!
        // ctx.loadRelated uses the parent URI's scheme
        const texture = try ctx.loadDependency(rl.Texture, rel_image_path);

        // Build IconAtlas and populate mappings
        var atlas = types.IconAtlas.init(ctx.allocator, texture, parsed.frames, false);
        try atlas.populateKeyboardMappings();
        return atlas;
    }

    pub fn unload(_: *IconAtlasLoader, atlas: types.IconAtlas) void {
        var a = atlas;
        a.deinit();
    }
};

// ===== TESTS =====

test "Assets manager operations" {
    const testing = std.testing;
    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();
    try testing.expect(assets.hasLoader(rl.Texture));
}

test "Assets load embedded texture" {
    const testing = std.testing;
    const embedded_assets = @import("embedded_assets");
    if (should_skip) {
        return error.SkipZigTest;
    }
    if (embedded_assets.list().len == 0) return error.SkipZigTest;

    rl.initWindow(800, 600, "Test");
    defer rl.closeWindow();

    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();

    const tex = try assets.loadAssetNow(rl.Texture, "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.png", null);
    try testing.expect(rl.isTextureValid(tex.*));
}

test "Assets load embedded IconAtlas" {
    const testing = std.testing;
    const embedded_assets = @import("embedded_assets");
    if (should_skip) {
        return error.SkipZigTest;
    }
    if (embedded_assets.list().len == 0) return error.SkipZigTest;

    rl.initWindow(800, 600, "Test");
    defer rl.closeWindow();

    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();

    const atlas = try assets.loadAssetNow(types.IconAtlas, "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml", null);
    try testing.expect(atlas.frameCount() > 0);
    try testing.expect(rl.isTextureValid(atlas.texture.*));
}

test "Assets default schemes" {
    const testing = std.testing;
    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();
    try testing.expect(assets.hasScheme("embedded"));
    try testing.expect(assets.hasScheme("file"));
}

test "Assets custom scheme registration" {
    const testing = std.testing;
    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();

    try assets.registerFolderScheme("assets", "game_assets");
    try testing.expect(assets.hasScheme("assets"));

    assets.unregisterScheme("assets");
    try testing.expect(!assets.hasScheme("assets"));
}

test "Assets file not found" {
    const testing = std.testing;
    if (should_skip) {
        return error.SkipZigTest;
    }

    // Need raylib window for texture loading, but file check happens first
    rl.initWindow(320, 240, "Test");
    defer rl.closeWindow();

    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();

    const result = assets.loadAssetNow(rl.Texture, "nonexistent.png", null);
    try testing.expectError(error.FileNotFound, result);
}

test "Assets unknown scheme" {
    const testing = std.testing;
    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();

    const result = assets.scheme_registry.resolve(testing.allocator, "unknown://file.txt");
    try testing.expectError(error.UnknownScheme, result);
}

test "Assets queued load waits for process" {
    const testing = std.testing;

    const TestAsset = struct {
        value: usize,
    };

    const TestLoader = struct {
        pub const LoadSettings = struct {
            multiplier: usize = 1,
        };

        pub fn load(_: *@This(), ctx: *const LoadContext, settings: ?*const LoadSettings) anyerror!TestAsset {
            return .{
                .value = ctx.uri.len * if (settings) |s| s.multiplier else 1,
            };
        }

        pub fn unload(_: *@This(), asset: TestAsset) void {
            _ = asset;
        }
    };

    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();
    try assets.addLoader(TestAsset, TestLoader, .{});

    const settings = TestLoader.LoadSettings{ .multiplier = 2 };
    const handle = try assets.loadAsset(TestAsset, "embedded://queued.asset", settings);

    try testing.expectEqual(@as(usize, 1), assets.amount());
    try testing.expect(assets.get(TestAsset, handle) == null);

    try assets.process();

    try testing.expectEqual(@as(usize, 0), assets.amount());
    const asset = assets.get(TestAsset, handle) orelse return error.TestUnexpectedResult;
    try testing.expectEqual("embedded://queued.asset".len * settings.multiplier, asset.value);
}

test "Assets loadAssetNow consumes matching queued request" {
    const testing = std.testing;

    const TestAsset = struct {
        value: usize,
    };

    const TestLoader = struct {
        pub const LoadSettings = struct {
            multiplier: usize = 1,
        };

        pub fn load(_: *@This(), ctx: *const LoadContext, settings: ?*const LoadSettings) anyerror!TestAsset {
            return .{
                .value = ctx.uri.len * if (settings) |s| s.multiplier else 1,
            };
        }

        pub fn unload(_: *@This(), asset: TestAsset) void {
            _ = asset;
        }
    };

    var assets = Assets.init(testing.io, testing.allocator);
    defer assets.deinit();
    try assets.addLoader(TestAsset, TestLoader, .{});

    const queued_settings = TestLoader.LoadSettings{ .multiplier = 3 };
    const handle = try assets.loadAsset(TestAsset, "embedded://queued-now.asset", queued_settings);

    try testing.expectEqual(@as(usize, 1), assets.amount());

    const asset = try assets.loadAssetNow(TestAsset, "embedded://queued-now.asset", null);

    try testing.expectEqual(@as(usize, 0), assets.amount());
    try testing.expectEqual("embedded://queued-now.asset".len * queued_settings.multiplier, asset.value);
    try testing.expectEqual(asset, assets.get(TestAsset, handle).?);
}
