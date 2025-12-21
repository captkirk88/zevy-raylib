//! Example Zig application demonstrating integration of Zevy ECS with Raylib via the Zevy Raylib plugin.
//! This example creates a window, initializes audio, and runs a simple game loop
//! with entity movement and rendering using Zevy ECS and Raylib.
//!
//! It showcases how to set up the ECS manager, plugin manager, and register custom systems
//! for movement and rendering. A simple UI button is also created to demonstrate UI interaction.

const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const zevy_raylib = @import("zevy_raylib");
const ui = zevy_raylib.ui;
const layout = zevy_raylib.ui.layout;
const input = zevy_raylib.input;
const rl = @import("raylib");

// Import the plugins we need
const RaylibPlugin = zevy_raylib.RaylibPlugin;
const UIPlugin = zevy_raylib.UIPlugin;
const AssetsPlugin = zevy_raylib.AssetsPlugin;
const InputPlugin = zevy_raylib.InputPlugin;
const ParamRegistry = zevy_raylib.ParamRegistry;

const CIRCLE_COUNT = 10_000;

const DeltaTime = f32;

// Example components for our ECS
const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

const Sprite = struct {
    radius: f32,
    color: rl.Color,
};

// Example system that updates entity positions
fn movementSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.params.Query(struct { pos: Position, vel: Velocity }, .{}),
    dt_res: zevy_ecs.params.Res(DeltaTime),
) !void {
    _ = manager;
    const dt = dt_res.ptr.*;

    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const vel: *Velocity = item.vel;

        pos.x += vel.x * dt;
        pos.y += vel.y * dt;

        // Bounce off screen edges
        if (pos.x < 0 or pos.x > @as(f32, @floatFromInt(rl.getScreenWidth()))) vel.x = -vel.x;
        if (pos.y < 0 or pos.y > @as(f32, @floatFromInt(rl.getScreenHeight()))) vel.y = -vel.y;
    }
}

// Example system that renders sprites
fn renderSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.params.Query(struct { pos: Position, sprite: Sprite }, struct {}),
) !void {
    _ = manager;

    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const sprite: *Sprite = item.sprite;

        rl.drawCircleV(
            rl.Vector2{ .x = pos.x, .y = pos.y },
            sprite.radius,
            sprite.color,
        );
    }
}

const CloseMeButtonTag = struct {};

fn buttonClickedSystem(
    manager: *zevy_ecs.Manager,
    exit_app_writer: zevy_ecs.params.EventWriter(zevy_raylib.ExitAppEvent),
    click_events: zevy_ecs.params.EventReader(zevy_raylib.ui.input.UIClickEvent),
    query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        button: zevy_raylib.ui.components.UIButton,
        tag: CloseMeButtonTag,
    }, .{}),
) !void {
    _ = manager;

    while (click_events.read()) |event| {
        while (query.next()) |item| {
            //const button: *zevy_raylib.ui.components.UIButton = item.button;
            if (event.data.entity.eql(item.entity)) {
                exit_app_writer.write(.{});
                event.handled = true;
            }
        }
    }
}

