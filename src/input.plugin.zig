const std = @import("std");
const plugins = @import("plugins");
const input = @import("input/input.zig");
const zevy_ecs = @import("zevy_ecs");

pub const InputPlugin = struct {
    const Self = @This();

    pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
        _ = self;
        _ = plugin_manager;
        _ = try e.addResource(input.InputManager, input.InputManager.init(e.allocator));
    }
};
