const std = @import("std");
const input = @import("input.zig");
const zevy_ecs = @import("zevy_ecs");

pub const Bindings = input.InputManager;

pub const InputBindingsParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        if (T == Bindings) {
            return T;
        }
        return null;
    }

    pub fn apply(e: *zevy_ecs.Manager, comptime _: type) anyerror!*Bindings {
        if (e.hasResource(Bindings) == false) {
            const rel_mgr = Bindings.init(e.allocator);
            return try e.addResource(Bindings, rel_mgr);
        }
        return e.getResource(Bindings) orelse return error.MissingInputManager;
    }

    pub fn deinit(e: *zevy_ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
        // Nothing to do, InputManager is owned by ECS resources
    }
};
