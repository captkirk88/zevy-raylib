const std = @import("std");

/// Result of scheme resolution
pub const ResolveResult = union(enum) {
    /// Resolved to a file path
    file_path: []const u8,
    /// Resolved to a URL
    url: []const u8,
    /// Resolved to embedded data
    embedded_data: []const u8,
    /// Custom resolver result (opaque data)
    custom: []const u8,
};

/// Scheme resolver interface - can resolve scheme://path to actual location
pub const SchemeResolver = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    destroy_fn: ?*const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void, // Optional function to destroy the pointer itself

    const VTable = struct {
        resolve: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror!ResolveResult,
        deinit: ?*const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    };

    pub fn init(pointer: anytype) SchemeResolver {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        if (ptr_info != .pointer) @compileError("Expected pointer type");

        const gen = struct {
            fn resolveImpl(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror!ResolveResult {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.pointer.child.resolve, .{ self, allocator, path });
            }

            fn deinitImpl(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                if (@hasDecl(ptr_info.pointer.child, "deinit")) {
                    @call(.always_inline, ptr_info.pointer.child.deinit, .{ self, allocator });
                }
            }

            const vtable = VTable{
                .resolve = resolveImpl,
                .deinit = if (@hasDecl(ptr_info.pointer.child, "deinit")) deinitImpl else null,
            };
        };

        return SchemeResolver{
            .ptr = @ptrCast(pointer),
            .vtable = &gen.vtable,
            .destroy_fn = null, // Don't destroy borrowed pointers
        };
    }

    /// Create a SchemeResolver that will destroy its pointer when deinited
    pub fn initOwned(pointer: anytype) SchemeResolver {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        if (ptr_info != .pointer) @compileError("Expected pointer type");

        const gen = struct {
            fn resolveImpl(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror!ResolveResult {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.pointer.child.resolve, .{ self, allocator, path });
            }

            fn deinitImpl(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                if (@hasDecl(ptr_info.pointer.child, "deinit")) {
                    @call(.always_inline, ptr_info.pointer.child.deinit, .{ self, allocator });
                }
            }

            fn destroyImpl(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                allocator.destroy(self);
            }

            const vtable = VTable{
                .resolve = resolveImpl,
                .deinit = if (@hasDecl(ptr_info.pointer.child, "deinit")) deinitImpl else null,
            };
        };

        return SchemeResolver{
            .ptr = @ptrCast(pointer),
            .vtable = &gen.vtable,
            .destroy_fn = &gen.destroyImpl,
        };
    }

    pub fn resolve(self: SchemeResolver, allocator: std.mem.Allocator, path: []const u8) anyerror!ResolveResult {
        return self.vtable.resolve(self.ptr, allocator, path);
    }

    pub fn deinit(self: SchemeResolver, allocator: std.mem.Allocator) void {
        if (self.vtable.deinit) |deinit_fn| {
            deinit_fn(self.ptr, allocator);
        }
        if (self.destroy_fn) |destroy| {
            destroy(self.ptr, allocator);
        }
    }
};

/// Registry for managing scheme resolvers
pub const SchemeRegistry = struct {
    allocator: std.mem.Allocator,
    resolvers: std.StringHashMap(SchemeResolver),

    pub fn init(allocator: std.mem.Allocator) SchemeRegistry {
        return SchemeRegistry{
            .allocator = allocator,
            .resolvers = std.StringHashMap(SchemeResolver).init(allocator),
        };
    }

    pub fn deinit(self: *SchemeRegistry) void {
        var iterator = self.resolvers.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.resolvers.deinit();
    }

    /// Register a scheme resolver
    pub fn registerScheme(self: *SchemeRegistry, scheme: []const u8, resolver: SchemeResolver) !void {
        const owned_scheme = try self.allocator.dupe(u8, scheme);
        errdefer self.allocator.free(owned_scheme);

        const result = try self.resolvers.getOrPut(owned_scheme);
        if (result.found_existing) {
            // Clean up old resolver
            result.value_ptr.deinit(self.allocator);
            // Free the owned_scheme since we're not using it
            self.allocator.free(owned_scheme);
        }
        result.value_ptr.* = resolver;
    }

    /// Unregister a scheme resolver
    pub fn unregisterScheme(self: *SchemeRegistry, scheme: []const u8) void {
        if (self.resolvers.fetchRemove(scheme)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }
    }

    /// Resolve a URI using registered schemes
    pub fn resolve(self: *SchemeRegistry, uri: []const u8) anyerror!ResolveResult {
        if (std.mem.indexOf(u8, uri, "://")) |separator_pos| {
            const scheme = uri[0..separator_pos];
            const path = uri[separator_pos + 3 ..];

            if (self.resolvers.get(scheme)) |resolver| {
                return resolver.resolve(self.allocator, path);
            }
            return error.UnknownScheme;
        }

        // No scheme - treat as regular file path
        const owned_path = try self.allocator.dupe(u8, uri);
        return ResolveResult{ .file_path = owned_path };
    }

    /// Check if a scheme is registered
    pub fn hasScheme(self: *SchemeRegistry, scheme: []const u8) bool {
        return self.resolvers.contains(scheme);
    }

    /// Get list of registered schemes
    pub fn getSchemes(self: *SchemeRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        var schemes = try std.ArrayList([]const u8).initCapacity(allocator, 8);
        defer schemes.deinit(allocator);

        var iterator = self.resolvers.keyIterator();
        while (iterator.next()) |key| {
            try schemes.append(allocator, try allocator.dupe(u8, key.*));
        }

        return try schemes.toOwnedSlice(allocator);
    }
};

