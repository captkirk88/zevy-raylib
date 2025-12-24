const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");
const rl = @import("raylib");
const raygui = @import("raygui");

const ui = @import("gui/ui.zig");
const assets_plugin = @import("assets.plugin.zig");

/// Event emitted when the application is going to exit
pub const ExitAppEvent = struct {};

pub fn RaylibPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Self = @This();

        title: [:0]const u8,
        width: i32,
        height: i32,
        target_fps: i32 = 60,
        log_level: rl.TraceLogLevel = .warning,
        headless: bool = false,

        pub fn build(self: *Self, e: *zevy_ecs.Manager, _: *plugins.PluginManager) !void {
            const log = std.log.scoped(.zevy_raylib);
            const sch = try e.getOrAddResource(zevy_ecs.schedule.Scheduler, try zevy_ecs.schedule.Scheduler.init(e.allocator), null);

            try sch.registerEvent(
                e,
                ExitAppEvent,
                ParamRegistry,
            );

            rl.setTraceLogLevel(self.log_level);
            if (!self.headless) {
                rl.initWindow(self.width, self.height, self.title);
                log.info("Initialized window: {s} ({d}x{d})", .{ self.title, self.width, self.height });
                rl.initAudioDevice();
                log.info("Audio device: {s}", .{if (rl.isAudioDeviceReady()) "Ready" else "Not Ready"});

                if (self.target_fps < 30) self.target_fps = 30;
                rl.setTargetFPS(self.target_fps);
            }
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, ecs: *zevy_ecs.Manager) void {
            const log = std.log.scoped(.zevy_raylib);
            _ = ecs;
            if (!self.headless) {
                rl.closeAudioDevice();
                if (!rl.isAudioDeviceReady()) log.info("Audio device closed", .{}) else log.err("Audio device failed to close", .{});
                rl.closeWindow();
                if (!rl.isWindowReady()) log.info("Window closed", .{}) else log.err("Window failed to close", .{});
            }
        }

        pub fn setWidth(self: *Self, width: i32) void {
            self.width = width;
            rl.setWindowSize(self.width, self.height);
        }

        pub fn setHeight(self: *Self, height: i32) void {
            self.height = height;
            rl.setWindowSize(self.width, self.height);
        }

        pub fn setTargetFPS(self: *Self, fps: i32) void {
            self.target_fps = fps;
            rl.setTargetFPS(self.target_fps);
        }

        pub fn setLevel(self: *Self, level: rl.TraceLogLevel) void {
            self.log_level = level;
            rl.setTraceLogLevel(self.log_level);
        }

        pub fn setTitle(self: *Self, title: [:0]const u8) void {
            self.title = title;
            rl.setWindowTitle(self.title);
        }
    };
}
