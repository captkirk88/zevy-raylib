const std = @import("std");
const plugins = zevy_ecs.plugins;
const input = @import("input/root.zig");
const zevy_ecs = @import("zevy_ecs");

const main_thread_poll_stage = zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate)
    .add(50_000)
    .withOp(.sync);

pub const params = input.params;

/// Input Plugin
/// Adds input handling capabilities to the ECS manager.
pub const InputPlugin = struct {
    const Name: []const u8 = "InputPlugin";
    const Self = @This();

    pub fn build(self: *Self, app: *zevy_ecs.app.App, plugin_manager: *plugins.PluginManager) anyerror!void {
        _ = self;
        _ = plugin_manager;
        app
            .addResource(input.InputManager, input.InputManager.init(app.allocator()))
            .addSystem(zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate), inputUpdateSystem).done();
    }

    pub fn deinit(_: *Self, _: std.mem.Allocator, _: *zevy_ecs.Manager) anyerror!void {
        // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
    }
};

fn inputUpdateSystem(commands: zevy_ecs.params.Commands, input_manager: zevy_ecs.params.ResMut(input.InputManager)) !void {
    _ = commands;
    try input_manager.get().update();
}
