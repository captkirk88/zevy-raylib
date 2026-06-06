//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const app = @import("zevy_ecs").app;
const plugins = zevy_ecs.plugins;

/// The public API of raylib-zig
pub const rl = @import("raylib");

const io = @import("io/root.zig");
const graphics_mod = @import("graphics/root.zig");
pub const input = @import("input/root.zig");

const TestApp = struct {
    manager: *zevy_ecs.Manager,

    pub fn ecs(self: *TestApp) *zevy_ecs.Manager {
        return self.manager;
    }
    pub fn scheduler(self: *TestApp) *zevy_ecs.schedule.Scheduler {
        return self.manager.scheduler();
    }
    pub fn allocator(self: *TestApp) std.mem.Allocator {
        return self.manager.allocator();
    }
    pub fn io(self: *TestApp) std.Io {
        return self.manager.io();
    }
};

const zevy_mem = @import("zevy_mem");
var test_pluginManager: zevy_mem.Lazy(plugins.PluginManager) = .init(std.heap.page_allocator, struct {
    pub fn get(alloc: std.mem.Allocator) plugins.PluginManager {
        return plugins.PluginManager.init(alloc);
    }
}.get);

const test_app_vtable: app.VTable = .{
    .addSystem = test_app_addSystem,
    .addPlugin = test_app_addPlugin,
    .addEvent = test_app_addEvent,
    .addEventWithCleanupAtStage = test_app_addEventWithCleanupAtStage,
    .addStage = test_app_addStage,
    .registerState = test_app_registerState,
    .unregisterState = test_app_unregisterState,
    .addResource = test_app_addResource,
    .addResourceRef = test_app_addResourceRef,
    .removeResource = test_app_removeResource,
    .pluginManager = struct {
        pub fn get(self: *anyopaque) *plugins.PluginManager {
            const app_impl: *TestApp = @ptrCast(@alignCast(self));
            _ = app_impl;
            return test_pluginManager.get();
        }
    }.get, // Not needed for these tests
    .io = test_app_io,
    .allocator = test_app_allocator,
    .ecs = test_app_ecs,
    .scheduler = test_app_scheduler,
    .update = test_app_update,
    .run = test_app_run,
    .deinit = test_app_deinit,
};

fn test_app_to_interface(app_impl: *TestApp) app.App {
    var app_iface: app.App = undefined;
    app.populate(&app_iface, app_impl, &test_app_vtable);
    return app_iface;
}

fn test_app_addSystem(self: *anyopaque, stage: zevy_ecs.schedule.StageId, system: anytype) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.manager.scheduler().addSystem(app_impl.manager, stage, system);
    return test_app_to_interface(app_impl);
}

fn test_app_addPlugin(self: *anyopaque, plugin: anytype) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    _ = plugin;
    _ = app_impl;
    std.debug.panic("TestApp wrapper does not support addPlugin");
}

fn test_app_addEvent(self: *anyopaque, comptime EventType: type) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.scheduler().registerEvent(app_impl.manager, EventType) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_addEventWithCleanupAtStage(self: *anyopaque, comptime EventType: type, stage: zevy_ecs.schedule.StageId) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.scheduler().registerEventWithCleanupAtStage(app_impl.manager, EventType, stage) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_addStage(self: *anyopaque, stage: zevy_ecs.schedule.StageId) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.scheduler().addStage(stage) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_registerState(self: *anyopaque, comptime StateEnum: type) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.scheduler().registerState(app_impl.manager, StateEnum) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_unregisterState(self: *anyopaque, comptime StateEnum: type) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.scheduler().unregisterState(app_impl.manager, StateEnum) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_addResource(self: *anyopaque, comptime ResourceType: type, resource: ResourceType) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.manager.addResourceRetained(ResourceType, resource) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_addResourceRef(self: *anyopaque, comptime ResourceType: type, resource_ref: zevy_ecs.Ref(ResourceType)) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.manager.addResourceRef(ResourceType, resource_ref) catch |err| @panic(@errorName(err));
    return test_app_to_interface(app_impl);
}

fn test_app_removeResource(self: *anyopaque, comptime ResourceType: type) app.App {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    app_impl.manager.removeResource(ResourceType);
    return test_app_to_interface(app_impl);
}

fn test_app_io(self: *anyopaque) std.Io {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    return app_impl.io();
}

fn test_app_allocator(self: *anyopaque) std.mem.Allocator {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    return app_impl.allocator();
}

fn test_app_ecs(self: *anyopaque) *zevy_ecs.Manager {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    return app_impl.ecs();
}

fn test_app_scheduler(self: *anyopaque) *zevy_ecs.schedule.Scheduler {
    const app_impl: *TestApp = @ptrCast(@alignCast(self));
    return app_impl.scheduler();
}

fn test_app_update(self: *anyopaque) anyerror!void {
    _ = self;
    std.debug.panic("does not support update", .{});
}

