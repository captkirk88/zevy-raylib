const std = @import("std");

pub const CompareOptions = enum {
    /// Lightweight: normalize / case-fold using Unicode-aware helpers (best-effort)
    /// This is intended to be "culture-invariant" semantics (canonical-equivalence + casefold)
    invariant,
    /// Unicode-invariant, case-insensitive
    invariantIgnoreCase,

    /// Ordinal (binary) comparison
    ordinal,
    /// Ordinal (binary) comparison, case-insensitive (ASCII only)
    ordinalIgnoreCase,

    /// Culture-aware comparisons require a platform/ICU implementation.
    /// When ICU/platform support isn't enabled this falls back to `invariant`.
    cultureAware,
    /// Culture-aware, case-insensitive (locale-specific rules) - falls back to `invariantIgnoreCase`.
    cultureAwareIgnoreCase,
};

pub const StringSize = enum {
    u8,
    u16,

    pub fn Type(self: StringSize) type {
        switch (self) {
            .u8 => return u8,
            .u16 => return u16,
        }
    }

    pub fn fromType(comptime T: type) StringSize {
        return switch (T) {
            u8 => .u8,
            u16 => .u16,
            else => @compileError("Invalid type"),
        };
    }
};

pub fn String(comptime S: StringSize) type {
    return struct {
        const Self = @This();
        const T = S.Type();
        bytes: []const T,

        pub const empty = Self{
            .bytes = &[_]T{},
        };

        pub fn init(v: []const T) Self {
            return .{
                .bytes = v,
            };
        }

        pub fn len(self: *const Self) usize {
            return self.bytes.len;
        }

        pub fn clone(self: *const Self) Self {
            return .{ .bytes = self.bytes };
        }

        pub fn toLowerAscii(self: *const Self) !Self {
            const out = try std.heap.page_allocator.alloc(T, self.bytes.len);
            for (self.bytes, 0..self.bytes.len) |ch, i| {
                out[i] = toLowerAsciiC(S, ch);
            }
            return .{ .bytes = out };
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(T, self.bytes, other.bytes);
        }

        pub fn eqlSz(self: *const Self, comptime Sz: StringSize, other: *const Self) bool {
            return std.mem.eql(Sz.Type(), self.bytes, other.bytes);
        }

        pub fn startsWith(self: *const Self, other: []const T, opt: CompareOptions) bool {
            if (other.len > self.len()) return false;
            switch (opt) {
                .ordinal, .invariant, .cultureAware => {
                    // Binary / culture-sensitive startsWith (no case-folding)
                    return std.mem.eql(T, self.bytes[0..other.len], other);
                },
                .ordinalIgnoreCase => {
                    for (self.bytes[0..other.len], 0..other.len) |ch, i| {
                        if (toLowerAsciiC(S, ch) != toLowerAsciiC(S, other[i])) return false;
                    }
                    return true;
                },
                .invariantIgnoreCase, .cultureAwareIgnoreCase => {
                    // Normalize and casefold both strings then check prefix.
                    // For CultureAwareIgnoreCase we fall back to invariant behavior if ICU isn't present.
                    // Use an allocator on the stack via the general purpose allocator for now.
                    const allocator = std.heap.page_allocator;
                    const self_cf = casefoldNormalizeAlloc(allocator, S, self.bytes) catch return false;
                    defer allocator.free(self_cf);
                    const other_cf = casefoldNormalizeAlloc(allocator, S, other) catch {
                        return false;
                    };
                    defer allocator.free(other_cf);
                    if (other_cf.len > self_cf.len) return false;
                    return std.mem.eql(T, self_cf[0..other_cf.len], other_cf);
                },
            }
        }

        pub fn indexOf(self: *const Self, other: []const T, opt: CompareOptions) ?usize {
            return indexOfAlloc(S, std.heap.page_allocator, self.bytes, other, opt);
        }

        pub fn swapSz(self: *const Self, comptime S2: StringSize) error{
            InvalidUtf8,
            DanglingSurrogateHalf,
            ExpectedSecondSurrogateHalf,
            UnexpectedSecondSurrogateHalf,
            OutOfMemory,
        }!String(S2) {
            if (S == S2) return String(S2).init(self.bytes);

            if (S == .u8 and S2 == .u16) {
                const utf16_bytes = try std.unicode.utf8ToUtf16LeAlloc(std.heap.page_allocator, self.bytes);
                return String(.u16).init(utf16_bytes);
            } else if (S == .u16 and S2 == .u8) {
                const utf8_bytes = try std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, self.bytes);
                return String(.u8).init(utf8_bytes);
            }

            @compileError("Unsupported swapSz conversion");
        }

        pub fn format(self: *const Self, writer: *std.Io.Writer) error{WriteFailed}!void {
            switch (S) {
                .u8 => try writer.writeAll(self.bytes),
                .u16 => {
                    // For UTF-16, we need to convert to UTF-8 before writing.
                    const utf8_bytes = std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, self.bytes) catch return error.WriteFailed;
                    defer std.heap.page_allocator.free(utf8_bytes);
                    try writer.writeAll(utf8_bytes);
                },
            }
        }
    };
}

