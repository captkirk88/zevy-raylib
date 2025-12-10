const std = @import("std");

/// A thread-safe ID generator that produces unique string identifiers
pub const IdGenerator = struct {
    counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// Generate a unique ID with the given prefix
    /// Returns an owned string that must be freed by the caller
    pub fn generateOwned(self: *IdGenerator, allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
        const id_num = self.counter.fetchAdd(1, .monotonic);
        return try std.fmt.allocPrint(allocator, "{s}_{d}", .{ prefix, id_num });
    }

    /// Generate a unique ID with default "id" prefix
    /// Returns an owned string that must be freed by the caller
    pub fn generateIdOwned(self: *IdGenerator, allocator: std.mem.Allocator) ![]u8 {
        return try self.generateOwned(allocator, "id");
    }
};

/// Global ID generator instance for convenience
var global_id_generator = IdGenerator{};

/// Convenience function to generate a unique owned ID with the given prefix
/// using the global generator. Returns an owned string that must be freed by the caller.
pub fn generateIdOwned(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    return try global_id_generator.generateOwned(allocator, prefix);
}

/// Convenience function to generate a unique owned ID with default "id" prefix
/// Returns an owned string that must be freed by the caller.
pub fn generateUniqueIdOwned(allocator: std.mem.Allocator) ![]u8 {
    return try global_id_generator.generateIdOwned(allocator);
}
