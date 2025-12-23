const std = @import("std");
const reflect = @import("zevy_reflect");
const FileResolver = @import("loader.zig").FileResolver;

/// AssetProcessor wrapper type: validates that a processor implements the required interface
/// and provides a unified interface for post-processing assets after they are loaded.
///
/// Processors are optional and can be used to transform or enrich assets after loading.
/// For example, an IconAtlasProcessor might build a KeyCode -> frame index lookup table
/// from the raw frame names in a texture atlas.
///
/// Required processor methods:
///   - process(self: ProcessorType, asset: *AssetType, allocator: Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void
///   - ProcessSettings: type (must be declared, can be an empty struct)
pub fn AssetProcessor(comptime AssetType: type, comptime ProcessorType: type) type {
    // Compile-time validation
    comptime {
        if (!reflect.hasStruct(ProcessorType, "ProcessSettings")) {
            @compileError("Processor must have a ProcessSettings pub struct declaration: " ++ @typeName(ProcessorType));
        }
        _ = reflect.verifyFuncWithArgs(ProcessorType, "process", .{
            *AssetType,
            std.mem.Allocator,
            ?*const FileResolver,
            ?*const ProcessorType.ProcessSettings,
        }) catch |err| {
            switch (err) {
                error.NotAFunction, error.FuncDoesNotExist => @compileError("Processor must have a 'process' method: " ++ @typeName(ProcessorType)),
                error.IncorrectArgs => @compileError("Processor 'process' method has incorrect arguments: " ++ @typeName(ProcessorType)),
            }
        };
    }

    return struct {
        instance: ProcessorType,

        const Self = @This();
        pub const ProcessSettings = ProcessorType.ProcessSettings;

        pub fn init(processor: ProcessorType) Self {
            return .{
                .instance = processor,
            };
        }

        /// Process an asset after it has been loaded.
        /// The processor modifies the asset in-place.
        pub fn process(self: Self, asset: *AssetType, allocator: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessorType.ProcessSettings) anyerror!void {
            return try self.instance.process(asset, allocator, file_resolver, settings);
        }
    };
}

test "AssetProcessor basic interface" {
    const TestAsset = struct {
        value: usize,
        processed: bool,
    };

    const TestProcessor = struct {
        multiplier: usize,

        pub const ProcessSettings = struct {
            add_value: usize = 0,
        };

        pub fn process(self: @This(), asset: *TestAsset, allocator: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void {
            _ = allocator;
            _ = file_resolver;
            asset.value *= self.multiplier;
            if (settings) |s| {
                asset.value += s.add_value;
            }
            asset.processed = true;
        }
    };

    const processor = AssetProcessor(TestAsset, TestProcessor).init(TestProcessor{ .multiplier = 2 });

    var asset = TestAsset{ .value = 10, .processed = false };
    const settings = TestProcessor.ProcessSettings{ .add_value = 5 };

    try processor.process(&asset, std.testing.allocator, null, &settings);

    try std.testing.expectEqual(@as(usize, 25), asset.value); // (10 * 2) + 5
    try std.testing.expect(asset.processed);
}

test "AssetProcessor without settings" {
    const TestAsset = struct {
        data: []const u8,
        touched: bool = false,
    };

    const NoOpProcessor = struct {
        pub const ProcessSettings = struct {};

        pub fn process(_: @This(), asset: *TestAsset, allocator: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void {
            _ = allocator;
            _ = file_resolver;
            _ = settings;
            asset.touched = true;
        }
    };

    const processor = AssetProcessor(TestAsset, NoOpProcessor).init(NoOpProcessor{});

    var asset = TestAsset{ .data = "test" };
    try processor.process(&asset, std.testing.allocator, null, null);

    try std.testing.expectEqualStrings("test", asset.data);
    try std.testing.expect(asset.touched);
}
