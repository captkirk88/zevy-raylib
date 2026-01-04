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
            // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
            _ = self;
            _ = e;
        }
    };
}

fn inputUpdateSystem(commands: *zevy_ecs.params.Commands, input_manager: *params.Bindings) !void {
    _ = commands;
    try input_manager.update();
}
