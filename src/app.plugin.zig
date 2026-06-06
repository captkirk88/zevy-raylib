const std = @import("std");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const zevy_mem = @import("zevy_mem");
const zevy_reflect = @import("zevy_reflect");
const zevy_app = zevy_ecs.app;
const plugins = zevy_ecs.plugins;
const rl = @import("raylib");
const raygui = @import("raygui");
const zevy_raylib = @import("root.zig");
const ui = @import("gui/ui.zig");
const timing = @import("utils/timing.zig");
const assets_plugin = @import("assets.plugin.zig");

const main_thread_poll_stage = zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate)
    .add(50_000)
    .withOp(.sync);

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
pub const RaylibPlugin = struct {
    const Name: []const u8 = "RaylibPlugin";
    const Self = @This();
    /// Window Options
    window_opts: WindowOpts = .{},
    log_level: rl.TraceLogLevel = .info,
    /// Raylib log callback that redirects to zevy_raylib scoped logger
    raylib_logcallback: *const fn (c_int, [*c]const u8, raylib_log_callback.VaListParam) callconv(.c) void = raylib_log_callback.callback,

    pub fn build(self: *Self, app: *zevy_ecs.app.App, _: *plugins.PluginManager) anyerror!void {
        app
            .addResource(zevy_reflect.Change(WindowOpts), .initChanged(self.window_opts))
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreStartup),
                startupRaylib_System,
            )
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreUpdate),
                checkShouldClose_System,
            )
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.First),
                beginFrame_System,
            )
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Last),
                endFrame_System,
            )
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Exit),
                exittingSystem,
            )
            .done();

        SetTraceLogCallback(self.raylib_logcallback);
        rl.setTraceLogLevel(self.log_level);
    }

    pub fn deinit(_: *Self, _: std.mem.Allocator, _: *zevy_ecs.Manager) anyerror!void {
        // Do not close raylib here: plugin_manager.deinit() runs before
        // ecs.deinit(), and ECS-owned assets may still need a live GL/audio
        // context to unload safely.
    }
};

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

fn startupRaylib_System(commands: Commands, window_res: ResMut(zevy_reflect.Change(WindowOpts))) !void {
    const log = std.log.scoped(.zevy_raylib);
    const allocator = commands.allocator();
    const window = window_res.get();
    var window_opts: WindowOpts = undefined;
    if (window.isChanged()) {
        window.finish();
        window_opts = window.get().*;
        applyWindowOpts(&window_opts);
    }

    if (!window_opts.headless) {
        const title_z = try window_opts.titleZ(allocator);
        defer allocator.free(title_z);
        rl.initWindow(window_opts.resolution.width, window_opts.resolution.height, title_z);
        rl.initAudioDevice();
        rl.setExitKey(.escape);
        //if (window_opts.target_fps < 30) window_opts.target_fps = 30;
        //applyWindowOpts(&window_opts);
    } else {
        log.info("Running in headless mode: Window and audio device will not be initialized.", .{});
    }

    rl.setTargetFPS(window_opts.target_fps);

    const fixed_dt: f32 = 1.0 / 60.0; // 1/60 for physics/logic updates
    try commands.addResource(timing.FixedTimestepAccumulator, timing.FixedTimestepAccumulator.init(fixed_dt));
    try commands.addResource(timing.DeltaTime, .{ .value = fixed_dt });
}

fn checkShouldClose_System(commands: zevy_ecs.params.Commands, exitEvent_writer: zevy_ecs.params.EventWriter(zevy_app.ExitAppEvent)) void {
    if (zevy_raylib.shouldClose(commands.io(), null)) {
        exitEvent_writer.write(.Success);
    }
}

fn exittingSystem(exitEvent_reader: zevy_ecs.params.EventReader(zevy_app.ExitAppEvent)) void {
    const exitting = !exitEvent_reader.isEmpty();

    if (exitting) {
        if (zevy_raylib.rl.isAudioDeviceReady()) zevy_raylib.rl.closeAudioDevice();
        if (zevy_raylib.rl.isWindowReady()) zevy_raylib.rl.closeWindow();
    }
}

fn beginFrame_System() void {
    zevy_raylib.beginDrawing();
    zevy_raylib.clearBackground(rl.Color.black);
}

fn endFrame_System() void {
    zevy_raylib.endDrawing();
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
