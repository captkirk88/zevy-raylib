//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const rl = @import("raylib");
const io = @import("io/root.zig");
const graphics_mod = @import("graphics/root.zig");
pub const input = @import("input/input.zig");

pub const components = struct {
    pub const Transform = @import("common/components/transform.zig").Transform;
    pub const Name = @import("common/components/name.zig").Name;
};

pub const ui = @import("gui/ui.zig");

const app_plugin = @import("app.plugin.zig");
pub const RaylibPlugin = app_plugin.RaylibPlugin;
pub const UIPlugin = ui.UIPlugin;
pub const AssetsPlugin = @import("assets.plugin.zig").AssetsPlugin;
pub const InputPlugin = @import("input.plugin.zig").InputPlugin;

/// Assets type for managing asset loading and schemes
pub const Assets = io.Assets;

/// Asset handle type
pub const AssetHandle = io.AssetHandle;

/// Shader source asset type and loader
pub const ShaderSource = io.ShaderSource;
pub const ShaderSourceLoader = io.ShaderSourceLoader;
pub const ShaderLoader = io.ShaderLoader;

/// Graphics module: shader ECS integration
pub const graphics = graphics_mod;

pub const ExitAppEvent = app_plugin.ExitAppEvent;

pub const params = struct {
    pub const Bindings = input.params.Bindings;
};

pub const RaylibParamRegistry = zevy_ecs.DefaultParamRegistry;

/// Returns true when the application should stop.
/// In windowed mode delegates to `rl.windowShouldClose()`.
/// In headless mode (no window), this probes stdin in non-blocking mode and
/// returns true on `error.EndOfStream`.
///
/// Note: End-of-stream may indicate Ctrl+C in some terminal configurations,
/// but can also indicate stdin closure/redirection. In both cases this exits.
pub fn shouldClose(io_ctx: std.Io) bool {
    if (rl.isWindowReady()) return rl.windowShouldClose();

    if (builtin.os.tag == .windows) {
        // Zig 0.16's Windows nonblocking stdin path can panic on STATUS_ALERTED.
        // In headless mode on Windows we rely on external termination (e.g. Ctrl+C).
        return false;
    }

    var stdin_file = std.Io.File.stdin();
    stdin_file.flags.nonblocking = true;

    var b: [1]u8 = undefined;
    const vec = [_][]u8{b[0..]};
    _ = stdin_file.readStreaming(io_ctx, &vec) catch |err| switch (err) {
        error.EndOfStream => return true,
        error.WouldBlock => return false,
        else => return true,
    };
    return false;
}

/// Returns ticks per second given the number of fixed-timestep updates processed
/// in a frame and the actual elapsed frame time in seconds.
/// Safe to call in headless mode (returns 0 when there is no window).
pub fn getTPS(accum: *FixedTimestepAccumulator) usize {
    const frame_time = if (rl.isWindowReady()) rl.getFrameTime() else accum.fixed_dt;
    if (frame_time == 0) return 0;
    return @intFromFloat(@as(f32, @floatFromInt(accum.updates)) / frame_time);
}

/// Begins a draw pass only when a window is ready.
/// Returns true when drawing has started and `endDrawingIfReady()` should be called.
pub fn beginDrawing() void {
    if (!rl.isWindowReady()) return;
    rl.beginDrawing();
}

/// Ends a draw pass only when a window is ready.
pub fn endDrawing() void {
    if (!rl.isWindowReady()) return;
    rl.endDrawing();
}

pub fn clearBackground(color: rl.Color) void {
    if (!rl.isWindowReady()) return;
    rl.clearBackground(color);
}

