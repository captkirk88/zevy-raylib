const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const io = @import("io/root.zig");
const ui = @import("gui/ui.zig");

/// Assets Plugin
/// Adds asset management capabilities to the ECS manager.
pub const AssetsPlugin = struct {
    const Self = @This();

    pub fn build(self: *Self, e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
        _ = self;
        _ = plugin_manager;
        _ = try e.addResource(io.Assets, io.Assets.init(e.allocator));
        const scheduler = e.getResource(zevy_ecs.Scheduler) orelse return error.MissingScheduler;
        _ = scheduler;
    }
};