fn test_app_run(self: *anyopaque) anyerror!void {
    _ = self;
    std.debug.panic("does not support run", .{});
}

fn test_app_deinit(self: *anyopaque) void {
    _ = self;
}

pub const components = struct {
    pub const Transform = @import("common/components/transform.zig").Transform;
    pub const Name = @import("common/components/name.zig").Name;
};

pub const ui = @import("gui/ui.zig");

const app_plugin = @import("app.plugin.zig");
pub const RaylibPlugin = app_plugin.RaylibPlugin;
pub const WindowOpts = app_plugin.WindowOpts;
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

pub const params = struct {
    pub const Bindings = input.params.Bindings;
};

pub const timing = @import("utils/timing.zig");

pub const RaylibParamRegistry = zevy_ecs.MergedSystemParamRegistry(&.{ params.Bindings, zevy_ecs.DefaultParamRegistry });

/// Default plugins. These are not automatically registered
pub const RaylibDefaultPlugins = &[_]type{
    RaylibPlugin,
    AssetsPlugin,
    InputPlugin,
    UIPlugin,
};

/// Returns true when the application should stop.
/// In windowed mode delegates to `rl.windowShouldClose()`.
/// In headless mode (no window), this probes stdin in non-blocking mode and
/// returns true on `error.EndOfStream`.
///
/// Note: End-of-stream may indicate Ctrl+C in some terminal configurations,
/// but can also indicate stdin closure/redirection. In both cases this exits.
pub fn shouldClose(io_ctx: std.Io, key: ?rl.KeyboardKey) bool {
    if (rl.isWindowReady()) {
        // Raylib pumps events during its frame lifecycle; rely on the window close
        // flag directly and keep ESC as an explicit fallback.
        if (rl.windowShouldClose()) return true;
        return rl.isKeyPressed(key orelse .escape);
    }

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
pub fn getTPS(accum: *const timing.FixedTimestepAccumulator) usize {
    const frame_time = if (rl.isWindowReady()) rl.getFrameTime() else accum.delta;
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

/// Registers all plugins defined in this package
fn plug(plugs: *plugins.PluginManager, headless: bool) anyerror!void {
    try plugs.add(RaylibPlugin, .{
        .window_opts = .{
            .title = "Zevy Raylib App",
            .headless = headless,
        },
    });
    try plugs.add(AssetsPlugin, .{});
    try plugs.add(InputPlugin, .{});
    try plugs.add(UIPlugin, .{});
}

fn testInit() std.process.Init {
    if (builtin.is_test == false) {
        // This function is only intended for test initialization, so it should not be called in non-test contexts.
        @compileError("testInit() should only be used in test contexts");
    }
    const State = struct {
        var initialized = false;
        var threaded: std.Io.Threaded = undefined;
        var arena: std.heap.ArenaAllocator = undefined;
        var environ_map: std.process.Environ.Map = undefined;
    };

    if (!State.initialized) {
        State.threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        State.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        State.environ_map = std.process.Environ.Map.init(State.arena.allocator());
        State.initialized = true;
    }

    return .{
        .arena = &State.arena,
        .gpa = std.heap.page_allocator,
        .io = State.threaded.io(),
        .minimal = .{ .args = .{ .vector = undefined }, .environ = .empty },
        .preopens = .empty,
        .environ_map = &State.environ_map,
    };
}

test "zevy_raylib" {
    const init = testInit();
    const allocator = init.gpa;
    var ecs = try zevy_ecs.Manager.init(allocator, init.io);
    var plugs = plugins.PluginManager.init(allocator);
    defer {
        _ = plugs.deinit(&ecs);
        ecs.deinit();
    }
    try plug(&plugs, true);

    try std.testing.expect(plugs.get(RaylibPlugin) != null);
    try std.testing.expect(plugs.get(AssetsPlugin) != null);
    try std.testing.expect(plugs.get(InputPlugin) != null);
    try std.testing.expect(plugs.get(UIPlugin) != null);

    if (plugs.get(RaylibPlugin)) |raylib_plug| {
        try std.testing.expect(std.mem.eql(u8, raylib_plug.window_opts.title, "Zevy Raylib App"));
        try std.testing.expect(raylib_plug.window_opts.headless);
    } else {
        try std.testing.expect(false);
    }
}

test "zevy_raylib builds plugins headless" {
    const allocator = std.testing.allocator;
    var ecs = try zevy_ecs.Manager.init(allocator, std.testing.io);
    var test_impl = TestApp{ .manager = &ecs };
    var app_iface = test_app_to_interface(&test_impl);
    var plugs = plugins.PluginManager.init(allocator);
    defer {
        _ = plugs.deinit(&ecs);
        ecs.deinit();
    }

    try plug(&plugs, true);
    try plugs.build(&app_iface);

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
