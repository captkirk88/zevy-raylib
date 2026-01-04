const std = @import("std");
const rl = @import("raylib");

const Frame = @import("../graphics/texture_atlas.zig").NamedFrame;
const FrameRect = @import("../graphics/texture_atlas.zig").FrameRect;
const input_types = @import("../input/input_types.zig");
const KeyCode = input_types.KeyCode;
const MouseButton = input_types.MouseButton;

/// Represents a mapped input icon with frame indices for normal and outline variants
pub const InputIconMapping = struct {
    /// Frame index for the normal icon
    normal_index: ?usize = null,
    /// Frame index for the outline variant (if available)
    outline_index: ?usize = null,
};

pub const IconAtlas = struct {
    texture: *rl.Texture,
    frames: std.ArrayList(Frame),
    allocator: std.mem.Allocator,
    owns_texture: bool,
    /// KeyCode to frame index mappings (populated by processor)
    key_mappings: ?std.AutoHashMap(KeyCode, InputIconMapping) = null,
    /// MouseButton to frame index mappings (populated by processor)
    mouse_mappings: ?std.AutoHashMap(MouseButton, InputIconMapping) = null,

    pub fn init(allocator: std.mem.Allocator, texture: *rl.Texture, frames: std.ArrayList(Frame), owns_texture: bool) IconAtlas {
        return IconAtlas{
            .texture = texture,
            .frames = frames,
            .allocator = allocator,
            .owns_texture = owns_texture,
            .key_mappings = null,
            .mouse_mappings = null,
        };
    }

    pub fn deinit(self: *IconAtlas) void {
        // Free duplicated frame name strings owned by the frames' allocator
        for (self.frames.items) |frame| {
            if (frame.name.len > 0) self.allocator.free(frame.name);
        }
        // Free frames array
        self.frames.deinit(self.allocator);
        // Free mappings if they were created
        if (self.key_mappings) |*km| km.deinit();
        if (self.mouse_mappings) |*mm| mm.deinit();
        if (self.owns_texture) {
            rl.unloadTexture(self.texture.*);
            self.allocator.destroy(self.texture);
        }
    }

    pub fn frameCount(self: IconAtlas) usize {
        return self.frames.items.len;
    }

    /// Populate keyboard icon mappings from frame names (e.g., "keyboard_a", "keyboard_arrow_up_outline").
    pub fn populateKeyboardMappings(self: *IconAtlas) !void {
        if (self.key_mappings == null) {
            self.key_mappings = std.AutoHashMap(KeyCode, InputIconMapping).init(self.allocator);
        }

        // Work on a local copy and write back to avoid losing the mutated map
        var mappings = self.key_mappings.?;
        defer self.key_mappings = mappings;

        for (self.frames.items, 0..) |frame, idx| {
            const parsed = parseKeyboardFrame(frame.name) orelse continue;

            const entry = try mappings.getOrPut(parsed.key_code);
            if (!entry.found_existing) entry.value_ptr.* = .{};
            if (parsed.is_outline) {
                entry.value_ptr.outline_index = idx;
            } else {
                entry.value_ptr.normal_index = idx;
            }
        }
    }

    const ParseResult = struct {
        key_code: KeyCode,
        is_outline: bool,
    };

    fn parseKeyboardFrame(name: []const u8) ?ParseResult {
        if (name.len == 0) return null;

        var lower_buf: [96]u8 = undefined;
        if (name.len > lower_buf.len) return null;
        for (name, 0..) |ch, i| lower_buf[i] = std.ascii.toLower(ch);
        const lowered = lower_buf[0..name.len];

        const outline_suffix = "_outline";
        const is_outline = std.mem.endsWith(u8, lowered, outline_suffix);
        const base = if (is_outline)
            lowered[0 .. lowered.len - outline_suffix.len]
        else
            lowered;

        const prefix = "keyboard_";
        if (!std.mem.startsWith(u8, base, prefix)) return null;
        const key_name = base[prefix.len..];

        const key_code = keyNameToCode(key_name) orelse return null;
        return ParseResult{ .key_code = key_code, .is_outline = is_outline };
    }

    fn keyNameToCode(name: []const u8) ?KeyCode {
        // Ignore mouse icons embedded in the keyboard sheet
        if (std.mem.startsWith(u8, name, "mouse")) return null;

        // Normalize some suffix-based variants (icon, icon_alternative)
        const trimmed = blk: {
            const suffixes = .{ "_icon_alternative", "_icon" };
            inline for (suffixes) |suf| {
                if (std.mem.endsWith(u8, name, suf)) {
                    break :blk name[0 .. name.len - suf.len];
                }
            }
            break :blk name;
        };

        const simple = .{
            .{ "space", KeyCode.key_space },
            .{ "enter", KeyCode.key_enter },
            .{ "return", KeyCode.key_enter },
            .{ "escape", KeyCode.key_escape },
            .{ "tab", KeyCode.key_tab },
            .{ "backspace", KeyCode.key_backspace },
            .{ "shift", KeyCode.key_shift },
            .{ "ctrl", KeyCode.key_control },
            .{ "control", KeyCode.key_control },
            .{ "alt", KeyCode.key_alt },
            .{ "option", KeyCode.key_alt },
            .{ "command", KeyCode.key_left_super },
            .{ "win", KeyCode.key_left_super },
            .{ "super", KeyCode.key_left_super },
            .{ "arrow_up", KeyCode.key_up },
            .{ "arrow_down", KeyCode.key_down },
            .{ "arrow_left", KeyCode.key_left },
            .{ "arrow_right", KeyCode.key_right },
            .{ "arrows_all", KeyCode.key_arrows_all },
            .{ "arrows", KeyCode.key_arrows_all },
            .{ "arrows_down", KeyCode.key_down },
            .{ "arrows_left", KeyCode.key_left },
            .{ "arrows_right", KeyCode.key_right },
            .{ "arrows_up", KeyCode.key_up },
            .{ "arrows_horizontal", KeyCode.key_arrows_all },
            .{ "arrows_vertical", KeyCode.key_arrows_all },
            .{ "arrows_none", KeyCode.key_arrows_all },
            .{ "page_up", KeyCode.key_page_up },
            .{ "page_down", KeyCode.key_page_down },
            .{ "home", KeyCode.key_home },
            .{ "end", KeyCode.key_end },
            .{ "insert", KeyCode.key_insert },
            .{ "delete", KeyCode.key_delete },
            .{ "capslock", KeyCode.key_caps_lock },
            .{ "capslock_icon", KeyCode.key_caps_lock },
            .{ "numlock", KeyCode.key_num_lock },
            .{ "scrolllock", KeyCode.key_scroll_lock },
            .{ "printscreen", KeyCode.key_print_screen },
            .{ "pause", KeyCode.key_pause },
            .{ "equals", KeyCode.key_equal },
            .{ "plus", KeyCode.key_equal },
            .{ "minus", KeyCode.key_minus },
            .{ "period", KeyCode.key_period },
            .{ "comma", KeyCode.key_comma },
            .{ "semicolon", KeyCode.key_semicolon },
            .{ "colon", KeyCode.key_semicolon },
            .{ "apostrophe", KeyCode.key_apostrophe },
            .{ "quote", KeyCode.key_apostrophe },
            .{ "backslash", KeyCode.key_backslash },
            .{ "slash_back", KeyCode.key_backslash },
            .{ "slash_forward", KeyCode.key_slash },
            .{ "question", KeyCode.key_slash },
            .{ "tilde", KeyCode.key_grave },
            .{ "caret", KeyCode.key_grave },
            .{ "exclamation", KeyCode.key_1 },
            .{ "bracket_open", KeyCode.key_left_bracket },
            .{ "bracket_close", KeyCode.key_right_bracket },
            .{ "bracket_less", KeyCode.key_comma },
            .{ "bracket_greater", KeyCode.key_period },
            .{ "backspace_icon", KeyCode.key_backspace },
            .{ "backspace_icon_alternative", KeyCode.key_backspace },
            .{ "shift_icon", KeyCode.key_shift },
            .{ "space_icon", KeyCode.key_space },
            .{ "tab_icon", KeyCode.key_tab },
            .{ "tab_icon_alternative", KeyCode.key_tab },
            .{ "numpad_enter", KeyCode.key_kp_enter },
            .{ "numpad_plus", KeyCode.key_kp_add },
            .{ "any", KeyCode.any },
        };

        inline for (simple) |entry| {
            if (std.mem.eql(u8, trimmed, entry[0])) return entry[1];
        }

        if (std.mem.startsWith(u8, trimmed, "f") and trimmed.len > 1) {
            const n = std.fmt.parseInt(u8, trimmed[1..], 10) catch null;
            if (n) |val| {
                return switch (val) {
                    1 => KeyCode.key_f1,
                    2 => KeyCode.key_f2,
                    3 => KeyCode.key_f3,
                    4 => KeyCode.key_f4,
                    5 => KeyCode.key_f5,
                    6 => KeyCode.key_f6,
                    7 => KeyCode.key_f7,
                    8 => KeyCode.key_f8,
                    9 => KeyCode.key_f9,
                    10 => KeyCode.key_f10,
                    11 => KeyCode.key_f11,
                    12 => KeyCode.key_f12,
                    else => null,
                };
            }
        }

        if (std.mem.startsWith(u8, trimmed, "kp_")) {
            const rest = trimmed[3..];
            const kp_table = .{
                .{ "enter", KeyCode.key_kp_enter },
                .{ "equal", KeyCode.key_kp_equal },
                .{ "add", KeyCode.key_kp_add },
                .{ "subtract", KeyCode.key_kp_subtract },
                .{ "multiply", KeyCode.key_kp_multiply },
                .{ "divide", KeyCode.key_kp_divide },
                .{ "decimal", KeyCode.key_kp_decimal },
            };
            inline for (kp_table) |entry| {
                if (std.mem.eql(u8, rest, entry[0])) return entry[1];
            }
            if (rest.len == 1 and std.ascii.isDigit(rest[0])) {
                return switch (rest[0]) {
                    '0' => KeyCode.key_kp_0,
                    '1' => KeyCode.key_kp_1,
                    '2' => KeyCode.key_kp_2,
                    '3' => KeyCode.key_kp_3,
                    '4' => KeyCode.key_kp_4,
                    '5' => KeyCode.key_kp_5,
                    '6' => KeyCode.key_kp_6,
                    '7' => KeyCode.key_kp_7,
                    '8' => KeyCode.key_kp_8,
                    '9' => KeyCode.key_kp_9,
                    else => null,
                };
            }
        }

        if (std.mem.startsWith(u8, trimmed, "numpad_")) {
            const rest = trimmed[7..];
            if (std.mem.eql(u8, rest, "enter")) return KeyCode.key_kp_enter;
            if (std.mem.eql(u8, rest, "plus")) return KeyCode.key_kp_add;
        }

        if (trimmed.len == 1) {
            const ch = trimmed[0];
            if (std.ascii.isAlphabetic(ch)) {
                return switch (std.ascii.toLower(ch)) {
                    'a' => KeyCode.key_a,
                    'b' => KeyCode.key_b,
                    'c' => KeyCode.key_c,
                    'd' => KeyCode.key_d,
                    'e' => KeyCode.key_e,
                    'f' => KeyCode.key_f,
                    'g' => KeyCode.key_g,
                    'h' => KeyCode.key_h,
                    'i' => KeyCode.key_i,
                    'j' => KeyCode.key_j,
                    'k' => KeyCode.key_k,
                    'l' => KeyCode.key_l,
                    'm' => KeyCode.key_m,
                    'n' => KeyCode.key_n,
                    'o' => KeyCode.key_o,
                    'p' => KeyCode.key_p,
                    'q' => KeyCode.key_q,
                    'r' => KeyCode.key_r,
                    's' => KeyCode.key_s,
                    't' => KeyCode.key_t,
                    'u' => KeyCode.key_u,
                    'v' => KeyCode.key_v,
                    'w' => KeyCode.key_w,
                    'x' => KeyCode.key_x,
                    'y' => KeyCode.key_y,
                    'z' => KeyCode.key_z,
                    else => null,
                };
            }

            if (std.ascii.isDigit(ch)) {
                return switch (ch) {
                    '0' => KeyCode.key_0,
                    '1' => KeyCode.key_1,
                    '2' => KeyCode.key_2,
                    '3' => KeyCode.key_3,
                    '4' => KeyCode.key_4,
                    '5' => KeyCode.key_5,
                    '6' => KeyCode.key_6,
                    '7' => KeyCode.key_7,
                    '8' => KeyCode.key_8,
                    '9' => KeyCode.key_9,
                    else => null,
                };
            }
        }

        return null;
    }

    /// Get the frame index for a keyboard key icon
    pub fn getKeyIcon(self: *const IconAtlas, key: KeyCode, outline: bool) ?usize {
        if (self.key_mappings) |km| {
            if (km.get(key)) |mapping| {
                return if (outline) mapping.outline_index else mapping.normal_index;
            }
        }
        return null;
    }

    /// Get the frame index for a mouse button icon
    pub fn getMouseIcon(self: *const IconAtlas, button: MouseButton, outline: bool) ?usize {
        if (self.mouse_mappings) |mm| {
            if (mm.get(button)) |mapping| {
                return if (outline) mapping.outline_index else mapping.normal_index;
            }
        }
        return null;
    }

    /// Get the frame rectangle for a keyboard key
    pub fn getKeyFrame(self: *const IconAtlas, key: KeyCode, outline: bool) ?FrameRect {
        if (self.getKeyIcon(key, outline)) |index| {
            if (index < self.frames.items.len) {
                return self.frames.items[index].frame;
            }
        }
        return null;
    }

    /// Get the frame rectangle for a mouse button
    pub fn getMouseFrame(self: *const IconAtlas, button: MouseButton, outline: bool) ?FrameRect {
        if (self.getMouseIcon(button, outline)) |index| {
            if (index < self.frames.items.len) {
                return self.frames.items[index].frame;
            }
        }
        return null;
    }
};

