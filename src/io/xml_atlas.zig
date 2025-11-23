const std = @import("std");
const rl = @import("raylib");

const Frame = @import("../graphics/texture_atlas.zig").NamedFrame;

pub const XmlAtlas = struct {
    texture: rl.Texture,
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    /// True when this XmlAtlas loader allocated/owns the backing texture.
    /// When the texture is managed by the texture AssetManager, this will be false
    /// and deinit will not unload the texture (Assets owns it).
    owns_texture: bool,

    pub fn deinit(self: *XmlAtlas) void {
        // Free frames
        self.frames.deinit(self.allocator);
        if (self.owns_texture) {
            rl.unloadTexture(self.texture);
        }
    }

    pub fn frameCount(self: XmlAtlas) usize {
        return self.frames.items.len;
    }
};
