const std = @import("std");

/// A thread-safe ID generator that produces unique string identifiers
pub const IdGenerator = struct {
    counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// Generate a unique ID with the given prefix
    /// Returns an owned string that must be freed by the caller
    pub fn generate(self: *IdGenerator, allocator: std.mem.Allocator, prefix: ?[]const u8) ![]u8 {
        if (self.counter.load(.acquire) == std.math.maxInt(u32)) {
            self.counter.store(1, .release);
        }
        const id_num = self.counter.fetchAdd(1, .monotonic);
        const prefix_str = prefix orelse "id";
        return try std.fmt.allocPrint(allocator, "{s}_{d}", .{ prefix_str, id_num });
    }
};

/// Global ID generator instance for convenience
pub var global_id_generator = IdGenerator{};

/// Convenience function to generate a unique owned ID with the given prefix
/// using the global generator. Returns an owned string that must be freed by the caller.
pub fn generateId(allocator: std.mem.Allocator, prefix: ?[]const u8) ![]u8 {
    return try global_id_generator.generate(allocator, prefix);
}
