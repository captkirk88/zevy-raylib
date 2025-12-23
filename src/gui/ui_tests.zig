const std = @import("std");
const ui = @import("ui.zig");
const zevy_ecs = @import("zevy_ecs");

test "flex layout basic row start" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create container
    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 320.0, 100.0),
        ui.layout.FlexLayout{ .direction = ui.layout.FlexDirection.row, .gap = 10.0 },
        ui.layout.UIContainer.init("test"),
    });

    // Create children with a fixed basis
    const c1 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0) });
    const c2 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0) });
    const c3 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0) });

    // Add indexed Child relations
    const rel = manager.getResource(zevy_ecs.relations.RelationManager).?;
    try rel.add(&manager, c1, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c2, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c3, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    // Validate placement
    const r1 = try manager.getComponent(c1, ui.components.UIRect);
    const r2 = try manager.getComponent(c2, ui.components.UIRect);
    const r3 = try manager.getComponent(c3, ui.components.UIRect);
    if (r1) |rect| try std.testing.expectEqual(@as(f32, 100), rect.width) else try std.testing.expect(false);
    if (r2) |rect| try std.testing.expectEqual(@as(f32, 100), rect.width) else try std.testing.expect(false);
    if (r3) |rect| try std.testing.expectEqual(@as(f32, 100), rect.width) else try std.testing.expect(false);
}

test "flex layout grow distribution" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 600.0, 100.0),
        ui.layout.FlexLayout{ .direction = ui.layout.FlexDirection.row, .gap = 0.0 },
        ui.layout.UIContainer.init("grow_test"),
    });

    const c1 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withGrow(1.0) });
    const c2 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withGrow(3.0) });
    const c3 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0) });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, c1, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c2, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c3, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r1 = try manager.getComponent(c1, ui.components.UIRect);
    const r2 = try manager.getComponent(c2, ui.components.UIRect);
    const r3 = try manager.getComponent(c3, ui.components.UIRect);
    var diff1: f32 = 0.0;
    var diff2: f32 = 0.0;
    var diff3: f32 = 0.0;
    if (r1) |rect| {
        diff1 = rect.width - 175.0;
    } else {
        try std.testing.expect(false);
    }
    if (r2) |rect| {
        diff2 = rect.width - 325.0;
    } else {
        try std.testing.expect(false);
    }
    if (r3) |rect| {
        diff3 = rect.width - 100.0;
    } else {
        try std.testing.expect(false);
    }
    const eps = 0.01;
    try std.testing.expect(diff1 >= -eps and diff1 <= eps);
    try std.testing.expect(diff2 >= -eps and diff2 <= eps);
    try std.testing.expect(diff3 >= -eps and diff3 <= eps);
}

test "flex layout order sorting" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 600.0, 100.0),
        ui.layout.FlexLayout{ .direction = ui.layout.FlexDirection.row, .gap = 0.0 },
        ui.layout.UIContainer.init("order_test"),
    });

    const c1 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withOrder(3) });
    const c2 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withOrder(1) });
    const c3 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withOrder(2) });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    // Add them in a different order to ensure ordering is applied by the system
    try rel.add(&manager, c1, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c2, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c3, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r1 = try manager.getComponent(c1, ui.components.UIRect);
    const r2 = try manager.getComponent(c2, ui.components.UIRect);
    const r3 = try manager.getComponent(c3, ui.components.UIRect);

    if (r2) |rect| try std.testing.expectEqual(@as(f32, 0), rect.x) else try std.testing.expect(false);
    if (r3) |rect| try std.testing.expectEqual(@as(f32, 100), rect.x) else try std.testing.expect(false);
    if (r1) |rect| try std.testing.expectEqual(@as(f32, 200), rect.x) else try std.testing.expect(false);
}

