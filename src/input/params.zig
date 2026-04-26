const std = @import("std");
const input = @import("input.zig");
const zevy_ecs = @import("zevy_ecs");

pub const Bindings = input.InputManager;
const BindingsParam = *Bindings;

pub const InputBindingsParam = struct {
    pub fn matches(comptime T: type) bool {
        return T == BindingsParam;
    }

    pub fn apply(e: *zevy_ecs.Manager, comptime T: type) anyerror!T {
        if (T != BindingsParam) {
            @compileError("InputBindingsParam only supports *Bindings system parameters");
        }

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
