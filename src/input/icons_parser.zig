const std = @import("std");
const xml = @import("../io/xml.zig");
const TextureAtlas = @import("../graphics/texture_atlas.zig");
const NamedFrame = TextureAtlas.NamedFrame;

/// Parsed atlas data extracted from a TextureAtlas XML document.
pub const AtlasParseResult = struct {
    image_path: ?[]u8,
    frames: std.ArrayList(NamedFrame),
};

/// Parse a TextureAtlas-style XML document into frame data and the referenced image path.
/// Caller owns the returned buffers and must free them with `allocator`.
pub fn parseTextureAtlas(doc: *xml.XmlDocument, allocator: std.mem.Allocator) !AtlasParseResult {
    const rdr = try doc.reader();

    var frames = try std.ArrayList(NamedFrame).initCapacity(allocator, 16);
    var frames_owned: bool = true;
    defer if (frames_owned) frames.deinit(allocator);

    var image_path_rel: ?[]u8 = null;
    errdefer if (image_path_rel) |p| allocator.free(p);

    while (true) {
        const node = doc.readNode() catch |err| {
            frames.deinit(allocator);
            return err;
        };
        switch (node) {
            .eof => break,
            .element_start => {
                const element_name = rdr.elementName();
                if (std.mem.eql(u8, element_name, "TextureAtlas")) {
                    if (image_path_rel == null) {
                        const maybe_path = try doc.attributeValue("imagePath");
                        if (maybe_path) |path_slice| {
                            image_path_rel = try allocator.dupe(u8, path_slice);
                            if (image_path_rel) |p| {
                                const unescaped = try xml.unescapeXmlEntities(allocator, p);
                                allocator.free(p);
                                image_path_rel = unescaped;
                            }
                        }
                    }
                } else if (std.ascii.eqlIgnoreCase(element_name, "SubTexture")) {
                    const frame_name = try allocator.dupe(u8, try doc.requireAttributeValue("name"));
                    errdefer allocator.free(frame_name);
                    const frame_rect = TextureAtlas.FrameRect{
                        .x = try doc.parseAttributeInt(i32, "x"),
                        .y = try doc.parseAttributeInt(i32, "y"),
                        .w = try doc.parseAttributeInt(i32, "width"),
                        .h = try doc.parseAttributeInt(i32, "height"),
                    };
                    try frames.append(allocator, .{ .name = frame_name, .frame = frame_rect });
                    // ownership transferred to frames; prevent deferred free
                }
            },
            .element_end => {},
            else => {},
        }
    }

    frames_owned = false;
    return .{
        .image_path = image_path_rel,
        .frames = frames,
    };
}
