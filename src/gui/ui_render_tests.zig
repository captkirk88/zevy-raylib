const std = @import("std");
const rl = @import("raylib");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const ui = @import("ui.zig");
const layouts = ui.layout;
const comps = ui.components;
const input = @import("../input/input.zig");
const style = @import("style.zig");
const Assets = @import("../io/assets.zig").Assets;
const ui_resources = @import("resources.zig");

const SKIP_IN_DEBUG = true;
const is_debug = @import("builtin").mode == .Debug;
const should_skip = if (SKIP_IN_DEBUG and is_debug) true else false;

const TEST_SKIP_TIMEOUT_SECS = 10;
const TEST_TIMEOUT_POLL_MS: u64 = 100;

fn sleepForTimeoutPoll(ms: u64) void {
    switch (builtin.os.tag) {
        .windows => {
            const delay_interval: std.os.windows.LARGE_INTEGER =
                -@as(std.os.windows.LARGE_INTEGER, @intCast(ms)) * (std.time.ns_per_ms / 100);
            _ = std.os.windows.ntdll.NtDelayExecution(.TRUE, &delay_interval);
        },
        else => {
            const sec_type = @typeInfo(std.posix.timespec).@"struct".fields[0].type;
            const nsec_type = @typeInfo(std.posix.timespec).@"struct".fields[1].type;

            var timespec = std.posix.timespec{
                .sec = @as(sec_type, @intCast(@divFloor(ms, std.time.ms_per_s))),
                .nsec = @as(nsec_type, @intCast(@mod(ms, std.time.ms_per_s) * std.time.ns_per_ms)),
            };

            _ = std.posix.system.nanosleep(&timespec, &timespec);
        },
    }
}

const TimeoutGuard = struct {
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    fn start(self: *TimeoutGuard, test_name: []const u8) !void {
        self.thread = try std.Thread.spawn(.{}, watchdogMain, .{ &self.stop, test_name });
    }

    fn deinit(self: *TimeoutGuard) void {
        self.stop.store(true, .release);
        if (self.thread) |thread| thread.join();
        self.thread = null;
    }

    fn watchdogMain(stop: *std.atomic.Value(bool), test_name: []const u8) void {
        var remaining_ms: u64 = TEST_SKIP_TIMEOUT_SECS * std.time.ms_per_s;

        while (!stop.load(.acquire) and remaining_ms > 0) {
            const sleep_ms = @min(remaining_ms, TEST_TIMEOUT_POLL_MS);
            sleepForTimeoutPoll(sleep_ms);
            remaining_ms -= sleep_ms;
        }

        if (!stop.load(.acquire)) {
            std.debug.panic("UI render test timed out after {d}s: {s}", .{ TEST_SKIP_TIMEOUT_SECS, test_name });
        }
    }
};

fn addChildRelation(ecs: *zevy_ecs.Manager, child: zevy_ecs.Entity, parent: zevy_ecs.Entity) !void {
    const rel_ref = ecs.getResource(zevy_ecs.relations.RelationManager) orelse return error.MissingRelationManager;
    defer rel_ref.deinit();
    var rel_guard = rel_ref.lockWrite();
    defer rel_guard.deinit();
    try rel_guard.get().add(ecs, child, parent, zevy_ecs.relations.kinds.Child);
}

fn runSchedulerStages(ecs: *zevy_ecs.Manager, start_stage: zevy_ecs.schedule.StageId, end_stage: zevy_ecs.schedule.StageId) !void {
    const scheduler_ref = ecs.getResource(zevy_ecs.schedule.Scheduler) orelse return error.ResourceNotFound;
    defer scheduler_ref.deinit();
    var scheduler_guard = scheduler_ref.lockWrite();
    defer scheduler_guard.deinit();
    try scheduler_guard.get().runStages(ecs, start_stage, end_stage);
}

