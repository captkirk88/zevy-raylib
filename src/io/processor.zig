const std = @import("std");
const reflect = @import("zevy_reflect");
const FileResolver = @import("loader.zig").FileResolver;

/// Template for creating asset processors
///
/// ProcessorType: The type of the processor implementing the processing logic.
///
/// AssetType: The type of asset to be processed.
///
/// Requirements:
/// - ProcessorType must have a public struct named `ProcessSettings` defining any settings for processing
/// - ProcessorType must implement a method with the signature:
/// ```zig
///  pub fn process(self: *@This(), asset: *AssetType, allocator: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void
/// ```
///
/// Example:
/// ```zig
/// const MyAsset = struct {
///     data: []u8,
/// };
/// const MyProcessor = struct {
///     pub const ProcessSettings = struct {
///         multiplier: usize,
///     };
///
///     pub fn process(self: *@This(), asset: *MyAsset, allocator: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void {
///         _ = allocator;
///         _ = file_resolver;
///         if (settings) |s| {
///             // Process asset using s.multiplier
///         }
///     }
/// };
/// const Template = AssetProcessorTemplate(MyAsset, MyProcessor);
/// const AssetProcessor = Template.Interface;
/// const processor: AssetProcessor = undefined;
/// const processor_inst = try Template.populateFromValue(std.testing.allocator, &processor, .{});
/// defer std.testing.allocator.destroy(processor_inst);
///
/// var asset = MyAsset{ .data = ... };
/// const settings = MyProcessor.ProcessSettings{ .multiplier = 3 };
/// try processor.vtable.process(processor.ptr, &asset, std.testing.allocator, null, &settings);
/// ```
pub fn AssetProcessorTemplate(comptime ProcessorType: type, comptime AssetType: type) type {
    if (!reflect.hasStruct(ProcessorType, "ProcessSettings")) {
        @compileError("Processor must have a ProcessSettings pub struct declaration: " ++ @typeName(ProcessorType));
    }
    return reflect.Template(struct {
        pub const Name: []const u8 = "AssetProcessor";

        pub fn process(_: *@This(), asset: *AssetType, _: std.mem.Allocator, resolver: ?*const FileResolver, settings: ?*const ProcessorType.ProcessSettings) anyerror!void {
            _ = asset;
            _ = resolver;
            _ = settings;
            unreachable;
        }
    });
}

test "AssetProcessor basic interface" {
    const TestAsset = struct {
        value: usize = 0,
        processed: bool = false,
    };

    const TestProcessor = struct {
        multiplier: usize,

        pub const ProcessSettings = struct {
            add_value: usize = 0,
        };

        pub fn process(self: *@This(), asset: *TestAsset, allocator_: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void {
            _ = allocator_;
            _ = file_resolver;
            asset.value *= self.multiplier;
            if (settings) |s| {
                asset.value += s.add_value;
            }
            asset.processed = true;
        }
    };

    const Template = AssetProcessorTemplate(TestProcessor, TestAsset);
    const AssetProcessor = Template.Interface;
    var processor: AssetProcessor = undefined;
    var inst = TestProcessor{ .multiplier = 2 };
    Template.populate(&processor, &inst);

    var asset = TestAsset{ .value = 10, .processed = false };
    const settings = TestProcessor.ProcessSettings{ .add_value = 5 };

    try processor.vtable.process(processor.ptr, &asset, std.testing.allocator, null, &settings);

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

        pub fn process(_: *@This(), asset: *TestAsset, allocator_: std.mem.Allocator, file_resolver: ?*const FileResolver, settings: ?*const ProcessSettings) anyerror!void {
            _ = allocator_;
            _ = file_resolver;
            _ = settings;
            asset.touched = true;
        }
    };

    const Template = AssetProcessorTemplate(NoOpProcessor, TestAsset);
    const AssetProcessor = Template.Interface;
    var processor: AssetProcessor = undefined;
    var inst = NoOpProcessor{};
    Template.populate(&processor, &inst);

    var asset = TestAsset{ .data = "test" };
    try processor.vtable.process(processor.ptr, &asset, std.testing.allocator, null, null);

    try std.testing.expectEqualStrings("test", asset.data);
    try std.testing.expect(asset.touched);
}
