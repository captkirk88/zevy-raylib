const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const io = @import("io/root.zig");
const ui = @import("gui/ui.zig");

/// Assets Plugin
/// Adds asset management capabilities to the ECS manager.
pub const AssetsPlugin = struct {
    const Name: []const u8 = "AssetsPlugin";
    const Self = @This();

    pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) anyerror!void {
        _ = self;
        _ = plugin_manager;
        try e.addResourceRetained(io.Assets, io.Assets.init(e.allocator));
    }

    pub fn deinit(self: *Self, _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
        // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
        _ = self;
        _ = e;
    }
};
