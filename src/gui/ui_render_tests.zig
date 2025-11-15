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

    const flex_container = ecs.create(.{
        comps.UIRect.init(200, 150, 400, 300),
        layouts.FlexLayout.column().withGap(10),
        layouts.UIContainer.init("flex_container"),
    });

    _ = ecs.create(.{
        comps.UIRect.init(0, 0, 380, 50),
        comps.UIPanel.init("Panel 1"),
        //comps.UIText.init("Panel 1").withFontSize(16),
        zevy_ecs.Relation(zevy_ecs.relations.Child).init(flex_container, .{}),
    });
    _ = ecs.create(.{
        comps.UIRect.init(0, 0, 380, 50),
        comps.UIPanel.init("Panel 2"),
        //comps.UIText.init("Panel 2"),
        zevy_ecs.Relation(zevy_ecs.relations.Child).init(flex_container, .{}),
    });
    _ = ecs.create(.{
        comps.UIRect.init(0, 0, 380, 50),
        comps.UIPanel.init("Panel 3"),
        //comps.UIText.init("Panel 3"),
        zevy_ecs.Relation(zevy_ecs.relations.Child).init(flex_container, .{}),
    });

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
