//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
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

/// Graphics module: shader ECS integration
pub const graphics = graphics_mod;

pub const ExitAppEvent = app_plugin.ExitAppEvent;

pub const params = struct {
    pub const Bindings = input.params.Bindings;
};

pub const RaylibParamRegistry = zevy_ecs.DefaultParamRegistry;

/// Registers all plugins defined in this package
pub fn plug(allocator: std.mem.Allocator, plugs: *plugins.PluginManager, ecs: *zevy_ecs.Manager, headless: bool) anyerror!void {
    _ = allocator;
    _ = ecs;
    try plugs.add(RaylibPlugin(RaylibParamRegistry), .{
        .title = "Zevy Raylib App",
        .width = 1280,
        .height = 720,
        .headless = headless,
    });
    try plugs.add(AssetsPlugin, .{});
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
        try std.testing.expect(std.mem.eql(u8, raylib_plug.title, "Zevy Raylib App"));
        try std.testing.expect(raylib_plug.headless);
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