pub fn toLowerAsciiC(comptime T: StringSize, c: T.Type()) T.Type() {
    const A_UPPER: T.Type() = 'A';
    const Z_UPPER: T.Type() = 'Z';
    if (c >= A_UPPER and c <= Z_UPPER) return c + 32;
    return c;
}

pub fn indexOf(comptime Sz: StringSize, hay: []const Sz.Type(), needle: []const Sz.Type(), opt: CompareOptions) ?usize {
    return indexOfAlloc(Sz, std.heap.page_allocator, hay, needle, opt);
}

pub fn indexOfAlloc(comptime Sz: StringSize, allocator: std.mem.Allocator, hay: []const Sz.Type(), needle: []const Sz.Type(), opt: CompareOptions) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > hay.len) return null;
    const last = hay.len - needle.len;
    var i: usize = 0;
    while (i <= last) : (i += 1) {
        var matched = true;
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            const hc = hay[i + j];
            const nc = needle[j];
            switch (opt) {
                .ordinal, .invariant, .cultureAware => if (hc != nc) {
                    matched = false;
                    break;
                },
                .ordinalIgnoreCase => if (toLowerAsciiC(Sz, hc) != toLowerAsciiC(Sz, nc)) {
                    matched = false;
                    break;
                },
                .invariantIgnoreCase, .cultureAwareIgnoreCase => {
                    // Use equalsUnicode to check this candidate substring with normalization
                    const sub = hay[i .. i + needle.len];
                    if (!(equalsUnicode(allocator, sub, needle, opt) catch false)) {
                        matched = false;
                        break;
                    }
                },
            }
        }
        if (matched) return i;
    }
    return null;
}

pub fn casefoldNormalize(comptime Sz: StringSize, s: []const Sz.Type()) ![]Sz.Type() {
    return casefoldNormalizeAlloc(std.heap.page_allocator, Sz, s);
}

