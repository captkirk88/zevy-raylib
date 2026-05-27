const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const input = @import("../input/root.zig");
const icons = @import("icons.zig");
const Assets = @import("../io/assets.zig").Assets;

const SKIP_IN_DEBUG = true;

const is_debug = @import("builtin").mode == .Debug;
const should_skip = if (SKIP_IN_DEBUG and is_debug) true else false;

/// Watchdog timeout: kill the process if a test takes longer than this many seconds.
/// Must be > render loop max_duration_ms (5s) + setup overhead (~2s), so 15s gives
/// plenty of headroom while still bounding a genuine hang.
const TEST_SKIP_TIMEOUT_SECS = 15;
const TEST_TIMEOUT_POLL_MS: u64 = 100;

fn sleepForTimeoutPoll(ms: u64) void {
    switch (builtin.os.tag) {
        .windows => {
            const delay_interval: std.os.windows.LARGE_INTEGER =
                -@as(std.os.windows.LARGE_INTEGER, @intCast(ms)) * (std.time.ns_per_ms / 100);
            _ = std.os.windows.ntdll.NtDelayExecution(.TRUE, &delay_interval);
        },
        else => {
            const sec_type = @typeInfo(std.posix.timespec).@"struct".fields[0].type;
            const nsec_type = @typeInfo(std.posix.timespec).@"struct".fields[1].type;

            var timespec = std.posix.timespec{
                .sec = @as(sec_type, @intCast(@divFloor(ms, std.time.ms_per_s))),
                .nsec = @as(nsec_type, @intCast(@mod(ms, std.time.ms_per_s) * std.time.ns_per_ms)),
            };

            _ = std.posix.system.nanosleep(&timespec, &timespec);
        },
    }
}

/// Watchdog guard: spawns a background thread that panics if the test does not
/// complete (i.e. call `deinit`) within TEST_SKIP_TIMEOUT_SECS seconds.
/// This prevents render-loop bugs or GPU stalls from hanging the test suite
/// forever.
const TimeoutGuard = struct {
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    fn start(self: *TimeoutGuard, test_name: []const u8) !void {
        self.thread = try std.Thread.spawn(.{}, watchdogMain, .{ &self.stop, test_name });
    }

    fn deinit(self: *TimeoutGuard) void {
        self.stop.store(true, .release);
        if (self.thread) |thread| thread.join();
        self.thread = null;
    }

    fn watchdogMain(stop: *std.atomic.Value(bool), test_name: []const u8) void {
        var remaining_ms: u64 = TEST_SKIP_TIMEOUT_SECS * std.time.ms_per_s;

        while (!stop.load(.acquire) and remaining_ms > 0) {
            const sleep_ms = @min(remaining_ms, TEST_TIMEOUT_POLL_MS);
            sleepForTimeoutPoll(sleep_ms);
            remaining_ms -= sleep_ms;
        }

        if (!stop.load(.acquire)) {
            // Use process.exit instead of std.debug.panic to avoid Windows crash
            // dialogs from background threads (which block test-runner indefinitely).
            std.debug.print("TIMEOUT: Render test timed out after {d}s: {s}\n", .{ TEST_SKIP_TIMEOUT_SECS, test_name });
            std.process.exit(1);
        }
    }
};

fn initTest(name: [:0]const u8) anyerror!Assets {
    rl.initWindow(1200, 800, name);
    // Disable ESC-closes-window so a key press in a previous test does not
    // cause windowShouldClose() to return true immediately in the next test.
    rl.setExitKey(.null);
    const allocator = std.testing.allocator;
    return Assets.init(allocator);
}

fn deinitTest(assets: *Assets) void {
    assets.deinit();
    rl.closeWindow();
}

