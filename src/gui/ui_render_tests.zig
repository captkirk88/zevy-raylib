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
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate), ui.systems.uiInputSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Update), ui.systems.anchorLayoutSystem, zevy_ecs.DefaultParamRegistry);
    sch.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.PostDraw), ui.systems.uiRenderSystem, zevy_ecs.DefaultParamRegistry);

    return ecs;
}

fn testLoop(ecs: *zevy_ecs.Manager, update_fn: fn (ecs: *zevy_ecs.Manager) void) anyerror!void {
    const scheduler = ecs.getResource(zevy_ecs.Scheduler) orelse return;
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

test {
    var ecs = try initTest("Render Button");
    defer {
        ecs.deinit();
        rl.closeWindow();
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

test {
    var ecs = try initTest("Render Flex Layout");
    defer {
        ecs.deinit();
        rl.closeWindow();
    }

    const flex_entity = ecs.create(.{
        comps.UIRect.init(200, 150, 400, 300),
        layouts.FlexLayout.column().withGap(10),
        //comps.UIVisible.init(true),
        //comps.UILayer.init(1),
    });

    _ = ecs.create(.{
        comps.UIRect.init(0, 0, 380, 50),
        comps.UIPanel.init("Panel 1"),
        zevy_ecs.Relation(zevy_ecs.relations.Child).init(flex_entity, .{}),
    });
    _ = ecs.create(.{
        comps.UIRect.init(0, 0, 380, 50),
        comps.UIPanel.init("Panel 2"),
        zevy_ecs.Relation(zevy_ecs.relations.Child).init(flex_entity, .{}),
    });
    _ = ecs.create(.{
        comps.UIRect.init(0, 0, 380, 50),
        comps.UIPanel.init("Panel 3"),
        zevy_ecs.Relation(zevy_ecs.relations.Child).init(flex_entity, .{}),
    });

    try testLoop(&ecs, struct {
        fn run(e: *zevy_ecs.Manager) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}
