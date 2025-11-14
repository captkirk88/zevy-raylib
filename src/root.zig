//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const io = @import("io/root.zig");
const input = @import("input/input.zig");

/// Embed utility functions to include resources in the binary
pub const embed = @import("builtin/embed.zig");

pub const RaylibPlugin = @import("app.plugin.zig").RaylibPlugin;
pub const AssetsPlugin = @import("assets.plugin.zig").AssetsPlugin;
pub const InputPlugin = @import("input.plugin.zig").InputPlugin;

/// Registers all plugins defined in this package
pub fn plug(allocator: std.mem.Allocator, plugs: *plugins.PluginManager, ecs: *zevy_ecs.Manager) !void {
    _ = allocator;
    _ = ecs;
    try plugs.add(RaylibPlugin, RaylibPlugin{
        .title = "Zevy Raylib App",
        .width = 800,
        .height = 600,
    });
    try plugs.add(AssetsPlugin, AssetsPlugin{});
    try plugs.add(InputPlugin, InputPlugin{});
}

test "zevy_raylib init" {
    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator);
    defer ecs.deinit();
    var plugs = plugins.PluginManager.init(allocator);
    defer plugs.deinit(&ecs);
    try plug(allocator, &plugs, &ecs);

    try std.testing.expect(plugs.get(RaylibPlugin) != null);
    try std.testing.expect(plugs.get(AssetsPlugin) != null);

    try plugs.build(&ecs);
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDeclsRecursive(@import("io/root.zig"));
    std.testing.refAllDecls(@import("input/tests.zig"));
    std.testing.refAllDeclsRecursive(io);
    std.testing.refAllDeclsRecursive(input);
}
