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
        const is_testing = @import("builtin").is_test;
        _ = is_testing;
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
        const is_testing = @import("builtin").is_test;
        _ = self;
        _ = ecs;
        rl.closeAudioDevice();
        rl.closeWindow();
        if (is_testing) std.debug.print("Deinitialized Raylib window and audio device\n", .{});
    }
};
