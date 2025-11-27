const std = @import("std");
const rl = @import("raylib");

// Resource types for UI (non-component global resources)
const Assets = @import("../io/assets.zig").Assets;
const AssetHandle = @import("../io/assets.zig").AssetHandle;

pub const UIIconAtlasHandle = struct {
    handle: AssetHandle,

    pub fn init(h: AssetHandle) UIIconAtlasHandle {
        return .{ .handle = h };
    }
};
