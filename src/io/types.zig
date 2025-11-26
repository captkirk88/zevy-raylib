const std = @import("std");
const rl = @import("raylib");

const Frame = @import("../graphics/texture_atlas.zig").NamedFrame;

pub const IconAtlas = struct {
    texture: rl.Texture,
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    owns_texture: bool,

    pub fn deinit(self: *IconAtlas) void {
        // Free frames
        self.frames.deinit(self.allocator);
        if (self.owns_texture) {
            rl.unloadTexture(self.texture);
        }
    }

    pub fn frameCount(self: IconAtlas) usize {
        return self.frames.items.len;
    }
};
