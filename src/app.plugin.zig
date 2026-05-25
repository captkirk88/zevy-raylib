const std = @import("std");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const zevy_mem = @import("zevy_mem");
const zevy_reflect = @import("zevy_reflect");
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

pub const WindowOpts = struct {
    /// The title of the application window. This should be a short and descriptive name for your application, such as "My Game" or "Zevy App". The title is displayed in the title bar of the window and may also be used by the operating system to identify the application. It's important to choose a title that accurately represents your application and is easily recognizable to users.
    title: []const u8 = "Zevy App",
    /// The initial resolution of the application window. This should be set to a reasonable default that works well on most displays, such as 800x600 or 1280x720. You can also provide a method to calculate this based on the display's aspect ratio for better compatibility with different screen sizes. Keep in mind that users may want to resize the window, so it's important to handle resizing events properly in your application.
    resolution: DisplayResolution = .{ .width = 1280, .height = 720 },
    /// The target frames per second (FPS) for the application. This controls how often the main game loop updates and renders. A common target is 60 FPS, which provides smooth visuals on most displays. However, you may want to adjust this based on the performance characteristics of your application and the capabilities of the target hardware. Setting this too high may cause performance issues on lower-end devices, while setting it too low may result in choppy visuals.
    target_fps: i32 = 60,
    /// Whether to enable VSync. If enabled, the frame rate will be capped to the display's refresh rate, which can help reduce screen tearing and save power. However, it may introduce input latency and reduce frame rates on lower-end hardware. If disabled, the application will run at the target FPS specified by `target_fps`, but may experience screen tearing.
    vsync: bool = true,
    /// Whether to enable high DPI mode on supported platforms. This will make the window use the full resolution of high DPI displays, but may cause the UI to appear smaller if not properly scaled. If enabled, it's recommended to use `DisplayResolution.aspectRatio()` to calculate the initial window size based on the display's aspect ratio, and then scale it up for high DPI.
    high_dpi: bool = true,
    fullscreen_mode: FullScreenMode = .Windowed,
    /// Whether to run in headless mode. If enabled, the application will not initialize a window or audio device, allowing it to run in environments without a display (e.g., servers or automated testing). In headless mode, you should ensure that your application can function without relying on window or audio features, and that it can exit gracefully when needed.
    headless: bool = false,

    pub fn format(self: *const WindowOpts, w: *std.Io.Writer) void {
        w.print("WindowOpts {{\n", .{}) catch {};
        w.print("title: \"{s}\",\n", .{self.title}) catch {};
        w.print("resolution: {f},\n", .{self.resolution}) catch {};
        w.print("target_fps: {},\n", .{self.target_fps}) catch {};
        w.print("vsync: {},\n", .{self.vsync}) catch {};
        w.print("high_dpi: {},\n", .{self.high_dpi}) catch {};
        w.print("borderless: {},\n", .{self.borderless}) catch {};
        w.print("fullscreen: {},\n", .{self.fullscreen}) catch {};
        w.print("headless: {}\n", .{self.headless}) catch {};
        w.print("}}\n", .{}) catch {};
    }

    pub fn titleZ(self: *const WindowOpts, allocator: std.mem.Allocator) ![:0]u8 {
        return try allocator.dupeZ(u8, self.title);
    }
};

pub const DisplayResolution = struct {
    width: i32,
    height: i32,

    pub fn aspectRatio(self: DisplayResolution) f32 {
        return @floatFromInt(@divExact(self.width, self.height));
    }

    pub fn fromRaylib() DisplayResolution {
        return DisplayResolution{
            .width = rl.getScreenWidth(),
            .height = rl.getScreenHeight(),
        };
    }

    pub fn init(width: i32, height: i32) DisplayResolution {
        return DisplayResolution{
            .width = width,
            .height = height,
        };
    }

    pub fn initFromAspectRatio(aspect_ratio: f32, height: i32) DisplayResolution {
        return DisplayResolution{
            .width = @intCast(@as(i32, @intFromFloat(aspect_ratio)) * height),
            .height = height,
        };
    }

    pub fn initFromMonitor(monitor_index: i32) DisplayResolution {
        return DisplayResolution{
            .width = rl.getMonitorWidth(monitor_index),
            .height = rl.getMonitorHeight(monitor_index),
        };
    }

    pub fn scale(self: DisplayResolution, scale_factor: f32) DisplayResolution {
        return DisplayResolution{
            .width = @intCast(self.width * @as(i32, @intFromFloat(scale_factor))),
            .height = @intCast(self.height * @as(i32, @intFromFloat(scale_factor))),
        };
    }

    pub fn format(self: *const DisplayResolution, w: *std.Io.Writer) void {
        w.print("DisplayResolution {{\n", .{}) catch {};
        w.print("width: {d},\n", .{self.width}) catch {};
        w.print("height: {d},\n", .{self.height}) catch {};
        w.print("aspect_ratio: {d}\n", .{self.aspectRatio()}) catch {};
        w.print("}}", .{}) catch {};
    }
};

