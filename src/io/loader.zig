const std = @import("std");
const reflect = @import("zevy_reflect");
const schemes = @import("scheme_resolver.zig");

/// File resolver for complex loaders that need to load multiple related files
pub const FileResolver = struct {
    /// Absolute base directory path (used for filesystem-based resolution)
    base_dir: []const u8,

    /// Original URI that was resolved to reach this file (e.g., "embedded://path/to/file.xml")
    /// When set, relative paths are resolved using the scheme registry instead of filesystem
    original_uri: ?[]const u8 = null,

    /// Scheme registry for resolving scheme-based URIs (optional, needed for embedded/custom schemes)
    scheme_registry: ?*schemes.SchemeRegistry = null,

    /// Resolve a relative path to an absolute path within the base directory
    resolve_path: ?*const fn (self: *const FileResolver, allocator: std.mem.Allocator, relative_path: []const u8) std.mem.Allocator.Error![]u8 = null,

    /// Check if a relative path exists within the base directory
    path_exists: ?*const fn (self: *const FileResolver, relative_path: []const u8) bool = null,
    /// Resolve a relative path, using scheme registry if original_uri has a scheme
    /// Returns the resolved path/URI that can be passed back into the active loader.
    pub fn resolveRelative(self: *const FileResolver, allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
        // If we have an original URI with a scheme, resolve relative to that
        if (self.original_uri) |uri| {
            if (std.mem.indexOf(u8, uri, "://")) |scheme_end| {
                // Find the directory portion of the URI
                var last_slash: usize = uri.len;
                while (last_slash > scheme_end + 3) : (last_slash -= 1) {
                    if (uri[last_slash - 1] == '/') break;
                }
                // Construct new URI: scheme://base_dir/relative_path
                const base_uri = uri[0..last_slash];
                return std.mem.concat(allocator, u8, &[_][]const u8{ base_uri, relative_path });
            }
        }
        // Fall back to filesystem-based resolution
        if (self.resolve_path) |resolve_path_fn| {
            return resolve_path_fn(self, allocator, relative_path);
        } else {
            return error.PathResolutionNotSupported;
        }
    }

    /// Check if a relative path exists, using scheme registry if original_uri has a scheme
    pub fn existsRelative(self: *const FileResolver, allocator: std.mem.Allocator, relative_path: []const u8) bool {
        // If we have an original URI with a scheme and a scheme registry, check via registry
        if (self.original_uri) |uri| {
            if (self.scheme_registry) |registry| {
                if (std.mem.indexOf(u8, uri, "://")) |scheme_end| {
                    // Find the directory portion of the URI
                    var last_slash: usize = uri.len;
                    while (last_slash > scheme_end + 3) : (last_slash -= 1) {
                        if (uri[last_slash - 1] == '/') break;
                    }
                    // Construct new URI: scheme://base_dir/relative_path
                    const base_uri = uri[0..last_slash];
                    const full_uri = std.mem.concat(allocator, u8, &[_][]const u8{ base_uri, relative_path }) catch return false;
                    defer allocator.free(full_uri);

                    // Try to resolve - if it succeeds, the resource exists
                    var result = registry.resolve(allocator, full_uri) catch return false;
                    result.deinit(allocator);
                    return true;
                }
            }
        }
        // Fall back to filesystem-based check
        if (self.path_exists) |path_exists_fn| {
            return path_exists_fn(self, relative_path);
        } else {
            return false;
        }
    }
};

pub fn AssetLoaderTemplate(comptime AssetType: type) type {
    return reflect.Template(struct {
        pub const Name: []const u8 = "AssetLoader";
        pub const LoadSettings = reflect.TemplateDeclType("LoadSettings");

        pub fn load(_: *@This(), absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const LoadSettings) anyerror!AssetType {
            _ = absolute_path;
            _ = file_resolver;
            _ = settings;
            unreachable;
        }

        pub fn extensions() []const []const u8 {
            unreachable;
        }
    });
}

pub fn AssetLoader(comptime LoaderType: type, comptime AssetType: type) type {
    return AssetLoaderTemplate(AssetType).InterfaceFor(LoaderType);
}

pub fn AssetUnloaderTemplate(comptime AssetType: type) type {
    return reflect.Template(struct {
        pub const Name: []const u8 = "AssetUnloader";

        pub fn unload(_: *@This(), asset: AssetType) void {
            _ = asset;
            unreachable;
        }
    });
}

pub fn AssetUnloader(comptime AssetType: type) type {
    return AssetUnloaderTemplate(AssetType).Interface;
}

pub fn AssetSaverTemplate(comptime AssetType: type) type {
    return reflect.Template(struct {
        pub const Name: []const u8 = "AssetSaver";
        pub const SaveSettings = reflect.TemplateDeclType("SaveSettings");

        pub fn save(_: *@This(), asset: *const AssetType, absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const SaveSettings) anyerror!void {
            _ = asset;
            _ = absolute_path;
            _ = file_resolver;
            _ = settings;
            unreachable;
        }
    });
}

pub fn AssetSaver(comptime SaverType: type, comptime AssetType: type) type {
    return AssetSaverTemplate(AssetType).InterfaceFor(SaverType);
}

test "AssetLoader and AssetUnloader validate template contracts" {
    const TestAsset = usize;

    const TestLoader = struct {
        pub const LoadSettings = struct {
            scale: usize = 1,
        };

        pub fn load(_: *@This(), absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const LoadSettings) anyerror!TestAsset {
            _ = file_resolver;
            return absolute_path.len * if (settings) |s| s.scale else 1;
        }

        pub fn extensions() []const []const u8 {
            return &[_][]const u8{".txt"};
        }

        pub fn unload(_: *@This(), asset: TestAsset) void {
            _ = asset;
        }
    };

    const LoaderTemplate = AssetLoaderTemplate(TestAsset);
    const UnloaderTemplate = AssetUnloaderTemplate(TestAsset);
    const LoaderInterface = AssetLoader(TestLoader, TestAsset);
    LoaderTemplate.validate(TestLoader);
    UnloaderTemplate.validate(TestLoader);

    var loader: LoaderInterface = undefined;
    var inst = TestLoader{};
    LoaderTemplate.populate(&loader, &inst);

    const settings = TestLoader.LoadSettings{ .scale = 2 };
    const loaded = try loader.vtable.load(loader.ptr, "abc", null, &settings);
    try std.testing.expectEqual(@as(TestAsset, 6), loaded);

    try std.testing.expectEqual(@as(usize, 1), TestLoader.extensions().len);
}

test "AssetSaver validates template contract" {
    const TestAsset = struct {
        value: usize,
    };

    const TestSaver = struct {
        pub const SaveSettings = struct {
            overwrite: bool = false,
        };

        pub fn save(_: *@This(), asset: *const TestAsset, absolute_path: []const u8, file_resolver: ?*const FileResolver, settings: ?*const SaveSettings) anyerror!void {
            _ = asset;
            _ = absolute_path;
            _ = file_resolver;
            _ = settings;
        }
    };

    const SaverTemplate = AssetSaverTemplate(TestAsset);
    const SaverInterface = AssetSaver(TestSaver, TestAsset);
    SaverTemplate.validate(TestSaver);

    var saver: SaverInterface = undefined;
    var inst = TestSaver{};
    SaverTemplate.populate(&saver, &inst);
    const asset = TestAsset{ .value = 1 };
    try saver.vtable.save(saver.ptr, &asset, "out.bin", null, null);

    try std.testing.expect(true);
}