test "populateKeyboardMappings maps letters and function keys" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const TestFrame = @import("../graphics/texture_atlas.zig").NamedFrame;

    var frames = try std.ArrayList(TestFrame).initCapacity(allocator, 4);

    try frames.append(allocator, .{ .name = try allocator.dupe(u8, "keyboard_n"), .frame = .{ .x = 0, .y = 0, .w = 1, .h = 1 } });
    try frames.append(allocator, .{ .name = try allocator.dupe(u8, "keyboard_g"), .frame = .{ .x = 0, .y = 0, .w = 1, .h = 1 } });
    try frames.append(allocator, .{ .name = try allocator.dupe(u8, "keyboard_f3"), .frame = .{ .x = 0, .y = 0, .w = 1, .h = 1 } });
    try frames.append(allocator, .{ .name = try allocator.dupe(u8, "keyboard_f"), .frame = .{ .x = 0, .y = 0, .w = 1, .h = 1 } });

    const tex = try allocator.create(rl.Texture);
    tex.* = undefined;

    var atlas = IconAtlas.init(allocator, tex, frames, false);
    defer atlas.deinit();
    defer allocator.destroy(tex);

    try atlas.populateKeyboardMappings();

    try testing.expectEqual(@as(?usize, 0), atlas.getKeyIcon(KeyCode.key_n, false));
    try testing.expectEqual(@as(?usize, 1), atlas.getKeyIcon(KeyCode.key_g, false));
    try testing.expectEqual(@as(?usize, 2), atlas.getKeyIcon(KeyCode.key_f3, false));
    try testing.expectEqual(@as(?usize, 3), atlas.getKeyIcon(KeyCode.key_f, false));
}
