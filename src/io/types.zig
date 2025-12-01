const std = @import("std");
const rl = @import("raylib");

const Frame = @import("../graphics/texture_atlas.zig").NamedFrame;
const FrameRect = @import("../graphics/texture_atlas.zig").FrameRect;
const input_types = @import("../input/input_types.zig");
const KeyCode = input_types.KeyCode;
const MouseButton = input_types.MouseButton;

/// Represents a mapped input icon with frame indices for normal and outline variants
pub const InputIconMapping = struct {
    /// Frame index for the normal icon
    normal_index: ?usize = null,
    /// Frame index for the outline variant (if available)
    outline_index: ?usize = null,
};

pub const IconAtlas = struct {
    texture: *rl.Texture,
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    owns_texture: bool,
    /// KeyCode to frame index mappings (populated by processor)
    key_mappings: ?std.AutoHashMap(KeyCode, InputIconMapping) = null,
    /// MouseButton to frame index mappings (populated by processor)
    mouse_mappings: ?std.AutoHashMap(MouseButton, InputIconMapping) = null,

    pub fn init(allocator: std.mem.Allocator, texture: *rl.Texture, frames: std.ArrayList(Frame), owns_texture: bool) IconAtlas {
        return IconAtlas{
            .texture = texture,
            .frames = frames,
            .allocator = allocator,
            .owns_texture = owns_texture,
            .key_mappings = null,
            .mouse_mappings = null,
        };
    }

    pub fn deinit(self: *IconAtlas) void {
        // Free duplicated frame name strings owned by the frames' allocator
        for (self.frames.items) |frame| {
            if (frame.name.len > 0) self.allocator.free(frame.name);
        }
        // Free frames array
        self.frames.deinit(self.allocator);
        // Free mappings if they were created
        if (self.key_mappings) |*km| km.deinit();
        if (self.mouse_mappings) |*mm| mm.deinit();
        if (self.owns_texture) {
            rl.unloadTexture(self.texture.*);
            self.allocator.destroy(self.texture);
        }
    }

    pub fn frameCount(self: IconAtlas) usize {
        return self.frames.items.len;
    }

    /// Get the frame index for a keyboard key icon
    pub fn getKeyIcon(self: *const IconAtlas, key: KeyCode, outline: bool) ?usize {
        if (self.key_mappings) |km| {
            if (km.get(key)) |mapping| {
                return if (outline) mapping.outline_index else mapping.normal_index;
            }
        }
        return null;
    }

    /// Get the frame index for a mouse button icon
    pub fn getMouseIcon(self: *const IconAtlas, button: MouseButton, outline: bool) ?usize {
        if (self.mouse_mappings) |mm| {
            if (mm.get(button)) |mapping| {
                return if (outline) mapping.outline_index else mapping.normal_index;
            }
        }
        return null;
    }

    /// Get the frame rectangle for a keyboard key
    pub fn getKeyFrame(self: *const IconAtlas, key: KeyCode, outline: bool) ?FrameRect {
        if (self.getKeyIcon(key, outline)) |index| {
            if (index < self.frames.items.len) {
                return self.frames.items[index].frame;
            }
        }
        return null;
    }

    /// Get the frame rectangle for a mouse button
    pub fn getMouseFrame(self: *const IconAtlas, button: MouseButton, outline: bool) ?FrameRect {
        if (self.getMouseIcon(button, outline)) |index| {
            if (index < self.frames.items.len) {
                return self.frames.items[index].frame;
            }
        }
        return null;
    }
};
