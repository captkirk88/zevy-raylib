//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const io = @import("io/root.zig");
const input = @import("input/input.zig");
const ui = @import("gui/ui.zig");

/// Embed utility functions to include resources in the binary
pub const embed = @import("builtin/embed.zig");

pub const RaylibPlugin = @import("app.plugin.zig").RaylibPlugin;
pub const RayGuiPlugin = @import("app.plugin.zig").RayGuiPlugin;
pub const AssetsPlugin = @import("assets.plugin.zig").AssetsPlugin;
pub const InputPlugin = @import("input.plugin.zig").InputPlugin;

/// Registers all plugins defined in this package
pub fn plug(allocator: std.mem.Allocator, plugs: *plugins.PluginManager, ecs: *zevy_ecs.Manager) anyerror!void {
    _ = allocator;
    _ = ecs;
    try plugs.add(RaylibPlugin, RaylibPlugin{
        .title = "Zevy Raylib App",
        .width = 800,
        .height = 600,
    });
    try plugs.add(RayGuiPlugin(zevy_ecs.DefaultParamRegistry), RayGuiPlugin(zevy_ecs.DefaultParamRegistry){});
    try plugs.add(AssetsPlugin, AssetsPlugin{});
    try plugs.add(InputPlugin(zevy_ecs.DefaultParamRegistry), InputPlugin(zevy_ecs.DefaultParamRegistry){});
}

test "zevy_raylib" {
    const TestPlugin = struct {
        pub fn build(self: *@This(), e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
            _ = self;
            _ = e;
            try std.testing.expect(plugin_manager.has(RaylibPlugin));
            try std.testing.expect(plugin_manager.has(AssetsPlugin));

            if (plugin_manager.get(RaylibPlugin)) |raylib_plug| {
                try std.testing.expect(std.mem.eql(u8, raylib_plug.title, "Zevy Raylib App"));
            } else {
                try std.testing.expect(false);
            }
        }
    };

    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator);
    defer ecs.deinit();
    var plugs = plugins.PluginManager.init(allocator);
    defer plugs.deinit(&ecs);
    try plug(allocator, &plugs, &ecs);
    try plugs.add(TestPlugin, TestPlugin{});

    try std.testing.expect(plugs.get(RaylibPlugin) != null);
    try std.testing.expect(plugs.get(AssetsPlugin) != null);

    try plugs.build(&ecs);
}

test {
    std.testing.refAllDeclsRecursive(@import("io/root.zig"));
    std.testing.refAllDecls(@import("input/tests.zig"));
    std.testing.refAllDeclsRecursive(io);
    std.testing.refAllDeclsRecursive(input);
    std.testing.refAllDeclsRecursive(ui);
}
