const std = @import("std");
const rl = @import("raylib");
const zevy_ecs = @import("zevy_ecs");
const ui = @import("ui.zig");
const layouts = ui.layout;
const comps = ui.components;

fn initTest(name: [:0]const u8) anyerror!zevy_ecs.Manager {
    const allocator = std.testing.allocator;

    rl.initWindow(800, 600, name);

    var ecs = try zevy_ecs.Manager.init(allocator);
    var sch = try ecs.addResource(zevy_ecs.Scheduler, try zevy_ecs.Scheduler.init(ecs.allocator));
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Startup), ui.systems.startupUiSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate), ui.systems.uiInputSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Update), ui.systems.anchorLayoutSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Update), ui.systems.flexLayoutSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Update), ui.systems.gridLayoutSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Update), ui.systems.dockLayoutSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.PostDraw), ui.systems.uiRenderSystem, zevy_ecs.DefaultParamRegistry);

    return ecs;
}

fn deinitTest(ecs: *zevy_ecs.Manager) void {
    ecs.deinit();
    rl.closeWindow();
}

fn testLoop(ecs: *zevy_ecs.Manager, update_fn: fn (ecs: *zevy_ecs.Manager) void) anyerror!void {
    const scheduler = ecs.getResource(zevy_ecs.Scheduler) orelse return;

    // Run startup stage once before the loop
    try scheduler.runStage(ecs, zevy_ecs.Stage(zevy_ecs.Stages.Startup));

    const start = std.time.milliTimestamp();
    const max_duration_ms = 10 * std.time.ms_per_s; // Run for 10 seconds
    while (!rl.windowShouldClose()) {
        const now = std.time.milliTimestamp();
        if (now - start >= max_duration_ms) break;

        update_fn(ecs);

        try scheduler.runStages(ecs, zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate), zevy_ecs.Stage(zevy_ecs.Stages.PostUpdate));

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        rl.drawFPS(0, 0);

        try scheduler.runStages(ecs, zevy_ecs.Stage(zevy_ecs.Stages.PreDraw), zevy_ecs.Stage(zevy_ecs.Stages.PostDraw));

        rl.endDrawing();
    }
}

