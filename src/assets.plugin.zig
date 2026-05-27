const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const io = @import("io/root.zig");
const ui = @import("gui/ui.zig");

/// Assets Plugin
/// Adds asset management capabilities to the ECS manager.
pub fn AssetsPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Name: []const u8 = "AssetsPlugin";
        const Self = @This();

        io: std.Io,

        pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) anyerror!void {
            _ = plugin_manager;
            try e.addResourceRetained(io.Assets, io.Assets.init(self.io, e.allocator));

            const scheduler_ptr = e.getResource(zevy_ecs.schedule.Scheduler) orelse return error.MissingScheduler;
            defer scheduler_ptr.deinit();
            const scheduler = scheduler_ptr.lockWrite();
            defer scheduler.deinit();
            scheduler.get().addSystem(e, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate), processAssetsSystem, ParamRegistry);
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
            // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
            _ = self;
            _ = e;
        }
    };
}

fn processAssetsSystem(_: zevy_ecs.params.Commands, assets_res: zevy_ecs.params.ResMut(io.Assets)) !void {
    try assets_res.get().process();
}
