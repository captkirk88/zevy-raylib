const name = @import("components/name_tests.zig");
const transform = @import("components/transform_tests.zig");

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(transform);
}