/// Casefold and canonicalize a UTF-8 string into a newly allocated buffer.
/// This is a best-effort helper for Unicode-invariant comparisons. It handles
/// ASCII case mapping and a small set of compatibility mappings (ligatures, ß).
pub fn casefoldNormalizeAlloc(allocator: std.mem.Allocator, comptime Sz: StringSize, s: []const Sz.Type()) ![]Sz.Type() {
    const T = Sz.Type();
    // Small heuristic: pre-allocate same length or slightly larger to avoid growth churn
    var out = try allocator.alloc(T, s.len * 2 + 8);
    var wrote: usize = 0;

    var view = switch (Sz) {
        .u8 => try std.unicode.Utf8View.init(s),
        .u16 => try std.unicode.Utf8View.init(std.unicode.utf16LeToUtf8Alloc(allocator, s)),
    };
    defer if (Sz == .u16) allocator.free(view.bytes);

    var iter = view.iterator();
    while (true) {
        const cp_slice = iter.nextCodepointSlice() orelse break;
        // Fast path: ASCII
        if (cp_slice.len == 1 and cp_slice[0] <= 0x7F) {
            const c = cp_slice[0];
            const lc = if (c >= 'A' and c <= 'Z') c + 32 else c;
            out[wrote] = lc;
            wrote += 1;
            continue;
        }

        // Decode codepoint
        const cp = try std.unicode.utf8Decode(cp_slice);

        // handle a couple of compatibility mappings
        if (cp == 0x00DF) { // ß -> ss
            if (wrote + 2 > out.len) out = try allocator.realloc(out, out.len * 2);
            out[wrote] = 's';
            out[wrote + 1] = 's';
            wrote += 2;
            continue;
        }
        if (cp == 0xFB01) { // ﬁ
            if (wrote + 2 > out.len) out = try allocator.realloc(out, out.len * 2);
            out[wrote] = 'f';
            out[wrote + 1] = 'i';
            wrote += 2;
            continue;
        }
        if (cp == 0xFB02) { // ﬂ
            if (wrote + 2 > out.len) out = try allocator.realloc(out, out.len * 2);
            out[wrote] = 'f';
            out[wrote + 1] = 'l';
            wrote += 2;
            continue;
        }

        // For other non-ASCII codepoints, we do not have a full casefold table
        // available in stdlib, so we conservatively append the original bytes
        // unchanged. This keeps canonical equivalence intact for many cases
        // (e.g. composed vs decomposed sequences are left untouched). If you
        // need true Unicode canonicalization use ICU or a full normalization table.
        if (wrote + cp_slice.len > out.len) out = try allocator.realloc(out, (out.len * 2) + cp_slice.len);
        @memmove(out[wrote .. wrote + cp_slice.len], cp_slice);
        wrote += cp_slice.len;
    }

    // shrink to fit
    const final = try allocator.realloc(out, wrote);
    return final;
}

pub fn equalsUnicode(allocator: std.mem.Allocator, a: []const u8, b: []const u8, opt: CompareOptions) !bool {
    // Only handle the two Unicode-invariant options here. For culture-aware
    // checks we'll fall back to the invariant behavior unless ICU is integrated.
    const ignore_case = if (opt == .invariantIgnoreCase or opt == .cultureAwareIgnoreCase) true else false;

    if (!ignore_case) {
        // UnicodeInvariant but case-sensitive — treat as an ordinal-equals for now.
        return std.mem.eql(u8, a, b);
    }

    // case-insensitive: produce casefolded/normalized buffers and compare
    const a_cf = try casefoldNormalizeAlloc(allocator, .u8, a);
    const b_cf = try casefoldNormalizeAlloc(allocator, .u8, b);
    const res = std.mem.eql(u8, a_cf, b_cf);
    allocator.free(a_cf);
    allocator.free(b_cf);
    return res;
}

pub fn contains(hay: []const u8, needle: []const u8, opt: CompareOptions) bool {
    return indexOf(.u8, hay, needle, opt) != null;
}

/// Safely return a slice of `s` from `start` for `len` bytes.
/// Returns null if the requested range is out of bounds.
pub fn substring(s: []const u8, start: usize, len: usize) ?[]const u8 {
    if (start > s.len) return null;
    if (len > s.len - start) return null;
    return s[start .. start + len];
}

/// Safely return a slice of `s` from `start` (inclusive) to `end` (exclusive).
/// Returns null if out-of-bounds or start > end.
pub fn sliceRange(s: []const u8, start: usize, end: usize) ?[]const u8 {
    if (start > end) return null;
    if (end > s.len) return null;
    return s[start..end];
}

/// Parse an integer from a byte slice. Returns null if parsing fails.
/// Parse an integer from a byte slice into any integer type `IntType`.
/// Returns `null` if parsing fails.
pub fn parseIntNullable(comptime IntType: type, s: []const u8, base: u8) ?IntType {
    const res = std.fmt.parseInt(IntType, s, base) catch return null;
    return res;
}

pub fn trimAsciiWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) : (start += 1) {}
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\n' or s[end - 1] == '\r')) : (end -= 1) {}
    return s[start..end];
}
