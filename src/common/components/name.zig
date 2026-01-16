//! A lightweight, inline fixed-size name component for entities.
//!
// This component stores short human-readable names directly inside the
// component value to avoid dynamic allocation. It is intended for debug,
// editor and logging use; names longer than `MAX_LEN` are truncated.

const std = @import("std");

pub const Name = struct {
    /// Maximum number of bytes stored for a name (not including an implicit
    /// null terminator). Chosen to fit common use-cases while keeping the
    /// component's memory footprint small.
    pub const MAX_LEN: usize = 64;

    len: u8,
    buf: [MAX_LEN]u8,

    /// Create an empty name.
    pub fn init() Name {
        var n: Name = undefined;
        n.len = 0;
        return n;
    }

    /// Create a name initialized from a string slice.
    /// If `s.len > MAX_LEN` the value is truncated to `MAX_LEN` bytes.
    pub fn initFrom(s: []const u8) Name {
        var n = Name.init();
        n.set(s);
        return n;
    }

    /// Set the name to `s`, truncating if necessary.
    pub fn set(self: *Name, s: []const u8) void {
        const tocopy = if (s.len < Name.MAX_LEN) s.len else Name.MAX_LEN;
        // Copy bytes (no allocation); remaining bytes beyond `len` are unspecified.
        std.mem.copy(u8, self.buf[0..tocopy], s[0..tocopy]);
        self.len = @as(u8, tocopy);
    }

    /// Return a slice view of the stored name bytes (not NUL-terminated).
    pub fn asSlice(self: *const Name) []const u8 {
        return self.buf[0..@as(usize, self.len)];
    }

    /// Check equality against a string slice.
    pub fn eql(self: *const Name, s: []const u8) bool {
        const a = self.asSlice();
        if (a.len != s.len) return false;
        return std.mem.eql(u8, a, s);
    }
};
