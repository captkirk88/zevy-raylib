const std = @import("std");
const rl = @import("raylib");
const input = @import("../input/input.zig");
const icons = @import("icons.zig");
const Assets = @import("../io/assets.zig").Assets;

const SKIP_IN_DEBUG = true;

const is_debug = @import("builtin").mode == .Debug;
const should_skip = if (SKIP_IN_DEBUG and is_debug) true else false;

fn initTest(name: [:0]const u8) anyerror!Assets {
    rl.initWindow(1200, 800, name);
    const allocator = std.testing.allocator;
    return Assets.init(allocator);
}

fn deinitTest(assets: *Assets) void {
    assets.deinit();
    rl.closeWindow();
}

fn testRenderLoop(_: *Assets, prompt_atlas: *icons.IconAtlas, title: [:0]const u8) anyerror!void {
    const start = std.time.milliTimestamp();
    const max_duration_ms = 5 * std.time.ms_per_s; // Run for 5 seconds
    var frame_text_buffer: [64:0]u8 = undefined;
    var debug_buffer: [128:0]u8 = undefined;
    var last_activity_time = start;

    // Setup camera for panning
    var camera: rl.Camera2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1.0,
    };

    while (!rl.windowShouldClose()) {
        const now = std.time.milliTimestamp();

        // Handle camera panning with mouse
        if (input.getMousePosition() != null and rl.isMouseButtonDown(.left)) {
            last_activity_time = now;
            const mouse_delta = rl.getMouseDelta();
            camera.target.x -= mouse_delta.x / camera.zoom;
            camera.target.y -= mouse_delta.y / camera.zoom;
        }

        // Check if enough time has passed without activity
        if (now - last_activity_time >= max_duration_ms) break;

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
            const label_x = x + @divExact(cell_width - text_width, 2);
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

    var assets = try initTest("Keyboard & Mouse Icons");
    defer deinitTest(&assets);

    const uri = "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml";
    var atlas = try icons.parseKeyboardMouse(assets.allocator, uri, &assets);
    defer atlas.deinit();
    try atlas.populateKeyboardMappings();

    try testRenderLoop(&assets, &atlas, "Keyboard & Mouse Icons");
}

test "Render Xbox Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var assets = try initTest("Xbox Icons");
    defer deinitTest(&assets);

    const uri = "embedded://Xbox Series/xbox-series_sheet_default.xml";
    var atlas = try icons.parseXbox(assets.allocator, uri, &assets);
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "Xbox Icons");
}

test "Render PlayStation Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var assets = try initTest("PlayStation Icons");
    defer deinitTest(&assets);

    const uri = "embedded://PlayStation Series/playstation-series_sheet_default.xml";
    var atlas = try icons.parsePlaystation(assets.allocator, uri, &assets);
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "PlayStation Icons");
}

test "Render Nintendo Switch Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var assets = try initTest("Nintendo Switch Icons");
    defer deinitTest(&assets);

    const uri = "embedded://Nintendo Switch 2/nintendo-switch-2_sheet_default.xml";
    var atlas = try icons.parseNintendoSwitch(assets.allocator, uri, &assets);
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "Nintendo Switch Icons");
}

test "Render Steam Deck Icons" {
    if (should_skip) {
        return error.SkipZigTest;
    }

    var assets = try initTest("Steam Deck Icons");
    defer deinitTest(&assets);

    const uri = "embedded://Steam Deck/steam-deck_sheet_default.xml";
    var atlas = try icons.parseSteamDeck(assets.allocator, uri, &assets);
    defer atlas.deinit();

    try testRenderLoop(&assets, &atlas, "Steam Deck Icons");
}
