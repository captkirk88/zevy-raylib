const std = @import("std");
const rlb = @import("raylib-backend");
const rl = @import("raylib-backend").c;

/// File resolver for complex loaders that need to load multiple related files
pub const FileResolver = struct {
    /// Absolute base directory path
    base_dir: []const u8,

    /// Original URI that was resolved to reach this file (e.g., "embedded://path/to/file.xml")
    /// Optional - may be null for regular file paths
    original_uri: ?[]const u8 = null,

    /// Resolve a relative path to an absolute path within the base directory
    resolve_path: *const fn (self: *const FileResolver, allocator: std.mem.Allocator, relative_path: []const u8) std.mem.Allocator.Error![]u8,

    /// Check if a relative path exists within the base directory
    path_exists: *const fn (self: *const FileResolver, relative_path: []const u8) bool,
    /// Pointer to the Loaders registry so a loader can request other
    /// asset types (via a small, typed API) without importing concrete managers.
    loaders: *Loaders,
};

/// AssetLoader wrapper type: validates that a loader implements the required interface
/// and provides a unified interface for loading assets.
///
/// Required loader methods:
///   - load(self: LoaderType, absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const LoadSettings) anyerror!AssetType
///   - extensions() []const []const u8
///   - LoadSettings: type (must be declared)
pub fn AssetLoader(comptime AssetType: type) type {
    return struct {
        loadFn: *const fn ([]const u8, ?*const FileResolver, ?*const anyopaque) anyerror!AssetType,
        extensionsFn: *const fn () []const []const u8,

        const Self = @This();

        pub fn init(comptime LoaderType: type, loader: LoaderType) Self {
            // Compile-time validation
            comptime {
                if (!@hasDecl(LoaderType, "LoadSettings")) {
                    @compileError("Loader must have a LoadSettings declaration: " ++ @typeName(LoaderType));
                }
                if (!@hasDecl(LoaderType, "load")) {
                    @compileError("Loader must have a load method: " ++ @typeName(LoaderType));
                }
                if (!@hasDecl(LoaderType, "extensions")) {
                    @compileError("Loader must have an extensions method: " ++ @typeName(LoaderType));
                }
            }

            const LoaderWrapper = struct {
                var instance: LoaderType = loader;

                fn loadWrapper(absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const anyopaque) anyerror!AssetType {
                    const typed_settings: ?*const LoaderType.LoadSettings = if (settings) |s| @ptrCast(@alignCast(s)) else null;
                    return try instance.load(absolute_path, file_resolver, typed_settings);
                }

                fn extensionsWrapper() []const []const u8 {
                    return LoaderType.extensions();
                }
            };

            return .{
                .loadFn = LoaderWrapper.loadWrapper,
                .extensionsFn = LoaderWrapper.extensionsWrapper,
            };
        }

        pub fn load(self: Self, absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const anyopaque) anyerror!AssetType {
            return try self.loadFn(absolute_path, file_resolver, settings);
        }

        pub fn extensions(self: Self) []const []const u8 {
            return self.extensionsFn();
        }
    };
}

/// AssetUnloader wrapper type: validates that an unloader implements the required interface
/// and provides a unified interface for unloading assets.
///
/// Required unloader methods:
///   - unload(self: UnloaderType, asset: AssetType) void
pub fn AssetUnloader(comptime AssetType: type) type {
    return struct {
        unloadFn: *const fn (AssetType) void,

        const Self = @This();

        pub fn init(comptime UnloaderType: type, unloader: UnloaderType) Self {
            // Compile-time validation
            comptime {
                if (!@hasDecl(UnloaderType, "unload")) {
                    @compileError("Unloader must have an unload method: " ++ @typeName(UnloaderType));
                }
            }

            const UnloaderWrapper = struct {
                var instance: UnloaderType = unloader;

                fn unloadWrapper(asset: AssetType) void {
                    instance.unload(asset);
                }
            };

            return .{
                .unloadFn = UnloaderWrapper.unloadWrapper,
            };
        }

        // TODO make AssetType a pointer to allow unloading of large structs without copying
        pub fn unload(self: Self, asset: AssetType) void {
            self.unloadFn(asset);
        }
    };
}

/// Runtime registry for exposing manager entry views to loaders.
pub const Loaders = struct {
    pub const ManagerView = struct {
        ptr: *anyopaque,
        // Lifecycle / control callbacks
        deinit_fn: ?*const fn (*anyopaque) void,
        process_fn: *const fn (*anyopaque) anyerror!void,
        destroy_fn: ?*const fn (*anyopaque, std.mem.Allocator) void,

        // Public access/load callbacks
        get_fn: *const fn (*anyopaque, usize) ?*anyopaque,
        load_asset_fn: *const fn (*anyopaque, []const u8, ?*anyopaque) anyerror!usize,
        load_asset_now_fn: *const fn (*anyopaque, []const u8, ?*anyopaque) anyerror!*anyopaque,
    };

    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u64, ManagerView),

    pub fn init(allocator: std.mem.Allocator) anyerror!Loaders {
        return Loaders{
            .allocator = allocator,
            .map = std.AutoHashMap(u64, ManagerView).init(allocator),
        };
    }

    pub fn deinit(self: *Loaders) void {
        self.map.deinit();
    }

    pub fn register(self: *Loaders, hash: u64, view: ManagerView) error{OutOfMemory}!void {
        try self.map.putNoClobber(hash, view);
    }

    pub fn unregister(self: *Loaders, hash: u64) void {
        _ = self.map.remove(hash);
    }

    pub fn load(self: *Loaders, comptime AssetType: type, path: []const u8) anyerror!usize {
        const hash = std.hash_map.hashString(@typeName(AssetType));
        if (self.map.get(hash)) |view| {
            const handle = try view.load_asset_fn(view.ptr, path, null);
            return handle;
        }
        return error.NoManagerForType;
    }

    pub fn loadNow(self: *Loaders, comptime AssetType: type, path: []const u8) anyerror!AssetType {
        const hash = std.hash_map.hashString(@typeName(AssetType));
        if (self.map.get(hash)) |view| {
            const res = try view.load_asset_now_fn(view.ptr, path, null);
            return @as(*AssetType, @ptrCast(@alignCast(res))).*;
        }
        return error.NoManagerForType;
    }
};