pub const FullScreenMode = enum {
    Exclusive,
    BorderlessWindowed,
    Windowed,
};

/// Raylib plugin for Zevy ECS
pub fn RaylibPlugin(comptime ParamRegistry: type) type {
    return struct {
        const Name: []const u8 = "RaylibPlugin";
        const Self = @This();
        /// Window Options
        window_opts: WindowOpts = .{},
        log_level: rl.TraceLogLevel = .info,
        /// Raylib log callback that redirects to zevy_raylib scoped logger
        raylib_logcallback: *const fn (c_int, [*c]const u8, raylib_log_callback.VaListParam) callconv(.c) void = raylib_log_callback.callback,

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

            var window_opts_change = zevy_reflect.Change(WindowOpts).init(self.window_opts);
            window_opts_change._prior_hash += 1; // Force changed state on startup to apply initial window options
            try e.addResourceRetained(zevy_reflect.Change(WindowOpts), window_opts_change);
            applyWindowOpts(&self.window_opts);

            sch.addSystem(e, zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Startup), startupRaylibSystem, ParamRegistry);

            SetTraceLogCallback(self.raylib_logcallback);
            rl.setTraceLogLevel(self.log_level);
            if (!self.window_opts.headless) {
                const title_z = try self.window_opts.titleZ(std.heap.page_allocator);
                defer std.heap.page_allocator.free(title_z);
                rl.initWindow(self.window_opts.resolution.width, self.window_opts.resolution.height, title_z);
                rl.initAudioDevice();
                if (self.window_opts.target_fps < 30) self.window_opts.target_fps = 30;
            } else {
                log.info("Running in headless mode: Window and audio device will not be initialized.", .{});
            }

            rl.setTargetFPS(self.window_opts.target_fps);
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator, ecs: *zevy_ecs.Manager) anyerror!void {
            // Do not close raylib here: plugin_manager.deinit() runs before
            // ecs.deinit(), and ECS-owned assets may still need a live GL/audio
            // context to unload safely.
            _ = ecs;
            _ = self;
        }
    };
}

// Extern functions
extern fn SetTraceLogCallback(callback: ?*const fn (c_int, [*c]const u8, raylib_log_callback.VaListParam) callconv(.c) void) void;

/// Raylib log callback that redirects to zevy_raylib scoped logger
const raylib_log_callback = struct {
    const c_stdio = @cImport({
        @cInclude("stdio.h");
    });
    pub const VaListParam = switch (@typeInfo(c_stdio.va_list)) {
        .array => |info| [*c]info.child,
        else => c_stdio.va_list,
    };

    extern fn vsnprintf(dst: [*c]u8, n: usize, format: [*c]const u8, args: VaListParam) callconv(.c) c_int;

    fn callback(log_level: c_int, format: [*c]const u8, args: VaListParam) callconv(.c) void {
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

const Commands = zevy_ecs.commands.Commands;
const ResMut = zevy_ecs.params.ResMut;

fn startupRaylibSystem(_: Commands, window_res: ResMut(zevy_reflect.Change(WindowOpts))) void {
    const window = window_res.get();
    if (window.isChanged()) {
        window.finish();
        const new_opts = window.get();
        applyWindowOpts(new_opts);
    }
}

fn applyWindowOpts(opts: *WindowOpts) void {
    const config_flags: rl.ConfigFlags = .{
        .vsync_hint = opts.vsync,
        .window_highdpi = opts.high_dpi,
    };

    if (!rl.isWindowReady()) {
        rl.setConfigFlags(config_flags);
        return;
    }

    switch (opts.fullscreen_mode) {
        .BorderlessWindowed => {
            // const monitor = rl.getCurrentMonitor();
            // const monitor_height = rl.getMonitorHeight(monitor);
            // const monitor_width = rl.getMonitorWidth(monitor);
            rl.toggleBorderlessWindowed();
        },
        .Windowed => {
            if (rl.isWindowFullscreen() or rl.isWindowMaximized()) {
                rl.toggleFullscreen();
            }
        },
        .Exclusive => {
            if (!rl.isWindowFullscreen()) {
                rl.toggleFullscreen();
            }
        },
    }
    rl.setWindowState(config_flags);
    const title_z = opts.titleZ(std.heap.page_allocator) catch {
        std.log.scoped(.zevy_raylib).warn("Failed to allocate window title, using fallback title.", .{});
        rl.setWindowTitle("Zevy App");
        rl.setWindowSize(opts.resolution.width, opts.resolution.height);
        return;
    };
    defer std.heap.page_allocator.free(title_z);
    rl.setWindowTitle(title_z);
    rl.setWindowSize(opts.resolution.width, opts.resolution.height);
}
