//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const io = @import("io/root.zig");
pub const input = @import("input/input.zig");

pub const ui = @import("gui/ui.zig");

const app_plugin = @import("app.plugin.zig");
pub const RaylibPlugin = app_plugin.RaylibPlugin;
pub const UIPlugin = ui.UIPlugin;
pub const AssetsPlugin = @import("assets.plugin.zig").AssetsPlugin;
pub const InputPlugin = @import("input.plugin.zig").InputPlugin;

/// Assets type for managing asset loading and schemes
pub const Assets = io.Assets;

pub const ExitAppEvent = app_plugin.ExitAppEvent;

pub const params = struct {
    pub const Bindings = input.params.Bindings;
};

pub const ParamRegistry = zevy_ecs.MergedSystemParamRegistry(&[_]type{
    zevy_ecs.DefaultParamRegistry,
    input.params.InputBindingsParam,
});

/// Registers all plugins defined in this package
pub fn plug(allocator: std.mem.Allocator, plugs: *plugins.PluginManager, ecs: *zevy_ecs.Manager, headless: bool) anyerror!void {
    _ = allocator;
    _ = ecs;
    try plugs.add(RaylibPlugin(ParamRegistry), .{
        .title = "Zevy Raylib App",
        .width = 1280,
        .height = 720,
        .headless = headless,
    });
    try plugs.add(AssetsPlugin, .{});
    try plugs.add(InputPlugin(ParamRegistry), .{});
    try plugs.add(UIPlugin(ParamRegistry), .{});
}

test "zevy_raylib" {
    const TestPlugin = struct {
        pub fn build(self: *@This(), e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
            _ = self;
            _ = e;
            try std.testing.expect(plugin_manager.has(RaylibPlugin(ParamRegistry)));
            try std.testing.expect(plugin_manager.has(AssetsPlugin));

            if (plugin_manager.get(RaylibPlugin(ParamRegistry))) |raylib_plug| {
                try std.testing.expect(std.mem.eql(u8, raylib_plug.title, "Zevy Raylib App"));
            } else {
                try std.testing.expect(false);
            }
        }

        pub fn deinit(self: *@This(), _: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = e;
        }
    };

    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator);
    var plugs = plugins.PluginManager.init(allocator);
    defer {
        _ = plugs.deinit(&ecs);
        ecs.deinit();
    }
    try plug(allocator, &plugs, &ecs, true);
    try plugs.add(TestPlugin, .{});

    try std.testing.expect(plugs.get(RaylibPlugin(ParamRegistry)) != null);
    try std.testing.expect(plugs.get(AssetsPlugin) != null);

    try plugs.build(&ecs);
}

test {
    std.testing.refAllDeclsRecursive(@import("io/root.zig"));
    std.testing.refAllDecls(@import("input/tests.zig"));
    std.testing.refAllDecls(@import("input/render_tests.zig"));
    std.testing.refAllDeclsRecursive(io);
    std.testing.refAllDeclsRecursive(input);
    std.testing.refAllDeclsRecursive(ui);
}
