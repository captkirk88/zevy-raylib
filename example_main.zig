const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const zevy_raylib = @import("zevy_raylib");
const rl = @import("raylib");

// Import the plugins we need
const RaylibPlugin = zevy_raylib.RaylibPlugin;
const RayGuiPlugin = zevy_raylib.RayGuiPlugin;
const AssetsPlugin = zevy_raylib.AssetsPlugin;
const InputPlugin = zevy_raylib.InputPlugin;

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
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }, .{}),
) !void {
    _ = manager;
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const vel: *Velocity = item.vel;

        pos.x += vel.x;
        pos.y += vel.y;

        // Bounce off screen edges
        if (pos.x < 0 or pos.x > 800) vel.x = -vel.x;
        if (pos.y < 0 or pos.y > 600) vel.y = -vel.y;
    }
}

// Example system that renders sprites
fn renderSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(struct { pos: Position, sprite: Sprite }, struct {}),
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

// Main game loop system
fn gameLoop(manager: *zevy_ecs.Manager, scheduler: *zevy_ecs.Scheduler) !void {
    while (!rl.windowShouldClose()) {
        // Run PreUpdate stage (input updates happen here)
        try scheduler.runStages(manager, zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate), zevy_ecs.Stage(zevy_ecs.Stages.PostUpdate));

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        // Run render systems
        try scheduler.runStages(manager, zevy_ecs.Stage(zevy_ecs.Stages.PreDraw), zevy_ecs.Stage(zevy_ecs.Stages.PostDraw));

        // Display FPS
        rl.drawFPS(10, 10);
        rl.drawText("Zevy Raylib Plugin Integration Example", 10, 40, 20, rl.Color.dark_gray);
        rl.drawText("Press ESC to exit", 10, 70, 16, rl.Color.gray);
    }
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
    try plugin_manager.add(RaylibPlugin, RaylibPlugin{
        .title = "Zevy Raylib Example",
        .width = 800,
        .height = 600,
        .log_level = .info,
    });

    std.log.info("Adding AssetsPlugin...", .{});
    try plugin_manager.add(AssetsPlugin, AssetsPlugin{});

    std.log.info("Adding InputPlugin...", .{});
    try plugin_manager.add(InputPlugin(zevy_ecs.DefaultParamRegistry), InputPlugin(zevy_ecs.DefaultParamRegistry){});

    std.log.info("Adding RayGuiPlugin...", .{});
    try plugin_manager.add(RayGuiPlugin(zevy_ecs.DefaultParamRegistry), RayGuiPlugin(zevy_ecs.DefaultParamRegistry){});

    // Build all plugins (this calls their build() methods)
    std.log.info("Building plugins...", .{});
    try plugin_manager.build(&ecs);

    // Get the scheduler that was created by the plugins
    var scheduler = ecs.getResource(zevy_ecs.Scheduler) orelse return error.MissingScheduler;

    // Register our custom systems
    std.log.info("Registering custom systems...", .{});
    scheduler.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Update), movementSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&ecs, zevy_ecs.Stage(zevy_ecs.Stages.Draw), renderSystem, zevy_ecs.DefaultParamRegistry);

    // Create some example entities
    std.log.info("Creating example entities...", .{});
    const colors = [_]rl.Color{
        rl.Color.red,
        rl.Color.green,
        rl.Color.blue,
        rl.Color.yellow,
        rl.Color.magenta,
        rl.Color.orange,
    };

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..10) |i| {
        _ = ecs.create(.{
            Position{
                .x = random.float(f32) * 700 + 50,
                .y = random.float(f32) * 500 + 50,
            },
            Velocity{
                .x = (random.float(f32) - 0.5) * 4,
                .y = (random.float(f32) - 0.5) * 4,
            },
            Sprite{
                .radius = 10 + random.float(f32) * 20,
                .color = colors[i % colors.len],
            },
        });
    }

    std.log.info("Starting game loop...", .{});

    // Run the game loop
    try gameLoop(&ecs, scheduler);

    std.log.info("Shutting down...", .{});
}
