//! Example Zig application demonstrating integration of Zevy ECS with Raylib via the Zevy Raylib plugin.
//! This example creates a window, initializes audio, and runs a simple game loop
//! with entity movement and rendering using Zevy ECS and Raylib.
//!
//! It showcases how to set up the ECS manager, plugin manager, and register custom systems
//! for movement and rendering. A simple UI button is also created to demonstrate UI interaction.
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const zevy_raylib = @import("zevy_raylib");
const ui = zevy_raylib.ui;
const layout = zevy_raylib.ui.layout;
const input = zevy_raylib.input;
const rl = @import("raylib");
const zevy_app = @import("app");

// Import the plugins we need
const RaylibPlugin = zevy_raylib.RaylibPlugin;
const UIPlugin = zevy_raylib.UIPlugin;
const AssetsPlugin = zevy_raylib.AssetsPlugin;
const InputPlugin = zevy_raylib.InputPlugin;
const ParamRegistry = zevy_raylib.RaylibParamRegistry;

pub const panic = zevy_ecs.panic;
const CIRCLE_COUNT = 30_000;
const ENABLE_UI = true;

const Scheduler = zevy_ecs.schedule.Scheduler;
const Stage = zevy_ecs.schedule.Stage;
const Stages = zevy_ecs.schedule.Stages;

const Res = zevy_ecs.params.Res;
const ResMut = zevy_ecs.params.ResMut;
const Commands = zevy_ecs.params.Commands;
const Query = zevy_ecs.params.Query;
const EventReader = zevy_ecs.params.EventReader;
const EventWriter = zevy_ecs.params.EventWriter;

// Example components for our ECS
const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

const Circle = struct {
    radius: f32,
    color: rl.Color,
};

// Example system that updates entity positions
fn movementSystem(
    commands: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { pos: Position, vel: Velocity }),
    dt_res: zevy_ecs.params.Res(zevy_raylib.timing.DeltaTime),
) !void {
    _ = commands;
    const dt = dt_res.get().value;

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

// Example system that renders circles based on their Position and Sprite components
fn renderSystem(
    query: zevy_ecs.params.Query(struct { pos: Position, sprite: Circle }),
) !void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const sprite: *Circle = item.sprite;

        rl.drawCircleV(
            rl.Vector2{
                .x = pos.x,
                .y = pos.y,
            },
            sprite.radius,
            sprite.color,
        );
    }
}

const CloseMeButtonTag = struct {};

fn buttonClickedSystem(
    commands: zevy_ecs.params.Commands,
    exit_app_writer: zevy_ecs.params.EventWriter(zevy_app.ExitAppEvent),
    click_events: zevy_ecs.params.EventReader(zevy_raylib.ui.input.UIClickEvent),
    query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        button: zevy_raylib.ui.components.UIButton,
        tag: CloseMeButtonTag,
    }),
) !void {
    _ = commands;

    while (click_events.read()) |event| {
        while (query.next()) |item| {
            //const button: *zevy_raylib.ui.components.UIButton = item.button;
            if (event.data.entity.eql(item.entity)) {
                exit_app_writer.write(.Success);
                std.log.info("Close button clicked, exiting app...", .{});
                event.handled = true;
            }
        }
    }
}

