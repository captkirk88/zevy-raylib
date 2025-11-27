const std = @import("std");
const rl = @import("raylib");

pub const FrameRect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

pub fn TextureAtlas(comptime FrameDataType: type) type {
    if (@hasField(FrameDataType, "frame") == false) {
        @compileError(std.fmt.comptimePrint(
            "type {s} must have field 'frame' of type FrameRect",
            .{@typeName(FrameDataType)},
        ));
    }

    return struct {
        texture: rl.Texture2D,
        frames: std.ArrayList(FrameDataType),
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Self) void {
            rl.unloadTexture(self.texture);
            self.frames.deinit(self.allocator);
        }

        /// Get the frame rectangle for a given frame index
        pub fn getFrameRect(self: Self, frame_index: usize) ?rl.Rectangle {
            if (frame_index >= self.frames.items.len) return null;
            const frame_data = self.frames.items[frame_index];
            // Assuming FrameDataType has a .frame field of type FrameRect {x,y,w,h}
            const fr = frame_data.frame;
            return rl.Rectangle{
                .x = @floatFromInt(fr.x),
                .y = @floatFromInt(fr.y),
                .width = @floatFromInt(fr.w),
                .height = @floatFromInt(fr.h),
            };
        }

        /// Get the number of frames
        pub fn frameCount(self: Self) usize {
            return self.frames.items.len;
        }

        /// Check if a frame exists
        pub fn hasFrame(self: Self, frame_index: usize) bool {
            return frame_index < self.frames.items.len;
        }

        const Self = @This();
        /// Draw a frame by index into a destination rectangle with tint.
        pub fn drawFrame(self: Self, frame_index: usize, dest: rl.Rectangle, tint: rl.Color) void {
            const src = self.getFrameRect(frame_index) orelse return;
            rl.drawTexturePro(self.texture, src, dest, rl.Vector2.zero(), 0, tint);
        }
    };
}

// A common named frame type used by XML-based atlases
pub const NamedFrame = struct {
    name: []const u8,
    frame: FrameRect,
};

pub const NamedTextureAtlas = TextureAtlas(NamedFrame);
