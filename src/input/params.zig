const std = @import("std");
const input = @import("input.zig");
const zevy_ecs = @import("zevy_ecs");

pub const Bindings = input.InputManager;

pub const InputBindingsParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            if (Child == Bindings) {
                return Child;
            }
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *zevy_ecs.Manager, comptime _: type) *Bindings {
        if (e.hasResource(Bindings) == false) {
            const rel_mgr = Bindings.init(e.allocator);
            return e.addResource(Bindings, rel_mgr) catch |err| {
                std.debug.panic("Failed to create RelationManager resource: {s}", .{@errorName(err)});
            };
        }
        return e.getResource(Bindings) orelse unreachable;
    }

    pub fn deinit(e: *zevy_ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};
