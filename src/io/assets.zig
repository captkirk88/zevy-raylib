const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const io_utils = @import("util.zig");
const schemes = @import("scheme_resolver.zig");
const types = @import("types.zig");
const xml = @import("xml.zig");
const icons_parser = @import("../input/icons_parser.zig");

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
                const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
                    if (err == error.FileNotFound) return error.FileNotFound;
                    return err;
                };
                defer file.close();
                return file.readToEndAlloc(self.allocator, 50 * 1024 * 1024); // 50MB limit
            },
            .url => |_| {
                result.deinit(self.allocator);
                return error.UrlNotSupported;
            },
            .custom => |_| {
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

    /// Load a related asset (e.g., texture referenced by atlas)
    pub fn loadRelated(self: *const LoadContext, comptime T: type, relative_path: []const u8) !*T {
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
    cache: std.AutoHashMap(u64, CacheEntry),

    const CacheEntry = struct {
        ptr: *anyopaque,
        type_hash: u64,
    };

    pub fn init(allocator: std.mem.Allocator) Assets {
        var self = Assets{
            .allocator = allocator,
            .scheme_registry = schemes.SchemeRegistry.init(allocator),
            .loaders = std.AutoHashMap(u64, LoaderEntry).init(allocator),
            .cache = std.AutoHashMap(u64, CacheEntry).init(allocator),
        };

        // Register default schemes
        self.initDefaultSchemes() catch @panic("Failed to register default schemes");

        // Register default loaders
        self.addLoader(rl.Texture, TextureLoader{}) catch @panic("Failed to add texture loader");
        self.addLoader(rl.Sound, SoundLoader{}) catch @panic("Failed to add sound loader");
        self.addLoader(rl.Music, MusicLoader{}) catch @panic("Failed to add music loader");
        self.addLoader(rl.Font, FontLoader{}) catch @panic("Failed to add font loader");
        self.addLoader(rl.Shader, ShaderLoader{}) catch @panic("Failed to add shader loader");
        self.addLoader(xml.XmlDocument, XmlDocumentLoader{}) catch @panic("Failed to add xml loader");
        self.addLoader(types.IconAtlas, IconAtlasLoader{}) catch @panic("Failed to add icon atlas loader");

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

        self.scheme_registry.deinit();
    }

    fn initDefaultSchemes(self: *Assets) !void {
        const embedded_resolver_ptr = try self.allocator.create(EmbeddedResolver);
        embedded_resolver_ptr.* = EmbeddedResolver{};
        try self.scheme_registry.registerScheme("embedded", schemes.SchemeResolver.initOwned(embedded_resolver_ptr));

        const file_resolver_ptr = try self.allocator.create(schemes.FileResolver);
        file_resolver_ptr.* = schemes.FileResolver{};
        try self.scheme_registry.registerScheme("file", schemes.SchemeResolver.initOwned(file_resolver_ptr));
    }

    /// Add a loader for an asset type
    pub fn addLoader(self: *Assets, comptime AssetType: type, loader: anytype) error{ ManagerAlreadyExists, OutOfMemory }!void {
        const LoaderType = @TypeOf(loader);
        const hash = std.hash_map.hashString(@typeName(AssetType));

        if (self.loaders.contains(hash)) return error.ManagerAlreadyExists;

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

    /// Load an asset synchronously and return a pointer to it
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

        const loader = self.loaders.get(type_hash) orelse return error.NoManagerForType;

        const ctx = LoadContext{
            .allocator = self.allocator,
            .uri = resolved_uri,
            .scheme_registry = &self.scheme_registry,
            .assets = self,
        };

        const settings_ptr: ?*const anyopaque = if (@TypeOf(settings) == @TypeOf(null))
            null
        else
            @ptrCast(&settings);

        const asset_ptr = try loader.load_fn(loader.ptr, &ctx, settings_ptr);

        try self.cache.put(cache_key, .{
            .ptr = asset_ptr,
            .type_hash = type_hash,
        });

        return @ptrCast(@alignCast(asset_ptr));
    }

    /// Load an asset and return a handle (for queued loading)
    pub fn loadAsset(self: *Assets, comptime AssetType: type, uri: []const u8, settings: anytype) anyerror!AssetHandle {
        _ = try self.loadAssetNow(AssetType, uri, settings);
        const resolved = try self.resolveUri(uri);
        defer self.allocator.free(resolved);
        return std.hash_map.hashString(resolved);
    }

    /// Get a cached asset by handle
    pub fn get(self: *Assets, comptime AssetType: type, handle: AssetHandle) ?*const AssetType {
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

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);
        return std.fs.path.join(self.allocator, &[_][]const u8{ cwd, uri });
    }

    /// Process queued loads (no-op in simplified version)
    pub fn process(self: *Assets) !void {
        _ = self;
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
        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, "", if (ext.len > 0) ext else ".png", data);
                defer ctx.allocator.free(temp_path);

                const path_z = try std.heap.c_allocator.dupeZ(u8, temp_path);
                defer std.heap.c_allocator.free(path_z);
                const tex = try rl.loadTexture(path_z);
                if (!rl.isTextureValid(tex)) return error.InvalidTexture;
                return tex;
            },
            .file_path => |path| {
                // Check file exists before calling raylib
                std.fs.accessAbsolute(path, .{}) catch return error.FileNotFound;

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
        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, "", if (ext.len > 0) ext else ".wav", data);
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
        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, "", if (ext.len > 0) ext else ".mp3", data);
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
        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        switch (resolved) {
            .embedded_data => |data| {
                const ext = std.fs.path.extension(ctx.uri);
                const temp_path = try io_utils.writeTempFile(ctx.allocator, "", if (ext.len > 0) ext else ".ttf", data);
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
    pub const LoadSettings = struct {
        frag: ?[]const u8 = null,
    };

    pub fn load(_: *ShaderLoader, ctx: *const LoadContext, settings: ?*const LoadSettings) anyerror!rl.Shader {
        var resolved = try ctx.scheme_registry.resolve(ctx.allocator, ctx.uri);
        defer resolved.deinit(ctx.allocator);

        const vertex_path = switch (resolved) {
            .embedded_data => |data| blk: {
                const ext = std.fs.path.extension(ctx.uri);
                break :blk try io_utils.writeTempFile(ctx.allocator, "", if (ext.len > 0) ext else ".vs", data);
            },
            .file_path => |path| try ctx.allocator.dupe(u8, path),
            else => return error.UnsupportedScheme,
        };
        defer ctx.allocator.free(vertex_path);

        const frag_path = if (settings) |s| blk: {
            if (s.frag) |frag| {
                const frag_uri = try ctx.resolveRelative(ctx.allocator, frag);
                defer ctx.allocator.free(frag_uri);
                var frag_resolved = try ctx.scheme_registry.resolve(ctx.allocator, frag_uri);
                defer frag_resolved.deinit(ctx.allocator);
                break :blk switch (frag_resolved) {
                    .embedded_data => |data| try io_utils.writeTempFile(ctx.allocator, "", ".fs", data),
                    .file_path => |path| try ctx.allocator.dupe(u8, path),
                    else => return error.UnsupportedScheme,
                };
            }
            break :blk try deriveFragPath(ctx.allocator, vertex_path);
        } else try deriveFragPath(ctx.allocator, vertex_path);
        defer ctx.allocator.free(frag_path);

        const vs_z = try std.heap.c_allocator.dupeZ(u8, vertex_path);
        defer std.heap.c_allocator.free(vs_z);
        const fs_z = try std.heap.c_allocator.dupeZ(u8, frag_path);
        defer std.heap.c_allocator.free(fs_z);

        const shader = try rl.loadShader(vs_z, fs_z);
        if (!rl.isShaderValid(shader)) return error.InvalidShader;
        return shader;
    }

    fn deriveFragPath(allocator: std.mem.Allocator, vertex_path: []const u8) ![]u8 {
        const base = std.fs.path.stem(vertex_path);
        const dir = std.fs.path.dirname(vertex_path) orelse ".";
        const frag_name = try std.mem.concat(allocator, u8, &[_][]const u8{ base, ".fs" });
        defer allocator.free(frag_name);
        return std.fs.path.join(allocator, &[_][]const u8{ dir, frag_name });
    }

    pub fn unload(_: *ShaderLoader, shader: rl.Shader) void {
        rl.unloadShader(shader);
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
        // Read and parse XML data
        const data = try ctx.readData();
        var doc = try xml.XmlDocument.initFromSlice(ctx.allocator, data, .{});
        defer doc.deinit();

        const parsed = try icons_parser.parseTextureAtlas(&doc, ctx.allocator);
        const rel_image_path = parsed.image_path orelse return error.MissingImagePath;
        defer ctx.allocator.free(rel_image_path);

        // Load texture using relative path resolution - KEY FIX!
        // ctx.loadRelated uses the parent URI's scheme
        const texture = try ctx.loadRelated(rl.Texture, rel_image_path);

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
    var assets = Assets.init(testing.allocator);
    defer assets.deinit();
    try testing.expect(assets.hasLoader(rl.Texture));
}

test "Assets load embedded texture" {
    const testing = std.testing;
    const embedded_assets = @import("embedded_assets");
    if (embedded_assets.list().len == 0) return error.SkipZigTest;

    var assets = Assets.init(testing.allocator);
    defer assets.deinit();

    rl.initWindow(800, 600, "Test");
    defer rl.closeWindow();

    const tex = try assets.loadAssetNow(rl.Texture, "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.png", null);
    try testing.expect(rl.isTextureValid(tex.*));
}

test "Assets load embedded IconAtlas" {
    const testing = std.testing;
    const embedded_assets = @import("embedded_assets");
    if (embedded_assets.list().len == 0) return error.SkipZigTest;

    var assets = Assets.init(testing.allocator);
    defer assets.deinit();

    rl.initWindow(800, 600, "Test");
    defer rl.closeWindow();

    const atlas = try assets.loadAssetNow(types.IconAtlas, "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml", null);
    try testing.expect(atlas.frameCount() > 0);
    try testing.expect(rl.isTextureValid(atlas.texture.*));
}

test "Assets default schemes" {
    const testing = std.testing;
    var assets = Assets.init(testing.allocator);
    defer assets.deinit();
    try testing.expect(assets.hasScheme("embedded"));
    try testing.expect(assets.hasScheme("file"));
}

test "Assets custom scheme registration" {
    const testing = std.testing;
    var assets = Assets.init(testing.allocator);
    defer assets.deinit();

    try assets.registerFolderScheme("assets", "game_assets");
    try testing.expect(assets.hasScheme("assets"));

    assets.unregisterScheme("assets");
    try testing.expect(!assets.hasScheme("assets"));
}

test "Assets file not found" {
    const testing = std.testing;
    var assets = Assets.init(testing.allocator);
    defer assets.deinit();

    // Need raylib window for texture loading, but file check happens first
    rl.initWindow(320, 240, "Test");
    defer rl.closeWindow();

    const result = assets.loadAssetNow(rl.Texture, "nonexistent.png", null);
    try testing.expectError(error.FileNotFound, result);
}

test "Assets unknown scheme" {
    const testing = std.testing;
    var assets = Assets.init(testing.allocator);
    defer assets.deinit();

    const result = assets.loadAssetNow(rl.Texture, "unknown://test.png", null);
    try testing.expectError(error.UnknownScheme, result);
}

test "Assets process no-op" {
    const testing = std.testing;
    var assets = Assets.init(testing.allocator);
    defer assets.deinit();
    try assets.process();
}