fn startup(
    commands: Commands,
    _: ResMut(zevy_raylib.Assets),
    relations: zevy_ecs.params.Relations,
) !void {
    // This system demonstrates example setup during startup, after plugins have initialized.
    std.log.info("Running startup system in Startup stage...", .{});
    // zevy_raylib.ui.systems.registerIconAtlasFromAssets(
    //     commands.manager(),
    //     assets.get(),
    //     "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml",
    //     .{},
    // );

    std.log.info("Registering custom systems...", .{});
    try commands.addSystem(Stage(Stages.PostUpdate), buttonClickedSystem);
    try commands.addSystem(Stage(Stages.FixedUpdate), movementSystem);
    try commands.addSystem(Stage(Stages.Draw), renderSystem);

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
        var ent = commands.create();
        defer ent.deinit();
        try ent
            .add(Position, .{
                .x = random.float(f32) * @as(f32, @floatFromInt(rl.getScreenWidth())),
                .y = random.float(f32) * @as(f32, @floatFromInt(rl.getScreenHeight())),
            })
            .add(Velocity, .{
                .x = (random.float(f32) - 0.5) * 200.0, // pixels per second
                .y = (random.float(f32) - 0.5) * 200.0, // pixels per second
            })
            .add(Circle, .{
                .radius = 10 + random.float(f32) * 20,
                .color = colors[i % colors.len],
            }).flush();
    }

    if (ENABLE_UI) {
        // Showing how to use gui
        var root_container = commands.create();
        try root_container
            .add(layout.UIContainer, .init("root"))
            .add(ui.components.UIRect, .initScreen()).flush();
        var close_button = commands.create();
        try close_button
            .add(ui.components.UIRect, .init(0, 0, 100, 50)) // TODO make this able to be set based on text size and padding
            .add(ui.components.UIButton, .init("CLOSE ME"))
            .add(layout.AnchorLayout, .init(.top_right))
            .add(CloseMeButtonTag, .{}).flush();

        // _ = ecs.create(.{
        //     ui.components.UIRect.initScreen(),
        //     ui.components.UIMessageBox.init("This should POP!", "This is a test, only a test...", "Ok;Cancel"),
        // });

        // TODO layout.UIContainer.child("root") would be nicer than this manual relation management
        try relations.add(commands.manager(), close_button.entity(), root_container.entity(), zevy_ecs.relations.kinds.Child);
    }
}

fn renderDebugText_System(fixed_dt_res: Res(zevy_raylib.timing.FixedTimestepAccumulator)) !void {
    const fixed_dt = fixed_dt_res.get();
    const diagnostics = fixed_dt.diagnostics;

    // Display FPS
    rl.drawFPS(10, 10);
    // draw tps
    var tps_buf: [32]u8 = undefined;
    const tps_text = std.fmt.bufPrintZ(&tps_buf, "TPS: {d}", .{zevy_raylib.getTPS(fixed_dt)}) catch "TPS: ?";
    rl.drawText(
        tps_text,
        10,
        rl.getScreenHeight() - 30,
        16,
        rl.Color.yellow,
    );

    var fixed_buf: [128]u8 = undefined;
    const dropped_ms: i32 = @intFromFloat(if (diagnostics) |diag| diag.dropped_time else 1 * 1000.0);
    const fixed_text = std.fmt.bufPrintZ(
        &fixed_buf,
        "Fixed: {d} steps dropped: {d}ms overloaded: {any}",
        .{ if (diagnostics) |diag| diag.updates else 0, dropped_ms, if (diagnostics) |diag| diag.overloaded else null },
    ) catch "Fixed: ?";
    const overloaded = diagnostics != null and diagnostics.?.overloaded;
    rl.drawText(
        fixed_text,
        10,
        rl.getScreenHeight() - 50,
        16,
        if (overloaded) rl.Color.orange else rl.Color.green,
    );

    rl.drawText("Zevy Raylib Plugin Integration Example", 10, 40, 20, rl.Color.lime);
    rl.drawText("Press ESC to exit", 10, 70, 16, rl.Color.light_gray);

    var buf: [128]u8 = undefined;
    const entity_count = try std.fmt.bufPrintZ(&buf, "Total Entities: {d}", .{CIRCLE_COUNT});
    rl.drawText(entity_count, 10, 100, 16, rl.Color.white);
}

pub fn main(init: std.process.Init) !void {
    var app = zevy_app.new(init);
    defer {
        if (rl.isAudioDeviceReady()) rl.closeAudioDevice();
        if (rl.isWindowReady()) rl.closeWindow();
    }
    defer app.deinit();

    app = app
        .addPlugin(RaylibPlugin{
            .window_opts = .{
                .title = std.fmt.comptimePrint("Circles! - {d} of them!", .{CIRCLE_COUNT}),
                .resolution = .init(1280, 720),
                .vsync = false,
                .high_dpi = false,
                .fullscreen_mode = .Windowed,
            },
            .log_level = .info,
        })
        .addPlugin(AssetsPlugin{})
        .addPlugin(InputPlugin{})
        .addSystem(Stage(Stages.Startup), startup)
        .addSystem(Stage(Stages.PostDraw), renderDebugText_System);

    if (ENABLE_UI) {
        app = app.addPlugin(UIPlugin{});
    }

    try app.run();
    std.log.info("Shutting down...", .{});
}