fn initTest(name: [:0]const u8, description: ?[:0]const u8) anyerror!zevy_ecs.Manager {
    if (should_skip) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    rl.initWindow(800, 600, name);
    // Disable ESC-closes-window so a key press in a previous test does not
    // cause windowShouldClose() to return true immediately in the next test.
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    var ecs = try zevy_ecs.Manager.init(allocator);

    if (description) |desc| {
        _ = ecs.create(.{
            ui.components.UIRect.init(10, 10, 780, 30),
            ui.components.UIText.init(desc).withAlignment(.left).withFontSize(16),
            ui.layout.AbsoluteLayout.init(.bottom_left),
        });
    }
    const input_mgr_res = try ecs.addResource(input.InputManager, .init(allocator));
    defer input_mgr_res.deinit();
    var input_mgr_guard = input_mgr_res.lockWrite();
    defer input_mgr_guard.deinit();
    // Register default UI input bindings for tests (Enter/Space/Gamepad A/etc.)
    ui.input.setupUIInputBindings(input_mgr_guard.get(), allocator) catch |err| {
        std.debug.print("Failed to setup UI input bindings in test: {s}\n", .{@errorName(err)});
        return err;
    };

    // Setup Assets for loading the icon atlas
    const assets = try ecs.addResource(Assets, Assets.init(allocator));
    defer assets.deinit();
    var assets_guard = assets.lockWrite();
    defer assets_guard.deinit();

    // Load the icon atlas
    ui.systems.registerIconAtlasFromAssets(&ecs, assets_guard.get(), "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml", .{});

    var sch = try ecs.addResource(zevy_ecs.schedule.Scheduler, try zevy_ecs.schedule.Scheduler.init(ecs.allocator));
    defer sch.deinit();
    var sch_guard = sch.lockWrite();
    defer sch_guard.deinit();
    const scheduler = sch_guard.get();

    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Startup),
        ui.systems.startupUiSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    // Ensure the InputManager is updated each frame before UI interaction detection
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate),
        testInputUpdateSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    // UI interaction detection relies on InputManager having been updated (PreUpdate).
    // Must run at Update (after PreUpdate completes) so the concurrent async dispatch
    // within a stage cannot race: uiInteractionDetectionSystem acquiring lockRead before
    // testInputUpdateSystem acquires lockWrite would read stale input state.
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
        ui.input.uiInteractionDetectionSystem,
        zevy_ecs.DefaultParamRegistry,
    );
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
        ui.systems.anchorLayoutSystem,
        zevy_ecs.DefaultParamRegistry,
    );
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
        ui.systems.flexLayoutSystem,
        zevy_ecs.DefaultParamRegistry,
    );
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
        ui.systems.gridLayoutSystem,
        zevy_ecs.DefaultParamRegistry,
    );
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
        ui.systems.dockLayoutSystem,
        zevy_ecs.DefaultParamRegistry,
    );
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostDraw),
        ui.systems.uiRenderSystem,
        zevy_ecs.DefaultParamRegistry,
    );
    scheduler.addSystem(
        &ecs,
        zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostDraw),
        ui.systems.uiInputKeyRenderSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    return ecs;
}

fn deinitTest(ecs: *zevy_ecs.Manager) void {
    // Run from Last → Exit/Max so cleanup systems (e.g. event store cleanup)
    // actually execute.
    runSchedulerStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Last), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Exit)) catch {};
    ecs.deinit();
    rl.closeWindow();
}

fn testLoop(ecs: *zevy_ecs.Manager, update_fn: fn (commands: zevy_ecs.params.Commands) void) anyerror!void {
    // Run startup stage once before the loop
    try runSchedulerStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreStartup), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Startup));

    const start = @as(i64, @intFromFloat(rl.getTime() * @as(f64, @floatFromInt(std.time.ms_per_s))));

    const max_duration_ms = TEST_SKIP_TIMEOUT_SECS * std.time.ms_per_s; // Run for 10 seconds
    while (!rl.windowShouldClose()) {
        if (!rl.isWindowReady()) break;
        const now = @as(i64, @intFromFloat(rl.getTime() * @as(f64, @floatFromInt(std.time.ms_per_s))));
        if (now - start >= max_duration_ms) break;

        const cmds = try zevy_ecs.commands.CommandsInner.init(ecs.allocator, ecs);
        defer cmds.deinit();
        update_fn(cmds);

        try runSchedulerStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.First), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostUpdate));

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        rl.drawFPS(0, 0);

        try runSchedulerStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreDraw), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Last));

        rl.endDrawing();
    }
}

// Small helper system used only in tests to ensure InputManager.update() is called
fn testInputUpdateSystem(
    input_mgr: zevy_ecs.params.ResMut(input.InputManager),
) !void {
    try input_mgr.get().update();
}