fn testRenderLoop(_: *Assets, prompt_atlas: *icons.IconAtlas, title: [:0]const u8) anyerror!void {
    const start = @as(i64, @intFromFloat(rl.getTime() * @as(f64, @floatFromInt(std.time.ms_per_s))));
    const max_duration_ms = 5 * std.time.ms_per_s; // Run for at most 5 seconds from start
    var frame_text_buffer: [64:0]u8 = undefined;
    var debug_buffer: [128:0]u8 = undefined;

    // Setup camera for panning
    var camera: rl.Camera2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1.0,
    };

    while (!rl.windowShouldClose()) {
        if (!rl.isWindowReady()) break;
        const now = @as(i64, @intFromFloat(rl.getTime() * @as(f64, @floatFromInt(std.time.ms_per_s))));

        // Absolute timeout from start — ensures the loop always exits in bounded
        // time regardless of mouse/keyboard state carried over from a previous test.
        if (now - start >= max_duration_ms) break;

        // Handle camera panning with mouse
        if (input.getMousePosition() != null and rl.isMouseButtonDown(.left)) {
            const mouse_delta = rl.getMouseDelta();
            camera.target.x -= mouse_delta.x / camera.zoom;
            camera.target.y -= mouse_delta.y / camera.zoom;
        }

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        // Draw UI (not affected by camera)
        rl.drawText(title, 20, 20, 24, rl.Color.white);

        const frame_text = std.fmt.bufPrintZ(&frame_text_buffer, "Frames: {d}", .{prompt_atlas.frameCount()}) catch "Error";
        rl.drawText(frame_text, 20, 50, 20, rl.Color.white);

        const texture_info = std.fmt.bufPrintZ(&debug_buffer, "Texture: {d}x{d}", .{ prompt_atlas.texture.width, prompt_atlas.texture.height }) catch "N/A";
        rl.drawText(texture_info, 20, 75, 16, rl.Color.white);

        rl.drawFPS(1200 - 100, 20);

        // Draw panned content inside camera
        rl.beginMode2D(camera);

        var frame_index: usize = 0;
        var x: i32 = 20;
        var y: i32 = 100;
        const cols = 10;
        const frame_size: i32 = 48;
        const cell_padding: i32 = 8;
        const padding: i32 = 4;
        const label_font_size: i32 = 12;

        for (prompt_atlas.frames.items) |frame| {
            rl.drawTextureRec(
                prompt_atlas.texture.*,
                .{
                    .x = @floatFromInt(@as(i32, @intCast(frame.frame.x))),
                    .y = @floatFromInt(@as(i32, @intCast(frame.frame.y))),
                    .width = @floatFromInt(@as(i32, @intCast(frame.frame.w))),
                    .height = @floatFromInt(@as(i32, @intCast(frame.frame.h))),
                },
                .{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
                rl.Color.white,
            );

            var name_buffer: [64:0]u8 = undefined;
            const name_z = std.fmt.bufPrintZ(&name_buffer, "{s}", .{frame.name}) catch "frame";

            const text_width: i32 = rl.measureText(name_z, @intCast(label_font_size));
            const cell_width: i32 = @max(frame_size, text_width) + cell_padding * 2;
            const label_x = x + @divTrunc(cell_width - text_width, 2);
            rl.drawText(name_z, label_x, y + frame_size + 4, @intCast(label_font_size), rl.Color.gray);

            frame_index += 1;
            x += cell_width + padding;

            if (frame_index % cols == 0) {
                x = 20;
                y += frame_size + label_font_size + cell_padding + padding * 2;
            }
        }

        rl.endMode2D();

        rl.endDrawing();
    }
}

test "Render Keyboard & Mouse Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Keyboard & Mouse Icons");
    defer timeout_guard.deinit();

    var assets = try initTest("Keyboard & Mouse Icons");
    defer deinitTest(&assets);

    var atlas = try icons.parseKeyboardMouse(
        assets.allocator,
        "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml",
        &assets,
    );
    defer atlas.deinit();
    try atlas.populateKeyboardMappings();

    try testRenderLoop(&assets, &atlas, "Keyboard & Mouse Icons");
}

test "Render Xbox Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Xbox Icons");
    defer timeout_guard.deinit();

    var assets = try initTest("Xbox Icons");
    defer deinitTest(&assets);

    var atlas = try icons.parseXbox(
        assets.allocator,
        "embedded://Xbox Series/xbox-series_sheet_default.xml",
        &assets,
    );
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "Xbox Icons");
}

test "Render PlayStation Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render PlayStation Icons");
    defer timeout_guard.deinit();

    var assets = try initTest("PlayStation Icons");
    defer deinitTest(&assets);

    var atlas = try icons.parsePlaystation(
        assets.allocator,
        "embedded://PlayStation Series/playstation-series_sheet_default.xml",
        &assets,
    );
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "PlayStation Icons");
}

test "Render Nintendo Switch Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Nintendo Switch Icons");
    defer timeout_guard.deinit();

    var assets = try initTest("Nintendo Switch Icons");
    defer deinitTest(&assets);

    var atlas = try icons.parseNintendoSwitch(
        assets.allocator,
        "embedded://Nintendo Switch 2/nintendo-switch-2_sheet_default.xml",
        &assets,
    );
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "Nintendo Switch Icons");
}

test "Render Steam Deck Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var timeout_guard: TimeoutGuard = .{};
    try timeout_guard.start("Render Steam Deck Icons");
    defer timeout_guard.deinit();

    var assets = try initTest("Steam Deck Icons");
    defer deinitTest(&assets);

    var atlas = try icons.parseSteamDeck(
        assets.allocator,
        "embedded://Steam Deck/steam-deck_sheet_default.xml",
        &assets,
    );
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "Steam Deck Icons");
}
