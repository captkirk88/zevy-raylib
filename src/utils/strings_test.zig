const std = @import("std");
const strings = @import("./strings.zig");

test "equals - unicode casefold for ß" {
    const allocator = std.testing.allocator;
    const a = "straße";
    const b = "STRASSE";

    try std.testing.expect(try strings.equalsUnicode(allocator, a, b, .invariantIgnoreCase));
}

test "startsWith - ligature fi" {
    const allocator = std.testing.allocator;
    // encode the U+FB01 ligature using explicit UTF-8 bytes (EF AC 81) to avoid
    // depending on file encoding when running tests.
    const a = "\xEF\xAC\x81" ++ "le"; // "ﬁle"
    const b = "fi";

    const s = strings.String(.u8).init(a);
    try std.testing.expect(s.startsWith(b, .invariantIgnoreCase));
    // ensure the ligature itself equals the two-char sequence "fi"
    try std.testing.expect(try strings.equalsUnicode(allocator, a[0..3], "fi", .invariantIgnoreCase));
}

test "indexOf - ß -> ss mapping" {
    const allocator = std.testing.allocator;
    const hay = "AßB";
    const needle = "ss";

    const idx = strings.indexOf(.u8, hay, needle, .invariantIgnoreCase);
    if (idx) |found| {
        try std.testing.expect(found == 1);
        try std.testing.expect(try strings.equalsUnicode(allocator, hay[found .. found + needle.len], needle, .invariantIgnoreCase));
    } else {
        try std.testing.expect(false);
    }
}

test "substring and sliceRange" {
    const s = "Hello, world";
    if (strings.substring(s, 0, 5)) |ss| {
        try std.testing.expect(std.mem.eql(u8, ss, "Hello"));
    } else try std.testing.expect(false);

    if (strings.substring(s, 7, 5)) |ss2| {
        try std.testing.expect(std.mem.eql(u8, ss2, "world"));
    } else try std.testing.expect(false);

    try std.testing.expect(strings.substring(s, 7, 50) == null);

    if (strings.sliceRange(s, 7, 12)) |sr| {
        try std.testing.expect(std.mem.eql(u8, sr, "world"));
    } else try std.testing.expect(false);

    try std.testing.expect(strings.sliceRange(s, 12, 7) == null);
}

test "parseIntNullable & parseIntToU8Nullable" {
    const a = "123";
    const b = "256";
    if (strings.parseIntNullable(u64, a, 10)) |val| try std.testing.expect(val == 123) else try std.testing.expect(false);
    if (strings.parseIntNullable(u8, a, 10)) |val8| try std.testing.expect(val8 == 123) else try std.testing.expect(false);
    try std.testing.expect(strings.parseIntNullable(u8, b, 10) == null);
}

test "String swap types" {
    const test_data = "Hello";
    const s = strings.String(.u8).init(test_data);
    const s2 = try s.swapSz(.u16);
    try std.testing.expectEqualSlices(u8, test_data, s.bytes);
    try std.testing.expectEqual(s.bytes.len, s2.bytes.len);
    for (test_data, 0..) |ch, i| {
        try std.testing.expectEqual(@as(u16, ch), s2.bytes[i]);
    }
}

test "String swap types with non-ASCII" {
    const allocator = std.testing.allocator;
    const test_data = "Héllo"; // 'é' is U+00E9
    const s = strings.String(.u8).init(test_data);
    const s2 = try s.swapSz(.u16);
    try std.testing.expectEqualSlices(u8, test_data, s.bytes);

    const roundtrip = try std.unicode.utf16LeToUtf8Alloc(allocator, s2.bytes);
    defer allocator.free(roundtrip);
    try std.testing.expectEqualSlices(u8, test_data, roundtrip);

    std.debug.print("Original: {f}, Swapped: {f}\n", .{ s, s2 });
}
