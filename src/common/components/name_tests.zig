const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const Name = @import("name.zig").Name;

test "Name initFrom and equals" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e = manager.create(.{Name.initFrom("Alice")});
    const t = try manager.getComponent(e, Name);
    if (t) |name| {
        try std.testing.expect(name.eql("Alice"));
        try std.testing.expect(std.mem.eql(u8, name.asSlice(), "Alice"));
    } else try std.testing.expect(false);
}

test "Name truncation" {
    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var long: [200]u8 = undefined;
    // fill long with repeating alphabet
    var i: usize = 0;
    while (i < long.len) : (i += 1) {
        long[i] = @as(u8, 'a' + (i % 26));
    }
    const s = long[0..];

    const e = manager.create(.{Name.initFrom(s)});
    const t = try manager.getComponent(e, Name);
    if (t) |name| {
        try std.testing.expectEqual(@as(usize, name.len), Name.MAX_LEN);
        // ensure prefix matches original
        try std.testing.expect(std.mem.eql(u8, name.asSlice(), s[0..Name.MAX_LEN]));
    } else try std.testing.expect(false);
}
