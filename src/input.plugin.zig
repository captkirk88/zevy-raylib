const std = @import("std");
const plugins = @import("plugins");
const input = @import("input/input.zig");
const zevy_ecs = @import("zevy_ecs");

pub const params = input.params;

/// Input Plugin
/// Adds input handling capabilities to the ECS manager.
pub fn InputPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Name: []const u8 = "InputPlugin";
        const Self = @This();

        pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) anyerror!void {
            _ = self;
            _ = plugin_manager;
            const input_ref = try e.addResource(input.InputManager, input.InputManager.init(e.allocator));
            defer input_ref.deinit();

            const scheduler_ref = try e.getOrAddResource(zevy_ecs.schedule.Scheduler, try zevy_ecs.schedule.Scheduler.init(e.allocator), null);
            defer scheduler_ref.deinit();
            var scheduler_guard = scheduler_ref.lockWrite();
            defer scheduler_guard.deinit();
            scheduler_guard.get().addSystem(e, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate), inputUpdateSystem, ParamRegistry);
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
            // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
            _ = self;
            _ = e;
        }
    };
}

fn inputUpdateSystem(commands: zevy_ecs.params.Commands, input_manager: zevy_ecs.params.ResMut(input.InputManager)) !void {
    _ = commands;
    try input_manager.get().update();
}
