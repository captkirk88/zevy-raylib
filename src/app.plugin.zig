const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const rl = @import("raylib");
const assets_plugin = @import("assets.plugin.zig");
const plugins = @import("plugins");

pub const RaylibPlugin = struct {
    const Self = @This();

    title: [:0]const u8,
    width: i32,
    height: i32,

    log_level: rl.TraceLogLevel = .warning,

    pub fn build(self: *Self, e: *zevy_ecs.Manager, _: *plugins.PluginManager) !void {
        const log = std.log.scoped(.zevy_raylib);
        const scheduler = try zevy_ecs.Scheduler.init(e.allocator);
        _ = try e.addResource(zevy_ecs.Scheduler, scheduler);
        rl.setTraceLogLevel(self.log_level);
        rl.initWindow(self.width, self.height, self.title);
        log.info("Initialized window: {s} ({d}x{d})", .{ self.title, self.width, self.height });
        rl.initAudioDevice();
        log.info("Audio device: {s}", .{if (rl.isAudioDeviceReady()) "Ready" else "Not Ready"});
        rl.setTargetFPS(500);
    }

    pub fn deinit(self: *Self, ecs: *zevy_ecs.Manager) void {
        const log = std.log.scoped(.zevy_raylib);
        _ = self;
        _ = ecs;
        rl.closeAudioDevice();
        if (!rl.isAudioDeviceReady()) log.info("Audio device closed", .{}) else log.err("Audio device failed to close", .{});
        rl.closeWindow();
        if (!rl.isWindowReady()) log.info("Window closed", .{}) else log.err("Window failed to close", .{});
    }
};

pub const GuiStage = struct {};

pub fn RayGuiPlugin(comptime ParamRegistry: type) type {
    return struct {
        const raygui = @import("raygui");
        const ui = @import("gui/ui.zig");
        const Self = @This();

        pub fn build(self: *Self, manager: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
            _ = self;
            _ = plugin_manager;
            const scheduler = manager.getResource(zevy_ecs.Scheduler) orelse return error.MissingSchedulerResource;
            try scheduler.addStage(zevy_ecs.Stage(GuiStage));
            scheduler.addSystem(manager, zevy_ecs.Stage(zevy_ecs.Stages.Startup), ui.systems.startupUiSystem, ParamRegistry);
            scheduler.addSystem(manager, zevy_ecs.Stage(GuiStage), ui.systems.uiInputSystem, ParamRegistry);
            scheduler.addSystem(manager, zevy_ecs.Stage(GuiStage), ui.systems.flexLayoutSystem, ParamRegistry);
            scheduler.addSystem(manager, zevy_ecs.Stage(GuiStage), ui.systems.gridLayoutSystem, ParamRegistry);
            scheduler.addSystem(manager, zevy_ecs.Stage(zevy_ecs.Stages.PostDraw), ui.systems.uiRenderSystem, ParamRegistry);
        }
    };
}