test "flex layout min/max constraints" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 400.0, 100.0),
        ui.layout.FlexLayout{ .direction = ui.layout.FlexDirection.row, .gap = 0.0 },
        ui.layout.UIContainer.init("constraints_test"),
    });

    const big = manager.create(.{ ui.components.UIRect.init(0, 0, 50.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withGrow(1.0).withConstraints(ui.layout.SizeConstraints.init().withMaxWidth(150.0)) });
    const small = manager.create(.{ ui.components.UIRect.init(0, 0, 50.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withGrow(1.0) });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, big, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, small, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const big_r = try manager.getComponent(big, ui.components.UIRect);
    const small_r = try manager.getComponent(small, ui.components.UIRect);

    // Container 400 - total base (200) = 200 left, split by grow: each gets 100 => sizes 200 each
    // but big has max width 150 so it should be clamped to 150 and small get remaining 250
    if (big_r) |rect| {
        std.debug.print("big rect width after layout: {any}\n", .{rect.width});
        try std.testing.expectEqual(@as(f32, 150.0), rect.width);
    } else try std.testing.expect(false);
    if (small_r) |rect| {
        std.debug.print("small rect width after layout: {any}\n", .{rect.width});
        try std.testing.expectEqual(@as(f32, 250.0), rect.width);
    } else try std.testing.expect(false);
}

test "flex layout order negative and stable tie" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 600.0, 100.0),
        ui.layout.FlexLayout{ .direction = ui.layout.FlexDirection.row, .gap = 0.0 },
        ui.layout.UIContainer.init("order_negative_test"),
    });

    // Add in order: A(order 0), B(order -1), C(order 0)
    const a = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withOrder(0) });
    const b = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withOrder(-1) });
    const c = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 10.0), ui.layout.FlexItem.init().withBasis(100.0).withOrder(0) });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    // Add them in A, B, C order to test stability of ties
    try rel.add(&manager, a, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, b, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const ra = try manager.getComponent(a, ui.components.UIRect);
    const rb = try manager.getComponent(b, ui.components.UIRect);
    const rc = try manager.getComponent(c, ui.components.UIRect);

    if (rb) |rect| {
        std.debug.print("rb.x after layout: {any}\n", .{rect.x});
        try std.testing.expectEqual(@as(f32, 0), rect.x);
    } else try std.testing.expect(false);
    if (ra) |rect| try std.testing.expectEqual(@as(f32, 100), rect.x) else try std.testing.expect(false);
    if (rc) |rect| try std.testing.expectEqual(@as(f32, 200), rect.x) else try std.testing.expect(false);
}

test "flex layout align_self override" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 300.0, 100.0),
        ui.layout.FlexLayout{ .direction = ui.layout.FlexDirection.row, .gap = 0.0, .align_items = ui.layout.FlexItemAlign.center },
        ui.layout.UIContainer.init("test2"),
    });

    const c1 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 20.0), ui.layout.FlexItem.init() });
    const c2 = manager.create(.{ ui.components.UIRect.init(0, 0, 100.0, 40.0), ui.layout.FlexItem.init().withAlignSelf(ui.layout.FlexItemAlign.start) });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, c1, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c2, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r1 = try manager.getComponent(c1, ui.components.UIRect);
    const r2 = try manager.getComponent(c2, ui.components.UIRect);

    // Container center is y = 50.0; c1 height 20 => centered y should be 50 - 10 = 40
    if (r1) |rect| {
        std.debug.print("r1.y after layout: {any}\n", .{rect.y});
        try std.testing.expectEqual(@as(f32, 40.0), rect.y);
    } else try std.testing.expect(false);

    // c2 align_self start should set y equal to container top (0.0)
    if (r2) |rect| try std.testing.expectEqual(@as(f32, 0.0), rect.y) else try std.testing.expect(false);
}

test "grid layout 2x2 basic" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 200.0, 200.0),
        ui.layout.GridLayout.init(2, 2),
        ui.layout.UIContainer.init("grid_basic"),
    });

    const c1 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});
    const c2 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});
    const c3 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});
    const c4 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, c1, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c2, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c3, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c4, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.gridLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r1 = try manager.getComponent(c1, ui.components.UIRect);
    const r2 = try manager.getComponent(c2, ui.components.UIRect);
    const r3 = try manager.getComponent(c3, ui.components.UIRect);
    const r4 = try manager.getComponent(c4, ui.components.UIRect);

    if (r1) |rect| {
        try std.testing.expectEqual(@as(f32, 0.0), rect.x);
        try std.testing.expectEqual(@as(f32, 0.0), rect.y);
        try std.testing.expectEqual(@as(f32, 100.0), rect.width);
        try std.testing.expectEqual(@as(f32, 100.0), rect.height);
    } else try std.testing.expect(false);

    if (r2) |rect| {
        try std.testing.expectEqual(@as(f32, 100.0), rect.x);
        try std.testing.expectEqual(@as(f32, 0.0), rect.y);
        try std.testing.expectEqual(@as(f32, 100.0), rect.width);
        try std.testing.expectEqual(@as(f32, 100.0), rect.height);
    } else try std.testing.expect(false);

    if (r3) |rect| {
        try std.testing.expectEqual(@as(f32, 0.0), rect.x);
        try std.testing.expectEqual(@as(f32, 100.0), rect.y);
        try std.testing.expectEqual(@as(f32, 100.0), rect.width);
        try std.testing.expectEqual(@as(f32, 100.0), rect.height);
    } else try std.testing.expect(false);

    if (r4) |rect| {
        try std.testing.expectEqual(@as(f32, 100.0), rect.x);
        try std.testing.expectEqual(@as(f32, 100.0), rect.y);
        try std.testing.expectEqual(@as(f32, 100.0), rect.width);
        try std.testing.expectEqual(@as(f32, 100.0), rect.height);
    } else try std.testing.expect(false);
}

test "anchor layout center" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 200.0, 200.0),
        ui.layout.UIContainer.init("anchor_container"),
    });

    const child = manager.create(.{
        ui.components.UIRect.init(0, 0, 50.0, 40.0),
        ui.layout.AnchorLayout.init(.center),
    });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, child, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.anchorLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r = try manager.getComponent(child, ui.components.UIRect);
    if (r) |rect| {
        try std.testing.expectEqual(@as(f32, 75.0), rect.x);
        try std.testing.expectEqual(@as(f32, 80.0), rect.y);
    } else try std.testing.expect(false);
}

