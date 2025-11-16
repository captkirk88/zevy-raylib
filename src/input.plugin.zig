const std = @import("std");
const plugins = @import("plugins");
const input = @import("input/input.zig");
const zevy_ecs = @import("zevy_ecs");

/// Input Plugin
/// Adds input handling capabilities to the ECS manager.
pub fn InputPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Self = @This();

        pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
            _ = self;
            _ = plugin_manager;
            _ = try e.addResource(input.InputManager, input.InputManager.init(e.allocator));
            const scheduler = e.getResource(zevy_ecs.Scheduler) orelse try e.addResource(zevy_ecs.Scheduler, try zevy_ecs.Scheduler.init(e.allocator));
            scheduler.addSystem(e, zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate), inputUpdateSystem, ParamRegistry);
        }
    };
}

fn inputUpdateSystem(manager: *zevy_ecs.Manager, input_manager: zevy_ecs.Res(input.InputManager)) !void {
    _ = manager;
    try input_manager.ptr.update();
}