test "Render Button default" {
    var ecs = try initTest("Render Button default");
    defer {
        deinitTest(&ecs);
    }
    _ = ecs.create(.{
        comps.UIRect.init(350, 250, 100, 50),
        comps.UIButton.init("Click Me"),
        //comps.UIVisible.init(true),
        //comps.UILayer.init(1),
    });

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Button flat" {
    var ecs = try initTest("Render Button flat");
    defer {
        deinitTest(&ecs);
    }
    _ = ecs.create(.{
        comps.UIRect.init(350, 250, 100, 50),
        comps.UIButton.init("Click Me").withStyle(.flat),
        //comps.UIVisible.init(true),
        //comps.UILayer.init(1),
    });

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Button toggle" {
    var ecs = try initTest("Render Button toggle");
    defer {
        deinitTest(&ecs);
    }
    _ = ecs.create(.{
        comps.UIRect.init(350, 250, 100, 50),
        comps.UIButton.init("Click Me").withStyle(.toggle),
        //comps.UIVisible.init(true),
        //comps.UILayer.init(1),
    });

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Flex Layout" {
    var ecs = try initTest("Render Flex Layout");
    defer {
        deinitTest(&ecs);
    }
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    const flex_container = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), @floatFromInt(screen_height)),
        layouts.FlexLayout.column().withGap(10).withJustify(.center).withAlign(.stretch),
        layouts.UIContainer.init("flex_container"),
    });
    const titles = [_]?[:0]const u8{ "Panel 1", "Panel 2", "Panel 3", null };
    const rel = ecs.getResource(zevy_ecs.RelationManager).?;
    for (0..4) |i| {
        const child = ecs.create(.{
            comps.UIRect.init(0, 0, 380, 50),
            comps.UIPanel.init(titles[i]),
            //comps.UIText.init("Panel {d}", .{i + 1}).withFontSize(16),
        });
        try rel.add(&ecs, child, flex_container, zevy_ecs.relations.Child);
    }

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Grid Layout" {
    var ecs = try initTest("Render Grid Layout");
    defer {
        deinitTest(&ecs);
    }

    const grid_container = ecs.create(.{
        comps.UIRect.init(100, 100, 600, 400),
        layouts.GridLayout.init(3, 2).withGap(10.0, 10.0),
        layouts.UIContainer.init("grid_container"),
    });

    const rel = ecs.getResource(zevy_ecs.RelationManager).?;
    const titles = [_][:0]const u8{ "Grid Item 0", "Grid Item 1", "Grid Item 2", "Grid Item 3", "Grid Item 4", "Grid Item 5" };
    for (titles) |title| {
        const child = ecs.create(.{
            comps.UIRect.init(0, 0, 190, 190),
            comps.UIPanel.init(title),
        });
        try rel.add(&ecs, child, grid_container, zevy_ecs.relations.Child);
    }

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Anchor Layout" {
    var ecs = try initTest("Render Anchor Layout");
    defer {
        deinitTest(&ecs);
    }

    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    const anchor_container = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), @floatFromInt(screen_height)),
        layouts.UIContainer.init("anchor_container"),
    });

    const rel = ecs.getResource(zevy_ecs.RelationManager).?;
    const top_left = ecs.create(.{ comps.UIRect.init(0, 0, 100, 50), comps.UIPanel.init("Top Left"), layouts.AnchorLayout.init(.top_left) });
    try rel.add(&ecs, top_left, anchor_container, zevy_ecs.relations.Child);

    const bottom_right = ecs.create(.{ comps.UIRect.init(0, 0, 100, 50), comps.UIPanel.init("Bottom Right"), layouts.AnchorLayout.init(.bottom_right) });
    try rel.add(&ecs, bottom_right, anchor_container, zevy_ecs.relations.Child);

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Dock Layout" {
    var ecs = try initTest("Render Dock Layout");
    defer {
        deinitTest(&ecs);
    }

    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Container that fills the screen
    const dock_container = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), @floatFromInt(screen_height)),
        layouts.UIContainer.init("dock_container"),
    });

    const rel = ecs.getResource(zevy_ecs.RelationManager).?;

    // Left docked panel
    const left = ecs.create(.{
        comps.UIRect.init(0, 0, 150, @floatFromInt(screen_height)),
        comps.UIPanel.init("Left"),
        layouts.DockLayout.init(.left),
    });
    try rel.add(&ecs, left, dock_container, zevy_ecs.relations.Child);

    // Top docked panel
    const top = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), 120),
        comps.UIPanel.init("Top"),
        layouts.DockLayout.init(.top),
    });
    try rel.add(&ecs, top, dock_container, zevy_ecs.relations.Child);

    // Right docked panel
    const right = ecs.create(.{
        comps.UIRect.init(0, 0, 150, @floatFromInt(screen_height)),
        comps.UIPanel.init("Right"),
        layouts.DockLayout.init(.right),
    });
    try rel.add(&ecs, right, dock_container, zevy_ecs.relations.Child);

    // Bottom docked panel
    const bottom = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), 80),
        comps.UIPanel.init("Bottom"),
        layouts.DockLayout.init(.bottom),
    });
    try rel.add(&ecs, bottom, dock_container, zevy_ecs.relations.Child);

    // Fill the remaining area with a panel
    const fill = ecs.create(.{
        comps.UIRect.init(0, 0, 0, 0),
        comps.UIPanel.init("Fill"),
        layouts.DockLayout.init(.fill),
    });
    try rel.add(&ecs, fill, dock_container, zevy_ecs.relations.Child);

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // No per-frame logic required for this test
        }
    }.run);
}
