const std = @import("std");
const rl = @import("raylib");

// Resource types for UI (non-component global resources)
const Assets = @import("../io/assets.zig").Assets;
const AssetHandle = @import("../io/assets.zig").AssetHandle;
const io_types = @import("../io/types.zig");

pub const UIIconAtlasHandle = struct {
    atlas: *io_types.IconAtlas,

    pub fn init(atlas: *io_types.IconAtlas) UIIconAtlasHandle {
        return .{ .atlas = atlas };
    }
};
