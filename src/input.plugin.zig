const std = @import("std");
const plugins = @import("plugins");
const input = @import("input/input.zig");
const zevy_ecs = @import("zevy_ecs");

pub const params = input.params;

/// Input Plugin
/// Adds input handling capabilities to the ECS manager.
pub fn InputPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Self = @This();

        pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
            _ = self;
            _ = plugin_manager;
            _ = try e.addResource(input.InputManager, input.InputManager.init(e.allocator));
            const scheduler = e.getResource(zevy_ecs.schedule.Scheduler) orelse try e.addResource(zevy_ecs.schedule.Scheduler, try zevy_ecs.schedule.Scheduler.init(e.allocator));
            scheduler.addSystem(e, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate), inputUpdateSystem, ParamRegistry);
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
            // Resources added via `Manager.addResource` are owned by the ECS and
            // will be cleaned up by `Manager.deinit`. Avoid double-free by
            // not deinitializing them here.
            _ = self;
            _ = e;
        }
    };
}

fn inputUpdateSystem(manager: *zevy_ecs.Manager, input_manager: *params.Bindings) !void {
    _ = manager;
    try input_manager.update();
}