/// Fixed-timestep accumulator for game logic updates.
///
/// Works in both windowed and headless (no window) mode.
///
/// Usage:
/// ```zig
/// var accum = FixedTimestepAccumulator.init(1.0 / 60.0);
/// // each frame:
/// while (!zevy_raylib.shouldClose(io)) {
///     accum.beginFrame();
///     while (accum.consumeTick()) { /* run fixed-dt systems */ }
/// }
/// ```
pub const FixedTimestepAccumulator = struct {
    const Self = @This();

    accumulator: f32 = 0.0,
    fixed_dt: f32,
    /// Maximum fixed updates consumed per frame (spiral-of-death guard).
    max_updates: usize = 5,
    /// Frame times above this are clamped (spiral-of-death guard).
    max_frame_time: f32 = 0.25,
    /// Number of fixed updates consumed in the current frame (reset by beginFrame()).
    updates: usize = 0,

    pub fn init(fixed_dt: f32) Self {
        return .{ .fixed_dt = fixed_dt };
    }

    /// Call once per frame. Reads the frame time (or uses fixed_dt in headless mode),
    /// clamps it, and adds it to the accumulator. Resets the per-frame update counter.
    pub fn beginFrame(self: *Self) void {
        const frame_time = if (rl.isWindowReady()) rl.getFrameTime() else self.fixed_dt;
        const clamped = @min(frame_time, self.max_frame_time);
        self.accumulator += clamped;
        self.updates = 0;
    }

    /// Returns true while there is accumulated time left to consume and the
    /// per-frame update cap has not been reached. Drains one fixed_dt tick
    /// per call and increments the update counter.
    pub fn consumeTick(self: *Self) bool {
        if (self.updates >= self.max_updates) return false;
        if (self.accumulator < self.fixed_dt) return false;
        self.accumulator -= self.fixed_dt;
        self.updates += 1;
        return true;
    }
};

/// Registers all plugins defined in this package
pub fn plug(allocator: std.mem.Allocator, plugs: *plugins.PluginManager, ecs: *zevy_ecs.Manager, headless: bool) anyerror!void {
    _ = allocator;
    _ = ecs;
    try plugs.add(RaylibPlugin(RaylibParamRegistry), .{
        .window_opts = .{
            .title = "Zevy Raylib App",
            .headless = headless,
        },
    });
    try plugs.add(AssetsPlugin(RaylibParamRegistry), .{});
    try plugs.add(InputPlugin(RaylibParamRegistry), .{});
    try plugs.add(UIPlugin(RaylibParamRegistry), .{});
}

test "zevy_raylib" {
    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator);
    var plugs = plugins.PluginManager.init(allocator);
    defer {
        _ = plugs.deinit(&ecs);
        ecs.deinit();
    }
    try plug(allocator, &plugs, &ecs, true);

    try std.testing.expect(plugs.get(RaylibPlugin(RaylibParamRegistry)) != null);
    try std.testing.expect(plugs.get(AssetsPlugin) != null);
    try std.testing.expect(plugs.get(InputPlugin(RaylibParamRegistry)) != null);
    try std.testing.expect(plugs.get(UIPlugin(RaylibParamRegistry)) != null);

    if (plugs.get(RaylibPlugin(RaylibParamRegistry))) |raylib_plug| {
        try std.testing.expect(std.mem.eql(u8, raylib_plug.window_opts.title, "Zevy Raylib App"));
        try std.testing.expect(raylib_plug.window_opts.headless);
    } else {
        try std.testing.expect(false);
    }
}

test "zevy_raylib builds plugins headless" {
    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator);
    var plugs = plugins.PluginManager.init(allocator);
    defer {
        _ = plugs.deinit(&ecs);
        ecs.deinit();
    }

    try plug(allocator, &plugs, &ecs, true);
    try plugs.build(&ecs);

    try std.testing.expect(ecs.hasResource(zevy_ecs.schedule.Scheduler));
    try std.testing.expect(ecs.hasResource(input.InputManager));
    try std.testing.expect(ecs.hasResource(Assets));
}

test {
    std.testing.refAllDecls(@import("io/root.zig"));
    std.testing.refAllDecls(@import("input/tests.zig"));
    std.testing.refAllDecls(@import("input/render_tests.zig"));
    std.testing.refAllDecls(@import("common/root_tests.zig"));
    std.testing.refAllDecls(io);
    std.testing.refAllDecls(input);
    std.testing.refAllDecls(ui);
}
