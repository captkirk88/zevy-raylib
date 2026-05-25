const builtin = @import("builtin");
const std = @import("std");

pub fn usesTouchPrimaryPointerForPlatform(os: std.Target.Os.Tag, abi: std.Target.Abi) bool {
    return os == .ios or abi == .android;
}

pub fn usesTouchPrimaryPointer() bool {
    return usesTouchPrimaryPointerForPlatform(builtin.os.tag, builtin.target.abi);
}

test "touch-primary platform detection does not treat desktop linux as android" {
    try std.testing.expect(!usesTouchPrimaryPointerForPlatform(.windows, .gnu));
    try std.testing.expect(!usesTouchPrimaryPointerForPlatform(.linux, .gnu));
    try std.testing.expect(usesTouchPrimaryPointerForPlatform(.linux, .android));
    try std.testing.expect(usesTouchPrimaryPointerForPlatform(.ios, .gnu));
}