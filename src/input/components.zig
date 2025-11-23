const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const input = @import("input.zig");
const Bindings = @import("params.zig").Bindings;

pub const InputActions = struct {
    const Self = @This();
    actions: std.ArrayList(input.InputAction),

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .actions = try std.ArrayList(input.InputAction).initCapacity(allocator, 1),
        };
    }
    pub fn add(self: *Self, allocator: std.mem.Allocator, action: input.InputAction) !void {
        try self.actions.append(allocator, action);
    }
};

pub fn addInputActionSystem(ecs: *zevy_ecs.Manager, bindings: Bindings, onActionsAdded: zevy_ecs.OnAdded(InputActions)) !void {
    for (onActionsAdded.items) |item| {
        if (item.comp) |actions| {
            for (actions.actions.items) |action| {
                if (bindings.getBindings().getBinding(action.name) == null) {
                    try bindings.getBindings().addBinding(input.InputAction.init(ecs.allocator, action.name, ""));
                }
            }
        }
    }
}
