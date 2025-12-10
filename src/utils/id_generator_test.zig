const std = @import("std");
const id_generator = @import("id_generator.zig");

test "ID generator basic functionality" {
    var generator = id_generator.IdGenerator{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate some IDs
    const id1 = try generator.generateIdOwned(allocator);
    defer allocator.free(id1);
    const id2 = try generator.generateIdOwned(allocator);
    defer allocator.free(id2);
    const id3 = try generator.generateOwned(allocator, "custom");
    defer allocator.free(id3);

    // Check that IDs are different
    try std.testing.expect(!std.mem.eql(u8, id1, id2));
    try std.testing.expect(!std.mem.eql(u8, id1, id3));
    try std.testing.expect(!std.mem.eql(u8, id2, id3));

    // Check that IDs contain expected prefixes
    try std.testing.expect(std.mem.startsWith(u8, id1, "id_"));
    try std.testing.expect(std.mem.startsWith(u8, id2, "id_"));
    try std.testing.expect(std.mem.startsWith(u8, id3, "custom_"));
}

test "ID generator global instance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test the global generator
    const id1 = try id_generator.generateUniqueIdOwned(allocator);
    defer allocator.free(id1);
    const id2 = try id_generator.generateIdOwned(allocator, "test");
    defer allocator.free(id2);

    try std.testing.expect(std.mem.startsWith(u8, id1, "id_"));
    try std.testing.expect(std.mem.startsWith(u8, id2, "test_"));
    try std.testing.expect(!std.mem.eql(u8, id1, id2));
}