// ===== BUILT-IN RESOLVERS =====

/// Embedded asset resolver - NOTE: This is defined in assets.zig as it needs access to embedded_assets module
/// Use the EmbeddedResolver from assets.zig instead
/// File system resolver - resolves file://path to absolute file path
pub const FileResolver = struct {
    pub fn resolve(self: *FileResolver, allocator: std.mem.Allocator, path: []const u8) !ResolveResult {
        _ = self;
        const resolved_path = try allocator.dupe(u8, path);
        return ResolveResult{ .file_path = resolved_path };
    }
};

/// Folder-based resolver - resolves folder://path to base_folder/path
pub const FolderResolver = struct {
    base_folder: []const u8,

    pub fn init(base_folder: []const u8) FolderResolver {
        return FolderResolver{ .base_folder = base_folder };
    }

    pub fn resolve(self: *FolderResolver, allocator: std.mem.Allocator, path: []const u8) !ResolveResult {
        const resolved_path = try std.fs.path.join(allocator, &[_][]const u8{ self.base_folder, path });
        return ResolveResult{ .file_path = resolved_path };
    }
};

/// URL resolver - resolves http://url or https://url to URL string
pub const UrlResolver = struct {
    base_url: []const u8,

    pub fn init(base_url: []const u8) UrlResolver {
        return UrlResolver{ .base_url = base_url };
    }

    pub fn resolve(self: *UrlResolver, allocator: std.mem.Allocator, path: []const u8) !ResolveResult {
        // Combine base URL with path
        const url = if (std.mem.endsWith(u8, self.base_url, "/") or std.mem.startsWith(u8, path, "/"))
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ self.base_url, path })
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.base_url, path });

        return ResolveResult{ .url = url };
    }
};

/// Environment-based resolver - resolves different paths based on build mode
pub const EnvironmentResolver = struct {
    dev_base: []const u8,
    prod_base: []const u8,
    is_debug: bool,

    pub fn init(dev_base: []const u8, prod_base: []const u8, is_debug: bool) EnvironmentResolver {
        return EnvironmentResolver{
            .dev_base = dev_base,
            .prod_base = prod_base,
            .is_debug = is_debug,
        };
    }

    pub fn resolve(self: *EnvironmentResolver, allocator: std.mem.Allocator, path: []const u8) !ResolveResult {
        const base = if (self.is_debug) self.dev_base else self.prod_base;
        const resolved_path = try std.fs.path.join(allocator, &[_][]const u8{ base, path });
        return ResolveResult{ .file_path = resolved_path };
    }
};

// ===== TESTS =====

test "SchemeRegistry basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    // Initially empty
    try testing.expect(!registry.hasScheme("test"));

    // Register a resolver
    var file_resolver = FileResolver{};
    try registry.registerScheme("file", SchemeResolver.init(&file_resolver));

    // Should now have the scheme
    try testing.expect(registry.hasScheme("file"));

    // Unregister
    registry.unregisterScheme("file");
    try testing.expect(!registry.hasScheme("file"));
}

test "SchemeRegistry resolve file path" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    // Test regular file path (no scheme)
    const result = try registry.resolve("test.txt");
    defer allocator.free(result.file_path);

    try testing.expect(result == .file_path);
    try testing.expectEqualStrings("test.txt", result.file_path);
}

