//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const raylib_plugin = @import("app.plugin.zig");
const assets_plugin = @import("assets.plugin.zig");

fn init(allocator: std.mem.Allocator, plugs: *plugins.PluginManager, ecs: *zevy_ecs.Manager) !void {
    _ = allocator;
    _ = ecs;
    try plugs.add(raylib_plugin.RaylibPlugin, raylib_plugin.RaylibPlugin{
        .title = "Zevy Raylib App",
        .width = 800,
        .height = 600,
    });
    try plugs.add(assets_plugin.AssetsPlugin, assets_plugin.AssetsPlugin{});
}

test "zevy_raylib init" {
    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator);
    defer ecs.deinit();
    var plugs = plugins.PluginManager.init(allocator);
    defer plugs.deinit(&ecs);
    try init(allocator, &plugs, &ecs);

    try std.testing.expect(plugs.get(raylib_plugin.RaylibPlugin) != null);
    try std.testing.expect(plugs.get(assets_plugin.AssetsPlugin) != null);

    try plugs.build(&ecs);
}

test {
    std.testing.refAllDecls(@This());
}
