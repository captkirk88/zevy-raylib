const std = @import("std");
const rl = @import("raylib");

const Frame = @import("../graphics/texture_atlas.zig").NamedFrame;
const input = @import("../input/input.zig");

pub const IconAtlas = struct {
    texture: *rl.Texture,
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    owns_texture: bool,

    pub fn init(allocator: std.mem.Allocator, texture: *rl.Texture, frames: std.ArrayList(Frame), owns_texture: bool) IconAtlas {
        return IconAtlas{
            .texture = texture,
            .frames = frames,
            .allocator = allocator,
            .owns_texture = owns_texture,
        };
    }

    pub fn deinit(self: *IconAtlas) void {
        // Free duplicated frame name strings owned by the frames' allocator
        for (self.frames.items) |frame| {
            if (frame.name.len > 0) self.allocator.free(frame.name);
        }
        // Free frames array
        self.frames.deinit(self.allocator);
        if (self.owns_texture) {
            rl.unloadTexture(self.texture.*);
            self.allocator.destroy(self.texture);
        }
    }

    pub fn frameCount(self: IconAtlas) usize {
        return self.frames.items.len;
    }
};
