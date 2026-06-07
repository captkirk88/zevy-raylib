const std = @import("std");
const id_generator = @import("id_generator.zig");

test "ID generator basic functionality" {
    var generator = id_generator.IdGenerator{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate some IDs
    const id1 = try generator.generate(allocator, null);
    defer allocator.free(id1);
    const id2 = try generator.generate(allocator, null);
    defer allocator.free(id2);
    const id3 = try generator.generate(allocator, "custom");
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

test "ID generator counter overflow" {
    var generator = id_generator.IdGenerator{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Manually set counter to max value to test overflow handling
    generator.counter.store(std.math.maxInt(u32), .release);

    // Generate an ID, which should trigger the overflow logic
    const id = try generator.generate(allocator, "overflow");
    defer allocator.free(id);

    // Check that the generated ID has the expected format and prefix
    try std.testing.expect(std.mem.startsWith(u8, id, "overflow_"));
}

test "ID generator no conflicting ids" {
    var generator = id_generator.IdGenerator{};
    const num_ids = 10_000;
    var mmap_allocator = @import("zevy_mem").allocators.MmapAllocator.init(std.testing.io, .{
        .size = std.heap.pageSize() * num_ids,
        .path = "bin/test_ids_mmap_allocator.bin",
    });
    defer switch (mmap_allocator.deinit()) {
        .ok => {},
        .leak => std.debug.print("Warning: MmapAllocator deinit leaked memory\n", .{}),
    };
    const allocator = mmap_allocator.allocator();

    var ids = try std.ArrayList([]u8).initCapacity(std.testing.allocator, num_ids);
    defer ids.deinit(std.testing.allocator);
    defer for (ids.items) |id| allocator.free(id);

    // Generate a large number of IDs and retain ownership until after uniqueness checks
    for (0..num_ids) |_| {
        const id = try generator.generate(allocator, "test");
        try ids.append(allocator, id);
    }

    // Check that all generated IDs are unique
    for (ids.items, 0..ids.items.len) |id1, i| {
        for (ids.items[i + 1 ..]) |id2| {
            try std.testing.expect(!std.mem.eql(u8, id1, id2));
        }
    }
}

test "ID generator global instance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test the global generator
    const id1 = try id_generator.generateId(allocator, null);
    defer allocator.free(id1);
    const id2 = try id_generator.generateId(allocator, "test");
    defer allocator.free(id2);

    try std.testing.expect(std.mem.startsWith(u8, id1, "id_"));
    try std.testing.expect(std.mem.startsWith(u8, id2, "test_"));
    try std.testing.expect(!std.mem.eql(u8, id1, id2));
}
