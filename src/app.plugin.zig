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
pub const ExitAppEvent = enum(u8) {
    Success = 0,
    Error = 1,
};

/// Raylib plugin for Zevy ECS
pub fn RaylibPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Name: []const u8 = "RaylibPlugin";
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

        pub fn build(self: *Self, e: *zevy_ecs.Manager, _: *plugins.PluginManager) anyerror!void {
            const log = std.log.scoped(.zevy_raylib);
            const sch_ref = try e.getOrAddResource(zevy_ecs.schedule.Scheduler, try zevy_ecs.schedule.Scheduler.init(e.allocator), null);
            defer sch_ref.deinit();
            var sch_guard = sch_ref.lockWrite();
            defer sch_guard.deinit();
            const sch = sch_guard.get();

            try sch.registerEvent(
                e,
                ExitAppEvent,
                ParamRegistry,
            );

            SetTraceLogCallback(self.raylib_logcallback);
            rl.setTraceLogLevel(self.log_level);
            if (!self.headless) {
                rl.initWindow(self.width, self.height, self.title);
                rl.initAudioDevice();

                if (self.target_fps < 30) self.target_fps = 30;
                rl.setTargetFPS(self.target_fps);
            } else {
                log.info("Running in headless mode: window and audio device initialization skipped", .{});
                if (self.target_fps < 1) self.target_fps = 1;
                // In headless mode, we can still use Raylib's timing functions for a consistent update loop, even though we won't be rendering or producing audio.
                rl.setTargetFPS(self.target_fps);
            }
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, ecs: *zevy_ecs.Manager) anyerror!void {
            // Do not manually deinit ECS-managed resources here unless they have a different func name for deinit: the ECS manager owns resource lifetimes and will deinit them during `Manager.deinit()`.
            _ = ecs;
            if (!self.headless) {
                rl.closeAudioDevice();
                rl.closeWindow();
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

    extern fn vsnprintf(dst: [*c]u8, n: usize, format: [*c]const u8, args: c_stdio.va_list) callconv(.c) c_int;

    fn callback(log_level: c_int, format: [*c]const u8, args: c_stdio.va_list) callconv(.c) void {
        if (format == null) return;
        var buf: [1024:0]u8 = undefined;
        _ = vsnprintf(&buf, buf.len, format, args);
        const message = std.mem.span(@as([*:0]const u8, &buf));

        const raylib_log_level: rl.TraceLogLevel = @enumFromInt(log_level);
        const level: std.log.Level = switch (raylib_log_level) {
            .trace, .debug => .debug,
            .info => .info,
            .warning => .warn,
            .err, .fatal => .err,
            else => .debug,
        };

        const log = std.log.scoped(.raylib);
        switch (level) {
            .debug => log.debug("{s}", .{message}),
            .info => log.info("{s}", .{message}),
            .warn => log.warn("{s}", .{message}),
            .err => log.err("{s}", .{message}),
        }
    }
};
