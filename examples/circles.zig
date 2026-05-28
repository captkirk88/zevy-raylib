//! Example Zig application demonstrating integration of Zevy ECS with Raylib via the Zevy Raylib plugin.
//! This example creates a window, initializes audio, and runs a simple game loop
//! with entity movement and rendering using Zevy ECS and Raylib.
//!
//! It showcases how to set up the ECS manager, plugin manager, and register custom systems
//! for movement and rendering. A simple UI button is also created to demonstrate UI interaction.

const std = @import("std");
const zevy_mem = @import("zevy_mem");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
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

const CIRCLE_COUNT = 10_000;

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

const Sprite = struct {
    radius: f32,
    color: rl.Color,
};

// Example system that updates entity positions
fn movementSystem(
    commands: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { pos: Position, vel: Velocity }),
    dt_res: zevy_ecs.params.Res(zevy_raylib.timing.DeltaTime),
    fixed_dt: zevy_ecs.params.Res(zevy_raylib.timing.FixedTimestepAccumulator),
) !void {
    _ = commands;
    if (!fixed_dt.get().canUpdate()) return; // Only update when the fixed timestep accumulator allows it
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
    commands: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { pos: Position, sprite: Sprite }),
) !void {
    _ = commands;

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
    assets: ResMut(zevy_raylib.Assets),
    scheduler: ResMut(zevy_ecs.schedule.Scheduler),
    relations: zevy_ecs.params.Relations,
) !void {
    // This system is just to demonstrate the PreStartup stage where you can set up resources and such before the main loop starts
    std.log.info("Running startup system in PreStartup stage...", .{});
    zevy_raylib.ui.systems.registerIconAtlasFromAssets(
        commands.manager(),
        assets.get(),
        "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml",
        .{},
    );

    std.log.info("Registering custom systems...", .{});
    scheduler.get().addSystem(commands.manager(), Stage(Stages.PostUpdate), buttonClickedSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.get().addSystem(commands.manager(), Stage(Stages.Update), movementSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.get().addSystem(commands.manager(), Stage(Stages.Draw), renderSystem, zevy_ecs.DefaultParamRegistry);

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
        const ent = try commands.create(.{
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
        ent.flush();
    }

    // Showing how to use gui
    const root_container = try commands.create(.{
        layout.UIContainer.init("root"),
        // Screen bounds rectangle
        ui.components.UIRect.initScreen(),
    });
    root_container.flush();
    const close_button = try commands.create(.{
        ui.components.UIRect.init(0, 0, 100, 50), // TODO make this able to be set based on text size and padding
        ui.components.UIButton.init("CLOSE ME"),
        //ui.components.UIInputKey.initSingle(input.InputKey{ .keyboard = input.KeyCode.key_enter }), TODO fix layout issue
        layout.AnchorLayout.init(.top_right),
        CloseMeButtonTag{},
    });
    close_button.flush();

    // _ = ecs.create(.{
    //     ui.components.UIRect.initScreen(),
    //     ui.components.UIMessageBox.init("This should POP!", "This is a test, only a test...", "Ok;Cancel"),
    // });

    // TODO layout.UIContainer.child("root") would be nicer than this manual relation management
    try relations.add(commands.manager(), close_button.entity(), root_container.entity(), zevy_ecs.relations.kinds.Child);
}

fn renderDebugText_System(fixed_dt_res: Res(zevy_raylib.timing.FixedTimestepAccumulator)) !void {
    // Display FPS
    rl.drawFPS(10, 10);
    // draw tps
    var tps_buf: [32]u8 = undefined;
    const tps_text = std.fmt.bufPrintZ(&tps_buf, "TPS: {d}", .{zevy_raylib.getTPS(fixed_dt_res.get())}) catch "TPS: ?";
    rl.drawText(
        tps_text,
        10,
        rl.getScreenHeight() - 30,
        16,
        rl.Color.black,
    );
    rl.drawText("Zevy Raylib Plugin Integration Example", 10, 40, 20, rl.Color.lime);
    rl.drawText("Press ESC to exit", 10, 70, 16, rl.Color.light_gray);

    var buf: [128]u8 = undefined;
    const entity_count = try std.fmt.bufPrintZ(&buf, "Total Entities: {d}", .{CIRCLE_COUNT});
    rl.drawText(entity_count, 10, 100, 16, rl.Color.white);
}

pub fn main(init: std.process.Init) !void {
    const app = zevy_app.new(init, ParamRegistry);
    defer {
        if (rl.isAudioDeviceReady()) rl.closeAudioDevice();
        if (rl.isWindowReady()) rl.closeWindow();
    }
    defer app.deinit();

    std.log.info("Adding RaylibPlugin...", .{});
    // Manually add plugins one by one to showcase integration
    try app.addPlugin(RaylibPlugin(ParamRegistry), RaylibPlugin(ParamRegistry){
        .window_opts = .{
            .title = std.fmt.comptimePrint("Circles! - {d} of them!", .{CIRCLE_COUNT}),
            .resolution = .init(1280, 720),
            .vsync = true,
            .high_dpi = false,
            .fullscreen_mode = .Windowed,
        },
        .log_level = .info,
    })
        .addPlugin(AssetsPlugin(ParamRegistry), .{ .io = init.io })
        .addPlugin(InputPlugin(ParamRegistry), .{})
        .addPlugin(UIPlugin(ParamRegistry), .{})
        .addSystem(Stage(Stages.PostDraw), renderDebugText_System).run();
    std.log.info("Shutting down...", .{});
}