test "dock layout basic" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 300.0, 200.0),
        ui.layout.UIContainer.init("dock_container"),
    });

    const left = manager.create(.{
        ui.components.UIRect.init(0, 0, 50.0, 10.0),
        ui.layout.DockLayout.init(.left),
    });
    const top = manager.create(.{
        ui.components.UIRect.init(0, 0, 10.0, 30.0),
        ui.layout.DockLayout.init(.top),
    });
    const fill = manager.create(.{
        ui.components.UIRect.init(0, 0, 10.0, 10.0),
        ui.layout.DockLayout.init(.fill),
    });

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, left, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, top, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, fill, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.dockLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r_left = try manager.getComponent(left, ui.components.UIRect);
    const r_top = try manager.getComponent(top, ui.components.UIRect);
    const r_fill = try manager.getComponent(fill, ui.components.UIRect);

    if (r_left) |rect| {
        try std.testing.expectEqual(@as(f32, 0.0), rect.x);
        try std.testing.expectEqual(@as(f32, 0.0), rect.y);
        try std.testing.expectEqual(@as(f32, 50.0), rect.width);
        try std.testing.expectEqual(@as(f32, 200.0), rect.height);
    } else try std.testing.expect(false);

    if (r_top) |rect| {
        try std.testing.expectEqual(@as(f32, 50.0), rect.x);
        try std.testing.expectEqual(@as(f32, 0.0), rect.y);
        try std.testing.expectEqual(@as(f32, 250.0), rect.width);
        try std.testing.expectEqual(@as(f32, 30.0), rect.height);
    } else try std.testing.expect(false);

    if (r_fill) |rect| {
        try std.testing.expectEqual(@as(f32, 50.0), rect.x);
        try std.testing.expectEqual(@as(f32, 30.0), rect.y);
        try std.testing.expectEqual(@as(f32, 250.0), rect.width);
        try std.testing.expectEqual(@as(f32, 170.0), rect.height);
    } else try std.testing.expect(false);
}

test "grid layout gaps and padding" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const container = manager.create(.{
        ui.components.UIRect.init(0.0, 0.0, 220.0, 220.0),
        ui.layout.GridLayout{
            .columns = 2,
            .rows = 2,
            .column_gap = 20.0,
            .row_gap = 20.0,
            .padding = .{ .left = 10.0, .top = 10.0, .right = 10.0, .bottom = 10.0 },
            .auto_flow = .row,
        },
        ui.layout.UIContainer.init("grid_padding"),
    });

    const c1 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});
    const c2 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});
    const c3 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});
    const c4 = manager.create(.{ui.components.UIRect.init(0, 0, 10.0, 10.0)});

    const rel = manager.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    try rel.add(&manager, c1, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c2, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c3, container, zevy_ecs.relations.kinds.Child);
    try rel.add(&manager, c4, container, zevy_ecs.relations.kinds.Child);

    const system = zevy_ecs.ToSystem(ui.systems.gridLayoutSystem, zevy_ecs.DefaultParamRegistry);
    _ = try system.run(&manager, system.ctx);

    const r1 = try manager.getComponent(c1, ui.components.UIRect);
    const r2 = try manager.getComponent(c2, ui.components.UIRect);
    const r3 = try manager.getComponent(c3, ui.components.UIRect);
    const r4 = try manager.getComponent(c4, ui.components.UIRect);

    const available_width: f32 = 220.0 - 10.0 - 10.0;
    const available_height: f32 = 220.0 - 10.0 - 10.0;
    const total_col_gap: f32 = 20.0;
    const total_row_gap: f32 = 20.0;
    const cell_width: f32 = (available_width - total_col_gap) / 2.0;
    const cell_height: f32 = (available_height - total_row_gap) / 2.0;

    if (r1) |rect| {
        try std.testing.expectEqual(@as(f32, 10.0), rect.x);
        try std.testing.expectEqual(@as(f32, 10.0), rect.y);
        try std.testing.expectEqual(cell_width, rect.width);
        try std.testing.expectEqual(cell_height, rect.height);
    } else try std.testing.expect(false);

    if (r2) |rect| {
        try std.testing.expectEqual(@as(f32, 10.0) + cell_width + 20.0, rect.x);
        try std.testing.expectEqual(@as(f32, 10.0), rect.y);
    } else try std.testing.expect(false);

    if (r3) |rect| {
        try std.testing.expectEqual(@as(f32, 10.0), rect.x);
        try std.testing.expectEqual(@as(f32, 10.0) + cell_height + 20.0, rect.y);
    } else try std.testing.expect(false);

    if (r4) |rect| {
        try std.testing.expectEqual(@as(f32, 10.0) + cell_width + 20.0, rect.x);
        try std.testing.expectEqual(@as(f32, 10.0) + cell_height + 20.0, rect.y);
    } else try std.testing.expect(false);
}