// Debug draw system used only in these tests: draw a rectangle around focused elements
fn focusDebugDrawSystem(
    manager: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        rect: comps.UIRect,
        focus: comps.UIFocus,
        visible: ?comps.UIVisible,
        enabled: ?comps.UIEnabled,
    }),
    style_res: zevy_ecs.params.Res(style.UIStyle),
) void {
    _ = manager;
    _ = style_res;
    while (query.next()) |item| {
        const rect: *comps.UIRect = item.rect;
        const visible: ?*comps.UIVisible = item.visible;
        const enabled: ?*comps.UIEnabled = item.enabled;
        if (visible) |v| {
            if (!v.visible) continue;
        }

        if (enabled) |en| {
            if (en.state == false) continue;
        }

        const b = rect.toRectangle();
        rl.drawRectangleLinesEx(b, 2, rl.Color.magenta);
    }
}

test "Render Button default" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Button default");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Button default", null);
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
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Button flat" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Button flat");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Button flat", null);
    defer {
        deinitTest(&ecs);
    }

    const btn = ecs.create(.{
        comps.UIRect.init(350, 250, 100, 50),
        comps.UIButton.init("Click Me").withStyle(.flat),
    });

    // Attach an input-key child so the renderer/system can show the prompt
    const icon_child = ecs.create(.{
        comps.UIRect.init(0, 0, 16, 16),
        comps.UIInputKey.initSingle(input.InputKey{ .keyboard = input.KeyCode.key_enter }),
    });
    try addChildRelation(&ecs, icon_child, btn);

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Button toggle" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Button toggle");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Button toggle", null);
    defer {
        deinitTest(&ecs);
    }

    const btn = ecs.create(.{
        comps.UIRect.init(350, 250, 100, 50),
        comps.UIButton.init("Click Me").withStyle(.toggle),
    });

    // Attach an input-key child so the renderer/system can show the prompt
    const icon_child = ecs.create(.{
        comps.UIRect.init(0, 0, 16, 16),
        comps.UIInputKey.initSingle(input.InputKey{ .keyboard = input.KeyCode.key_enter }),
    });
    try addChildRelation(&ecs, icon_child, btn);

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Flex Layout" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Flex Layout");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Flex Layout", null);
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
    for (0..4) |i| {
        const child = ecs.create(.{
            comps.UIRect.init(0, 0, 380, 50),
            comps.UIPanel.init(titles[i]),
            //comps.UIText.init("Panel {d}", .{i + 1}).withFontSize(16),
        });
        try addChildRelation(&ecs, child, flex_container);
    }

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Grid Layout" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Grid Layout");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Grid Layout", null);
    defer {
        deinitTest(&ecs);
    }

    const grid_container = ecs.create(.{
        comps.UIRect.init(100, 100, 600, 400),
        layouts.GridLayout.init(3, 2).withGap(10.0, 10.0),
        layouts.UIContainer.init("grid_container"),
    });

    const titles = [_][:0]const u8{ "Grid Item 0", "Grid Item 1", "Grid Item 2", "Grid Item 3", "Grid Item 4", "Grid Item 5" };
    for (titles) |title| {
        const child = ecs.create(.{
            comps.UIRect.init(0, 0, 190, 190),
            comps.UIPanel.init(title),
        });
        try addChildRelation(&ecs, child, grid_container);
    }

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Anchor Layout" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Anchor Layout");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Anchor Layout", null);
    defer {
        deinitTest(&ecs);
    }

    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    const anchor_container = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), @floatFromInt(screen_height)),
        layouts.UIContainer.init("anchor_container"),
    });

    const top_left = ecs.create(.{
        comps.UIRect.init(0, 0, 100, 50),
        comps.UIPanel.init("Top Left"),
        layouts.AnchorLayout.init(.top_left),
    });
    try addChildRelation(&ecs, top_left, anchor_container);

    const bottom_right = ecs.create(.{
        comps.UIRect.init(0, 0, 100, 50),
        comps.UIPanel.init("Bottom Right"),
        layouts.AnchorLayout.init(.bottom_right),
    });
    try addChildRelation(&ecs, bottom_right, anchor_container);

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // Update logic can be added here if needed
        }
    }.run);
}

