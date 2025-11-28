const std = @import("std");
const rl = @import("raylib");

const Frame = @import("../graphics/texture_atlas.zig").NamedFrame;
const input = @import("../input/input.zig");

pub const IconAtlas = struct {
    texture: rl.Texture,
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    owns_texture: bool,
    // Optional parsed input keys for each frame. When present, the array
    // will have the same length as `frames.items` and contain either a
    // parsed `input.InputKey` or `null` when a frame name couldn't be
    // parsed into an InputKey.
    parsed_keys: std.ArrayList(?input.InputKey),

    pub fn deinit(self: *IconAtlas) void {
        // Free parsed keys first
        self.parsed_keys.deinit(self.allocator);
        // Free duplicated frame name strings owned by the frames' allocator
        for (self.frames.items) |frame| {
            if (frame.name.len > 0) self.allocator.free(frame.name);
        }
        // Free frames array
        self.frames.deinit(self.allocator);
        if (self.owns_texture) {
            rl.unloadTexture(self.texture);
        }
    }

    pub fn frameCount(self: IconAtlas) usize {
        return self.frames.items.len;
    }
};