// Main game loop system
fn gameLoop(ecs: *zevy_ecs.Manager, scheduler: *zevy_ecs.schedule.Scheduler) !void {
    var accumulator: f32 = 0.0;
    const fixed_dt: f32 = 1.0 / 60.0; // 1/60 for physics/logic updates
    const dt = try ecs.addResource(DeltaTime, fixed_dt);

    try scheduler.runStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreStartup), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate).subtract(1));

    const exit_event_store = ecs.getResource(zevy_ecs.EventStore(zevy_raylib.ExitAppEvent)) orelse return error.MissingExitAppEventStore;
    while (exit_event_store.isEmpty() and !rl.windowShouldClose()) {
        const frame_time = rl.getFrameTime();
        var clamped_frame_time = frame_time;
        if (clamped_frame_time > 0.25) clamped_frame_time = 0.25; // clamp to avoid spiral of death

        accumulator += clamped_frame_time;

        // Run game logic updates in fixed timesteps for consistency
        var updates: usize = 0;
        while (accumulator >= fixed_dt) : (accumulator -= fixed_dt) {
            dt.* = fixed_dt;

            // Run PreUpdate stage (input updates happen here)
            try scheduler.runStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreDraw).subtract(1));

            updates += 1;
            if (updates > 5) break; // avoid too many catch-up updates per frame
        }

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        // Run render systems (extended to include UI stage at PostDraw + 1000)
        try scheduler.runStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreDraw), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Last).subtract(1));

        // Display FPS
        rl.drawFPS(10, 10);
        rl.drawText("Zevy Raylib Plugin Integration Example", 10, 40, 20, rl.Color.dark_gray);
        rl.drawText("Press ESC to exit", 10, 70, 16, rl.Color.gray);

        var buf: [128]u8 = undefined;
        const entity_count = try std.fmt.bufPrintZ(&buf, "Total Entities: {d}", .{CIRCLE_COUNT});
        rl.drawText(entity_count, 10, 100, 16, rl.Color.white);
    }

    try scheduler.runStages(ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Exit), zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Max).subtract(1));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS
    var ecs = try zevy_ecs.Manager.init(allocator);
    defer ecs.deinit();

    // Initialize plugin manager
    var plugin_manager = plugins.PluginManager.init(allocator);
    defer plugin_manager.deinit(&ecs);

    std.log.info("Adding RaylibPlugin...", .{});
    // Manually add plugins one by one to showcase integration
    try plugin_manager.add(RaylibPlugin(ParamRegistry), RaylibPlugin(ParamRegistry){
        .title = "Zevy Raylib Example",
        .width = 1280,
        .height = 720,
        .log_level = .info,
    });

    std.log.info("Adding AssetsPlugin...", .{});
    try plugin_manager.add(AssetsPlugin, .{});

    std.log.info("Adding InputPlugin...", .{});
    try plugin_manager.add(InputPlugin(ParamRegistry), .{});

    std.log.info("Adding RayGuiPlugin...", .{});
    try plugin_manager.add(UIPlugin(ParamRegistry), .{});

    // Build all plugins (this calls their build() methods)
    std.log.info("Building plugins...", .{});
    try plugin_manager.build(&ecs);

    // Load the icon atlas
    const assets = ecs.getResource(zevy_raylib.Assets) orelse return error.MissingAssets;
    zevy_raylib.ui.systems.registerIconAtlasFromAssets(&ecs, assets, "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml", .{});

    // Get the scheduler that was created by the plugins
    var scheduler = ecs.getResource(zevy_ecs.schedule.Scheduler) orelse return error.MissingScheduler;

    // Register our custom systems
    std.log.info("Registering custom systems...", .{});
    scheduler.addSystem(&ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostUpdate), buttonClickedSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update), movementSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&ecs, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Draw), renderSystem, zevy_ecs.DefaultParamRegistry);

    // Create some example entities
    std.log.info("Creating example entities...", .{});
    const colors = [_]rl.Color{
        rl.Color.red,
        rl.Color.green,
        rl.Color.blue,
        rl.Color.yellow,
        rl.Color.magenta,
        rl.Color.orange,
        rl.Color.purple,
    };

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..CIRCLE_COUNT) |i| {
        _ = ecs.create(.{
            Position{
                .x = random.float(f32) * @as(f32, @floatFromInt(rl.getScreenWidth())),
                .y = random.float(f32) * @as(f32, @floatFromInt(rl.getScreenHeight())),
            },
            Velocity{
                .x = (random.float(f32) - 0.5) * 200.0, // pixels per second
                .y = (random.float(f32) - 0.5) * 200.0, // pixels per second
            },
            Sprite{
                .radius = 10 + random.float(f32) * 20,
                .color = colors[i % colors.len],
            },
        });
    }

    // Showing how to use gui
    const root_container = ecs.create(.{
        layout.UIContainer.init("root"),
        // Screen bounds rectangle
        ui.components.UIRect.init(
            0,
            0,
            @floatFromInt(rl.getScreenWidth()),
            @floatFromInt(rl.getScreenHeight()),
        ),
    });
    const close_button = ecs.create(.{
        ui.components.UIRect.init(0, 0, 100, 50),
        ui.components.UIButton.init("Close Me"),
        layout.AnchorLayout.init(.top_right),
        CloseMeButtonTag{},
    });

    const relations = ecs.getResource(zevy_ecs.params.Relations).?;
    try relations.add(&ecs, close_button, root_container, zevy_ecs.relations.Child);

    // Add input key icon to the button
    const icon_child = ecs.create(.{
        ui.components.UIRect.init(70, 10, 16, 16),
        ui.components.UIInputKey.initSingle(input.InputKey{ .keyboard = input.KeyCode.key_enter }),
    });
    try relations.add(&ecs, icon_child, close_button, zevy_ecs.relations.Child);

    std.log.info("Starting game loop...", .{});

    // Run the game loop
    try gameLoop(&ecs, scheduler);

    std.log.info("Shutting down...", .{});
}
