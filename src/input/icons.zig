const std = @import("std");
const rl = @import("raylib");

const xml = @import("../io/xml.zig");
const Assets = @import("../io/assets.zig").Assets;
const io_util = @import("../io/util.zig");
const atlas = @import("../graphics/texture_atlas.zig");
const TextureAtlas = atlas.TextureAtlas;
const FrameRect = atlas.FrameRect;
const io_types = @import("../io/types.zig");
const input = @import("../input/input.zig");
const icon_parser = @import("icons_parser.zig");

pub const AtlasParseResult = icon_parser.AtlasParseResult;
pub const parseTextureAtlas = icon_parser.parseTextureAtlas;

const ParseError = error{ MissingImagePath, InvalidTexture, UnsupportedScheme };
const IconFrame = @import("../graphics/texture_atlas.zig").NamedFrame;

const IconTextureAtlas = TextureAtlas(IconFrame);

pub const PromptType = enum {
    keyboardmouse,
    xbox,
    playstation,
    nintendoswitch,
    steamdeck,
};

pub const IconAtlas = io_types.IconAtlas;

fn parseAtlasXml(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !IconAtlas {
    // Resolve and parse the XML file, handling both file paths and scheme URIs
    var use_allocator: std.mem.Allocator = allocator;
    var document = if (assets) |a| blk: {
        use_allocator = a.allocator;
        var resolved = try a.resolve(allocator, xml_path);

        switch (resolved) {
            .file_path => |path| {
                const doc = try xml.XmlDocument.openReader(use_allocator, path, .{});
                resolved.deinit(allocator);
                break :blk doc;
            },
            .embedded_data => |data| {
                const doc = try xml.XmlDocument.initFromSlice(use_allocator, data, .{});
                break :blk doc;
            },
            .url => |_| {
                resolved.deinit(allocator);
                return ParseError.UnsupportedScheme;
            },
            .custom => |_| {
                resolved.deinit(allocator);
                return ParseError.UnsupportedScheme;
            },
        }
    } else try xml.XmlDocument.openReader(allocator, xml_path, .{});
    defer document.deinit();

    // Parse the XML document to extract frame data and image path
    const parsed = try icon_parser.parseTextureAtlas(&document, use_allocator);
    var frames = parsed.frames;
    const image_path_rel = parsed.image_path;

    // Guard against freeing frames if we return early
    var frames_owned: bool = true;
    defer if (frames_owned) {
        freeFrameNames(use_allocator, frames.items);
        frames.deinit(use_allocator);
    };

    const rel_path = image_path_rel orelse return ParseError.MissingImagePath;
    const parent_dir: ?[]const u8 = if (assets != null) null else std.fs.path.dirname(xml_path) orelse ".";

    var texture: *rl.Texture = undefined;
    if (assets) |a| {
        // Construct the final path/URI for the image by combining the directory of xml_path with the relative image path
        const base_uri = io_util.getDirectoryUri(xml_path);
        const final_uri = if (base_uri.len > 0)
            try std.mem.concat(use_allocator, u8, &[_][]const u8{ base_uri, rel_path })
        else
            try std.fs.path.join(use_allocator, &[_][]const u8{ parent_dir orelse ".", rel_path });
        defer use_allocator.free(final_uri);

        texture = try a.loadAssetNow(rl.Texture, final_uri, null);
        use_allocator.free(rel_path);
    } else {
        const image_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_dir orelse ".", rel_path });
        defer allocator.free(image_path);
        allocator.free(rel_path);
        texture = try allocator.create(rl.Texture);
        const image_path_z = try std.heap.c_allocator.dupeZ(u8, image_path);
        defer std.heap.c_allocator.free(image_path_z);
        texture.* = try rl.loadTexture(image_path_z);
        if (!rl.isTextureValid(texture.*)) {
            rl.unloadTexture(texture.*);
            allocator.destroy(texture);
            return ParseError.InvalidTexture;
        }
    }

    // Transfer ownership of frames to returned IconAtlas
    frames_owned = false;

    const iconAtlas = IconAtlas.init(
        allocator,
        texture,
        frames,
        (assets == null),
    );
    return iconAtlas;
}

pub fn parseKeyboardMouse(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !IconAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parseXbox(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !IconAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parsePlaystation(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !IconAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parseNintendoSwitch(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !IconAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parseSteamDeck(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !IconAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

fn freeFrameNames(allocator: std.mem.Allocator, frames: []const IconFrame) void {
    for (frames) |frame| allocator.free(frame.name);
}

test "parse keyboardmouse texture atlas" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Raylib must be initialised to load textures
    rl.initWindow(640, 480, "icons test");
    defer rl.closeWindow();

    const xml_path = "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml";
    // Use parseKeyboardMouse which properly handles embedded assets
    var pa = try parseKeyboardMouse(allocator, xml_path, &assets);
    defer pa.deinit();

    try testing.expect(pa.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.texture.*));
}

test "loadAssetNow IconAtlas from embedded path" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var assets = Assets.init(allocator);
    defer assets.deinit();

    // Raylib must be initialised to load textures
    rl.initWindow(640, 480, "icons test loadAssetNow");
    defer rl.closeWindow();

    // Test that assets.loadAssetNow works with embedded IconAtlas
    // This exercises the scheme-aware FileResolver for relative path resolution
    const xml_path = "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml";
    const pa = try assets.loadAssetNow(IconAtlas, xml_path, null);

    try testing.expect(pa.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.texture.*));
}

test "parse xbox texture atlas" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var assets = Assets.init(allocator);
    defer assets.deinit();

    rl.initWindow(640, 480, "icons test");
    defer rl.closeWindow();

    const xml_path = "embedded://Xbox Series/xbox-series_sheet_default.xml";
    var pa = try parseXbox(allocator, xml_path, &assets);
    defer pa.deinit();

    try testing.expect(pa.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.texture.*));
}

test "missing imagePath attribute returns error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a small temporary file without an imagePath attribute
    const temp_name = "tmp_no_image.xml";
    var file = try std.fs.cwd().createFile(temp_name, .{ .truncate = true });
    defer {
        _ = file.close();
        _ = std.fs.cwd().deleteFile(temp_name) catch {};
    }
    const contents = "<TextureAtlas></TextureAtlas>";
    try file.writeAll(contents);

    const result = parseKeyboardMouse(allocator, temp_name, null);
    try testing.expectError(ParseError.MissingImagePath, result);
}

test "parse keyboardmouse via Assets resolver (embedded://)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Setup assets so 'embedded://' scheme is registered
    var assets = Assets.init(allocator);
    defer assets.deinit();

    rl.initWindow(640, 480, "icons test");
    defer rl.closeWindow();

    const uri = "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml";
    var pa = try parseKeyboardMouse(assets.allocator, uri, &assets);
    defer pa.deinit();

    try testing.expect(pa.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.texture.*));
}

test "parse playstation via Assets resolver (embedded://)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var assets = Assets.init(allocator);
    defer assets.deinit();

    rl.initWindow(640, 480, "icons test");
    defer rl.closeWindow();

    const uri = "embedded://PlayStation Series/playstation-series_sheet_default.xml";
    var pa = try parsePlaystation(assets.allocator, uri, &assets);
    defer pa.deinit();

    try testing.expect(pa.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.texture.*));
}
