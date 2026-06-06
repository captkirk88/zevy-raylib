const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = zevy_ecs.plugins;
const io = @import("io/root.zig");
const graphics = @import("graphics/root.zig");
const ui = @import("gui/ui.zig");

const Stage = zevy_ecs.schedule.Stage;
const Stages = zevy_ecs.schedule.Stages;

/// Assets Plugin
/// Adds asset management capabilities to the ECS manager.
pub const AssetsPlugin = struct {
    const Name: []const u8 = "AssetsPlugin";
    const Self = @This();

    pub fn build(_: *Self, app: *zevy_ecs.app.App, plugin_manager: *plugins.PluginManager) anyerror!void {
        _ = plugin_manager;
        app
            .addResource(io.Assets, io.Assets.init(app.io(), app.allocator()))
            // Process loads on the app thread. Some loaders (for example ShaderLoader)
            // require an active render context and fail when dispatched from async workers.
            .addSystem(zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreFixedUpdate), processAssets_System)
            .addSystem(Stage(Stages.Exit), graphics.shader.cleanupShaders_System)
            .done();
    }

    pub fn deinit(self: *Self, _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
        // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
        _ = self;
        _ = e;
    }
};

fn processAssets_System(_: zevy_ecs.params.Commands, assets_res: zevy_ecs.params.ResMut(io.Assets)) !void {
    try assets_res.get().process();
}
