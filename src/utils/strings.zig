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

fn toLowerAscii(b: u8) u8 {
    if (b >= 'A' and b <= 'Z') return b + 32;
    return b;
}

pub fn startsWith(hay: []const u8, needle: []const u8, opt: CompareOptions) bool {
    if (needle.len > hay.len) return false;
    switch (opt) {
        .ordinal, .invariant, .cultureAware => {
            // Binary / culture-sensitive startsWith (no case-folding)
            return std.mem.eql(u8, hay[0..needle.len], needle);
        },
        .ordinalIgnoreCase => {
            var i: usize = 0;
            while (i < needle.len) : (i += 1) {
                if (toLowerAscii(hay[i]) != toLowerAscii(needle[i])) return false;
            }
            return true;
        },
        .invariantIgnoreCase, .cultureAwareIgnoreCase => {
            // Normalize and casefold both strings then check prefix.
            // For CultureAwareIgnoreCase we fall back to invariant behavior if ICU isn't present.
            // Use an allocator on the stack via the general purpose allocator for now.
            var arena = std.heap.page_allocator;
            const hay_cf = casefoldNormalizeAlloc(arena, hay) catch return false;
            defer arena.free(hay_cf);
            const needle_cf = casefoldNormalizeAlloc(arena, needle) catch {
                return false;
            };
            defer arena.free(needle_cf);
            if (needle_cf.len > hay_cf.len) return false;
            return std.mem.eql(u8, hay_cf[0..needle_cf.len], needle_cf);
        },
    }
}

pub fn equals(a: []const u8, b: []const u8, opt: CompareOptions) bool {
    if (a.len != b.len) return false;
    switch (opt) {
        .ordinal, .invariant, .cultureAware => return std.mem.eql(u8, a, b),
        .ordinalIgnoreCase => {
            var i: usize = 0;
            while (i < a.len) : (i += 1) {
                if (toLowerAscii(a[i]) != toLowerAscii(b[i])) return false;
            }
            return true;
        },
        .invariantIgnoreCase, .cultureAwareIgnoreCase => {
            // Use Unicode-aware casefolding
            // Use the default allocator for temporary buffers
            var arena = std.heap.page_allocator;
            const ac = casefoldNormalizeAlloc(arena, a) catch return false;
            defer arena.free(ac);
            const bc = casefoldNormalizeAlloc(arena, b) catch return false;
            defer arena.free(bc);
            return std.mem.eql(u8, ac, bc);
        },
    }
}

pub fn indexOf(hay: []const u8, needle: []const u8, opt: CompareOptions) ?usize {
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
                .ordinalIgnoreCase => if (toLowerAscii(hc) != toLowerAscii(nc)) {
                    matched = false;
                    break;
                },
                .invariantIgnoreCase, .cultureAwareIgnoreCase => {
                    // Use equalsUnicode to check this candidate substring with normalization
                    const sub = hay[i .. i + needle.len];
                    if (!(equalsUnicode(std.heap.page_allocator, sub, needle, opt) catch false)) {
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

/// Casefold and canonicalize a UTF-8 string into a newly allocated buffer.
/// This is a best-effort helper for Unicode-invariant comparisons. It handles
/// ASCII case mapping and a small set of compatibility mappings (ligatures, ß).
pub fn casefoldNormalizeAlloc(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Small heuristic: pre-allocate same length or slightly larger to avoid growth churn
    var out = try allocator.alloc(u8, s.len * 2 + 8);
    var wrote: usize = 0;

    var view = try std.unicode.Utf8View.init(s);
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
    const a_cf = try casefoldNormalizeAlloc(allocator, a);
    const b_cf = try casefoldNormalizeAlloc(allocator, b);
    const res = std.mem.eql(u8, a_cf, b_cf);
    allocator.free(a_cf);
    allocator.free(b_cf);
    return res;
}

pub fn contains(hay: []const u8, needle: []const u8, opt: CompareOptions) bool {
    return indexOf(hay, needle, opt) != null;
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
/// Parse an integer from a byte slice into any integer type T.
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

pub const Strings = struct {};
