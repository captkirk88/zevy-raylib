const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const rl = @import("raylib");
const assets_plugin = @import("assets.plugin.zig");
const plugins = @import("plugins");

const RaylibPlugin = struct {
    const Self = @This();

    title: [:0]const u8,
    width: u32,
    height: u32,

    pub fn build(self: *Self, e: *zevy_ecs.Manager) !void {
        _ = e;
        const log = std.log.scoped(.zevy_raylib);
        rl.setTraceLogLevel(.warning);
        rl.initWindow(self.width, self.height, self.title);
        log.info("Initialized window: {s} ({d}x{d})", .{ self.title, self.width, self.height });
        rl.initAudioDevice();
        log.info("Audio device: {s}", .{if (rl.isAudioDeviceReady()) "Ready" else "Not Ready"});
        rl.setTargetFPS(500);
    }
};
