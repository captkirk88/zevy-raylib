const std = @import("std");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const zevy_mem = @import("zevy_mem");
const plugins = @import("plugins");
const rl = @import("raylib");
const raygui = @import("raygui");

const ui = @import("gui/ui.zig");
const assets_plugin = @import("assets.plugin.zig");

/// Event emitted when the application is going to exit
pub const ExitAppEvent = struct {};

/// Raylib plugin for Zevy ECS
pub fn RaylibPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Self = @This();
        /// Window title
        title: [:0]const u8,
        /// Window width
        width: i32,
        /// Window height
        height: i32,
        /// Target FPS for Raylib
        target_fps: i32 = 60,
        /// Raylib log level
        log_level: rl.TraceLogLevel = .warning,
        /// If true, Raylib window and audio device will not be initialized
        headless: bool = false,
        /// Raylib log callback that redirects to zevy_raylib scoped logger
        raylib_logcallback: *const fn (c_int, [*c]const u8, [*c]u8) callconv(.c) void = raylib_log_callback.callback,

        pub fn build(self: *Self, e: *zevy_ecs.Manager, _: *plugins.PluginManager) !void {
            const log = std.log.scoped(.zevy_raylib);
            const sch = try e.getOrAddResource(zevy_ecs.schedule.Scheduler, try zevy_ecs.schedule.Scheduler.init(e.allocator), null);

            try sch.registerEvent(
                e,
                ExitAppEvent,
                ParamRegistry,
            );

            SetTraceLogCallback(self.raylib_logcallback);
            rl.setTraceLogLevel(self.log_level);
            if (!self.headless) {
                rl.initWindow(self.width, self.height, self.title);
                log.info("Initialized window: {s} ({d}x{d})", .{ self.title, self.width, self.height });
                rl.initAudioDevice();
                if (rl.isAudioDeviceReady()) {
                    log.info("Audio device initialized", .{});
                } else {
                    log.err("Failed to initialize audio device", .{});
                }

                if (self.target_fps < 30) self.target_fps = 30;
                rl.setTargetFPS(self.target_fps);
            }
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, ecs: *zevy_ecs.Manager) void {
            // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
            const log = std.log.scoped(.zevy_raylib);
            _ = ecs;
            if (!self.headless) {
                rl.closeAudioDevice();
                if (!rl.isAudioDeviceReady()) log.info("Audio device closed", .{}) else log.err("Audio device failed to close", .{});
                rl.closeWindow();
                if (!rl.isWindowReady()) log.info("Window closed", .{}) else log.err("Window failed to close", .{});
            }
        }
    };
}

// const rlraw = @cImport({
//     @cInclude("raylib.h");
// });

// Extern functions
extern fn SetTraceLogCallback(callback: ?*const fn (c_int, [*c]const u8, [*c]u8) callconv(.c) void) void;

/// Raylib log callback that redirects to zevy_raylib scoped logger
const raylib_log_callback = struct {
    const c_stdio = @cImport({
        @cInclude("stdio.h");
    });

    fn callback(log_level: c_int, format: [*c]const u8, args: c_stdio.va_list) callconv(.c) void {
        if (format == null) return;
        var buf: [1024:0]u8 = undefined;
        _ = c_stdio.vsprintf(&buf, format, args);
        const message = std.mem.span(@as([*:0]const u8, &buf));

        const raylib_log_level: rl.TraceLogLevel = @enumFromInt(log_level);
        const level: std.log.Level = switch (raylib_log_level) {
            .trace, .debug => .debug,
            .info => .info,
            .warning => .warn,
            .err, .fatal => .err,
            else => .info,
        };

        const log = std.log.scoped(.zevy_raylib);
        switch (level) {
            .debug => log.debug("{s}", .{message}),
            .info => log.info("{s}", .{message}),
            .warn => log.warn("{s}", .{message}),
            .err => log.err("{s}", .{message}),
        }
    }
};