test "Render Dock Layout" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Dock Layout");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Dock Layout", null);
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

    // Left docked panel
    const left = ecs.create(.{
        comps.UIRect.init(0, 0, 150, @floatFromInt(screen_height)),
        comps.UIPanel.init("Left"),
        layouts.DockLayout.init(.left),
    });
    try addChildRelation(&ecs, left, dock_container);

    // Top docked panel
    const top = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), 120),
        comps.UIPanel.init("Top"),
        layouts.DockLayout.init(.top),
    });
    try addChildRelation(&ecs, top, dock_container);

    // Right docked panel
    const right = ecs.create(.{
        comps.UIRect.init(0, 0, 150, @floatFromInt(screen_height)),
        comps.UIPanel.init("Right"),
        layouts.DockLayout.init(.right),
    });
    try addChildRelation(&ecs, right, dock_container);

    // Bottom docked panel
    const bottom = ecs.create(.{
        comps.UIRect.init(0, 0, @floatFromInt(screen_width), 80),
        comps.UIPanel.init("Bottom"),
        layouts.DockLayout.init(.bottom),
    });
    try addChildRelation(&ecs, bottom, dock_container);

    // Fill the remaining area with a panel
    const fill = ecs.create(.{
        comps.UIRect.init(0, 0, 0, 0),
        comps.UIPanel.init("Fill"),
        layouts.DockLayout.init(.fill),
    });
    try addChildRelation(&ecs, fill, dock_container);

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
            // No per-frame logic required for this test
        }
    }.run);
}

test "Render Two Buttons Same Input" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Two Buttons Same Input");
    defer timeout_guard.deinit();

    var ecs = try initTest("Render Two Buttons Same Input", "Press [Enter/Return]");
    defer deinitTest(&ecs);

    const btn_a = ecs.create(.{
        comps.UIRect.init(200, 200, 140, 50),
        comps.UIButton.init("Button A").withStyle(.toggle),
    });

    const btn_b = ecs.create(.{
        comps.UIRect.init(360, 200, 140, 50),
        comps.UIButton.init("Button B").withStyle(.toggle),
    });

    // Attach identical input-key children (Enter) to both buttons
    const icon_a = ecs.create(.{
        comps.UIRect.init(0, 0, 16, 16),
        comps.UIInputKey.initSingle(input.InputKey{ .keyboard = input.KeyCode.key_enter }),
    });
    try addChildRelation(&ecs, icon_a, btn_a);

    const icon_b = ecs.create(.{
        comps.UIRect.init(0, 0, 16, 16),
        comps.UIInputKey.initSingle(.{ .keyboard = input.KeyCode.key_enter }),
    });
    try addChildRelation(&ecs, icon_b, btn_b);

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
        }
    }.run);
}

test "UI Focus Navigation Demo" {
    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("UI Focus Navigation Demo");
    defer timeout_guard.deinit();

    var ecs = try initTest("UI Focus Navigation Demo", "Use [Tab]");
    defer deinitTest(&ecs);

    {
        const sch = ecs.getResource(zevy_ecs.schedule.Scheduler).?;
        defer sch.deinit();
        var sch_guard = sch.lockWrite();
        defer sch_guard.deinit();

        // Create three focusable buttons laid out horizontally
        const btn1 = ecs.create(.{
            comps.UIRect.init(160, 240, 160, 48),
            comps.UIButton.init("First"),
            comps.UIFocusable{},
        });

        const btn2 = ecs.create(.{
            comps.UIRect.init(340, 240, 160, 48),
            comps.UIButton.init("Second"),
            comps.UIFocusable{},
        });

        const btn3 = ecs.create(.{
            comps.UIRect.init(520, 240, 160, 48),
            comps.UIButton.init("Third"),
            comps.UIFocusable{},
        });

        // Give initial focus to the first button so navigation has a starting point
        // Add initial UIFocus
        try ecs.addComponent(btn1, comps.UIFocus, .{});
        // Silence unused-variable warnings for the other entities
        _ = btn2;
        _ = btn3;

        // Register the focus navigation system for this test so Tab will cycle focus
        sch_guard.get().addSystem(&ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update), ui.input.uiFocusNavigationSystem, zevy_ecs.DefaultParamRegistry);
        // Add our debug draw system so focused element is outlined
        sch_guard.get().addSystem(&ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostDraw), focusDebugDrawSystem, zevy_ecs.DefaultParamRegistry);
    }

    try testLoop(&ecs, struct {
        fn run(e: zevy_ecs.params.Commands) void {
            _ = e;
        }
    }.run);
}