test "SchemeRegistry resolve with file scheme" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    var file_resolver = FileResolver{};
    try registry.registerScheme("file", SchemeResolver.init(&file_resolver));

    const result = try registry.resolve("file://test.txt");
    defer allocator.free(result.file_path);

    try testing.expect(result == .file_path);
    try testing.expectEqualStrings("test.txt", result.file_path);
}

test "SchemeRegistry resolve with folder scheme" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    var folder_resolver = FolderResolver.init("assets");
    try registry.registerScheme("assets", SchemeResolver.init(&folder_resolver));

    const result = try registry.resolve("assets://player.png");
    defer allocator.free(result.file_path);

    try testing.expect(result == .file_path);
    try testing.expect(std.mem.endsWith(u8, result.file_path, "assets/player.png") or
        std.mem.endsWith(u8, result.file_path, "assets\\player.png"));
}

test "SchemeRegistry resolve with URL scheme" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    var url_resolver = UrlResolver.init("https://cdn.example.com");
    try registry.registerScheme("cdn", SchemeResolver.init(&url_resolver));

    const result = try registry.resolve("cdn://texture.jpg");
    defer allocator.free(result.url);

    try testing.expect(result == .url);
    try testing.expectEqualStrings("https://cdn.example.com/texture.jpg", result.url);
}

test "SchemeRegistry unknown scheme error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    const result = registry.resolve("unknown://test.txt");
    try testing.expectError(error.UnknownScheme, result);
}

test "SchemeRegistry get schemes list" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    var file_resolver = FileResolver{};
    var folder_resolver = FolderResolver.init("assets");

    try registry.registerScheme("file", SchemeResolver.init(&file_resolver));
    try registry.registerScheme("assets", SchemeResolver.init(&folder_resolver));

    const schemes = try registry.getSchemes(allocator);
    defer {
        for (schemes) |scheme| {
            allocator.free(scheme);
        }
        allocator.free(schemes);
    }

    try testing.expectEqual(@as(usize, 2), schemes.len);

    // Check that both schemes are in the list (order may vary)
    var found_file = false;
    var found_assets = false;
    for (schemes) |scheme| {
        if (std.mem.eql(u8, scheme, "file")) found_file = true;
        if (std.mem.eql(u8, scheme, "assets")) found_assets = true;
    }
    try testing.expect(found_file);
    try testing.expect(found_assets);
}

test "SchemeRegistry environment resolver" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    var env_resolver = EnvironmentResolver.init("dev_assets", "prod_assets", true);
    try registry.registerScheme("env", SchemeResolver.init(&env_resolver));

    const result = try registry.resolve("env://config.json");
    defer allocator.free(result.file_path);

    try testing.expect(result == .file_path);
    try testing.expect(std.mem.indexOf(u8, result.file_path, "dev_assets") != null);
}

test "SchemeRegistry resolver replacement" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    var file_resolver1 = FileResolver{};
    var file_resolver2 = FileResolver{};

    // Register first resolver
    try registry.registerScheme("test", SchemeResolver.init(&file_resolver1));
    try testing.expect(registry.hasScheme("test"));

    // Replace with second resolver (should not leak memory)
    try registry.registerScheme("test", SchemeResolver.init(&file_resolver2));
    try testing.expect(registry.hasScheme("test"));
}

test "SchemeRegistry complex URI parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = SchemeRegistry.init(allocator);
    defer registry.deinit();

    // Test URIs with complex paths
    const test_cases = [_][]const u8{
        "file://path/with/slashes.txt",
        "assets://deep/nested/folder/file.png",
        "cdn://images/sprites/player/idle.gif",
    };

    var file_resolver = FileResolver{};
    var folder_resolver = FolderResolver.init("game_assets");
    var url_resolver = UrlResolver.init("https://cdn.game.com");

    try registry.registerScheme("file", SchemeResolver.init(&file_resolver));
    try registry.registerScheme("assets", SchemeResolver.init(&folder_resolver));
    try registry.registerScheme("cdn", SchemeResolver.init(&url_resolver));

    for (test_cases) |uri| {
        const result = try registry.resolve(uri);

        switch (result) {
            .file_path => |path| {
                defer allocator.free(path);
                try testing.expect(path.len > 0);
            },
            .url => |url| {
                defer allocator.free(url);
                try testing.expect(url.len > 0);
            },
            else => try testing.expect(false), // Unexpected result type
        }
    }
}
