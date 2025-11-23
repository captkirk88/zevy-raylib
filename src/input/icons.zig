const std = @import("std");
const rl = @import("raylib");

const xml = @import("../io/xml.zig");
const Assets = @import("../io/assets.zig").Assets;
const atlas = @import("../graphics/texture_atlas.zig");
const TextureAtlas = atlas.TextureAtlas;
const FrameRect = atlas.FrameRect;

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

pub const PromptAtlas = struct {
    atlas: IconTextureAtlas,
    // When the atlas is produced from a named asset manager, the texture
    // will be owned by the Assets system. In that case we must not unload
    // the texture when deinitializing this PromptAtlas. Set `owned` to
    // true when Xml parsing returns an atlas we created/own.
    owned: bool,

    pub fn deinit(self: *PromptAtlas) void {
        // Free the duplicated frame name strings owned by atlas.allocator
        freeFrameNames(self.atlas.allocator, self.atlas.frames.items);
        // Always free the frames array itself
        self.atlas.frames.deinit(self.atlas.allocator);

        // Only unload the texture if we own it
        if (self.owned) {
            rl.unloadTexture(self.atlas.texture);
        }
    }
};

fn parseAtlasXml(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !PromptAtlas {
    // If an Assets pointer is provided, resolve the xml_path using its registry
    var use_allocator: std.mem.Allocator = allocator;
    var document = if (assets) |a| blk: {
        use_allocator = a.allocator;
        var resolved = try a.resolve(allocator, xml_path);

        switch (resolved) {
            .file_path => |path| {
                // path is owned by assets.allocator; open the file and then free
                const doc = try xml.XmlDocument.openReader(use_allocator, path, .{});
                resolved.deinit(allocator);
                break :blk doc;
            },
            .embedded_data => |data| {
                // data is allocated by assets.allocator; give ownership to XmlDocument
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

    // If we're given an Assets pointer and there's a registered XmlAtlas
    // manager, prefer to load the parsed atlas via the asset system so we don't
    // duplicate parsing logic. We skip loader-based loading for embedded assets
    // since they can't find supplemental image files in the embedded namespace.
    if (assets) |a| {
        const XmlAtlas = @import("../io/xml_atlas.zig").XmlAtlas;

        // Only try loader-based loading for non-embedded assets
        var check_resolved = try a.resolve(allocator, xml_path);
        const is_embedded = switch (check_resolved) {
            .embedded_data => true,
            else => false,
        };
        check_resolved.deinit(allocator);

        if (!is_embedded and a.hasLoader(XmlAtlas)) {
            // Try to load via XmlAtlasLoader for non-embedded assets
            if (a.loadAssetNow(XmlAtlas, xml_path, null)) |asset_atlas| {
                // Copy the frames into an IconTextureAtlas owned by use_allocator.
                var frames = try std.ArrayList(IconFrame).initCapacity(use_allocator, asset_atlas.frameCount());
                errdefer frames.deinit(use_allocator);

                for (asset_atlas.frames.items) |f| {
                    const name_copy = try use_allocator.dupe(u8, f.name);
                    try frames.append(use_allocator, .{ .name = name_copy, .frame = f.frame });
                }

                // Build PromptAtlas: we do NOT own the texture (Assets manages it)
                return PromptAtlas{
                    .atlas = .{
                        .texture = asset_atlas.texture,
                        .frames = frames,
                        .allocator = use_allocator,
                    },
                    .owned = false,
                };
            } else |_| {
                // If XmlAtlasLoader failed, fall through to manual parsing
            }
        }
    } // Use the shared XmlDocument parsing helper which returns imagePath and
    // an ArrayList of NamedFrame entries allocated with `use_allocator`.
    const parsed = try document.parseTextureAtlas(use_allocator);
    var frames = parsed.frames;
    const image_path_rel = parsed.image_path;
    // ensure frames get freed if we return early
    var frames_owned: bool = true;
    defer if (frames_owned) {
        freeFrameNames(use_allocator, frames.items);
        frames.deinit(use_allocator);
    };

    const rel_path = image_path_rel orelse return ParseError.MissingImagePath;
    const parent_dir: ?[]const u8 = if (assets != null) null else std.fs.path.dirname(xml_path) orelse ".";

    var texture: rl.Texture = undefined;
    if (assets) |a| {
        // Build a uri relative to xml_path when xml_path contains a scheme
        const scheme_pos = std.mem.indexOf(u8, xml_path, "://");
        const has_scheme = scheme_pos != null;
        var base_uri: []const u8 = "";
        if (has_scheme) {
            // Find the last slash in xml_path, if present
            var last: ?usize = null;
            var i: usize = xml_path.len;
            while (i > 0) : (i -= 1) {
                if (xml_path[i - 1] == '/') {
                    last = i - 1;
                    break;
                }
            }
            if (last) |idx| base_uri = xml_path[0 .. idx + 1];
        }

        const final_uri = if (base_uri.len > 0) try std.mem.concat(use_allocator, u8, &[_][]const u8{ base_uri, rel_path }) else try std.fs.path.join(use_allocator, &[_][]const u8{ parent_dir orelse ".", rel_path });
        defer use_allocator.free(final_uri);

        texture = try a.loadAssetNow(rl.Texture, final_uri, null);
        use_allocator.free(rel_path);
    } else {
        const image_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_dir orelse ".", rel_path });
        defer allocator.free(image_path);
        allocator.free(rel_path);

        const image_path_z = try std.heap.c_allocator.dupeZ(u8, image_path);
        defer std.heap.c_allocator.free(image_path_z);
        texture = try rl.loadTexture(image_path_z);
        if (!rl.isTextureValid(texture)) {
            rl.unloadTexture(texture);
            return ParseError.InvalidTexture;
        }
    }
    // We've transferred ownership of frames to the returned PromptAtlas, so
    // prevent the defer from freeing them.
    frames_owned = false;

    if (!rl.isTextureValid(texture)) {
        rl.unloadTexture(texture);
        return ParseError.InvalidTexture;
    }

    return PromptAtlas{
        .atlas = .{
            .texture = texture,
            .frames = frames,
            .allocator = use_allocator,
        },
        .owned = true,
    };
}

pub fn parseKeyboardMouse(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !PromptAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parseXbox(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !PromptAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parsePlaystation(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !PromptAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parseNintendoSwitch(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !PromptAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

pub fn parseSteamDeck(allocator: std.mem.Allocator, xml_path: []const u8, assets: ?*Assets) !PromptAtlas {
    return parseAtlasXml(allocator, xml_path, assets);
}

fn freeFrameNames(allocator: std.mem.Allocator, frames: []const IconFrame) void {
    for (frames) |frame| allocator.free(frame.name);
}

test "parse keyboardmouse texture atlas" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Raylib must be initialised to load textures
    rl.initWindow(640, 480, "icons test");
    defer rl.closeWindow();

    const xml_path = "embedded_assets/Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml";
    var pa = try parseKeyboardMouse(allocator, xml_path, null);
    defer pa.deinit();

    try testing.expect(pa.atlas.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.atlas.texture));
}

test "parse xbox texture atlas" {
    const testing = std.testing;
    const allocator = testing.allocator;

    rl.initWindow(640, 480, "icons test");
    defer rl.closeWindow();

    const xml_path = "embedded_assets/Xbox Series/xbox-series_sheet_default.xml";
    var pa = try parseXbox(allocator, xml_path, null);
    defer pa.deinit();

    try testing.expect(pa.atlas.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.atlas.texture));
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

    try testing.expect(pa.atlas.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.atlas.texture));
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

    try testing.expect(pa.atlas.frameCount() > 0);
    try testing.expect(rl.isTextureValid(pa.atlas.texture));
}
