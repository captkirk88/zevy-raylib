const zevy_ecs = @import("zevy_ecs");

pub const AssetsPlugin = struct {
    const Self = @This();

    pub fn build(self: *Self, e: *zevy_ecs.Manager) !void {
        _ = self;
        _ = e;
    }
};
