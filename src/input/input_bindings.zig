const std = @import("std");
const input_types = @import("input_types.zig");

pub const InputKey = input_types.InputKey;
pub const KeyCode = input_types.KeyCode;
pub const MouseButton = input_types.MouseButton;
pub const GamepadButton = input_types.GamepadButton;

/// Represents a chord of inputs that must be pressed together
pub const InputChord = struct {
    keys: std.ArrayList(InputKey),

    pub fn init(allocator: std.mem.Allocator) InputChord {
        return InputChord{
            .keys = std.ArrayList(InputKey).initCapacity(allocator, 4) catch |err| {
                std.debug.panic("Initializing InputChord: {s}", .{@errorName(err)});
            },
        };
    }

    pub fn deinit(self: *InputChord, allocator: std.mem.Allocator) void {
        self.keys.deinit(allocator);
    }

    pub fn add(self: *InputChord, allocator: std.mem.Allocator, key: InputKey) error{OutOfMemory}!void {
        try self.keys.append(allocator, key);
    }

    /// Get the length of the chord (number of keys)
    pub fn len(self: *const InputChord) usize {
        return self.keys.items.len;
    }

    /// Check if this chord contains the given key
    pub fn contains(self: *const InputChord, key: InputKey) bool {
        for (self.keys.items) |chord_key| {
            if (chord_key.eql(key)) {
                return true;
            }
        }
        return false;
    }

    /// Check if this chord matches exactly the given set of pressed keys
    pub fn matches(self: *const InputChord, pressed_keys: []const InputKey) bool {
        if (self.keys.items.len != pressed_keys.len) {
            return false;
        }

        // Check that all chord keys are in pressed keys
        for (self.keys.items) |chord_key| {
            var found = false;
            for (pressed_keys) |pressed_key| {
                if (chord_key.eql(pressed_key)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        return true;
    }

    /// Check if this chord is a subset of the given pressed keys
    /// This is used to check if a chord could potentially match
    pub fn isSubsetOf(self: *const InputChord, pressed_keys: []const InputKey) bool {
        for (self.keys.items) |chord_key| {
            var found = false;
            for (pressed_keys) |pressed_key| {
                if (chord_key.eql(pressed_key)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    /// Compare two chords for sorting (longer chords first, then lexicographically)
    pub fn compare(self: *const InputChord, other: *const InputChord) std.math.Order {
        // First, compare by length (longer chords have priority)
        if (self.keys.items.len > other.keys.items.len) {
            return .lt; // self comes before other
        } else if (self.keys.items.len < other.keys.items.len) {
            return .gt; // self comes after other
        }

        // Same length, compare lexicographically by key values
        const min_len = @min(self.keys.items.len, other.keys.items.len);
        for (0..min_len) |i| {
            const self_key_val = switch (self.keys.items[i]) {
                .keyboard => |k| @as(u32, @intCast(@intFromEnum(k))),
                .mouse => |m| @as(u32, @intCast(@intFromEnum(m))) + 1000000,
                .gamepad => |g| @as(u32, @intCast(@intFromEnum(g.button))) + 2000000 + (@as(u32, g.gamepad_id) * 100),
                .touch => |t| @as(u32, @intCast(@intFromEnum(t.input))) + 3000000 + (@as(u32, t.touch_id) * 100),
                .gesture => |gest| @as(u32, @intCast(@intFromEnum(gest))) + 4000000,
            };
            const other_key_val = switch (other.keys.items[i]) {
                .keyboard => |k| @as(u32, @intCast(@intFromEnum(k))),
                .mouse => |m| @as(u32, @intCast(@intFromEnum(m))) + 1000000,
                .gamepad => |g| @as(u32, @intCast(@intFromEnum(g.button))) + 2000000 + (@as(u32, g.gamepad_id) * 100),
                .touch => |t| @as(u32, @intCast(@intFromEnum(t.input))) + 3000000 + (@as(u32, t.touch_id) * 100),
                .gesture => |gest| @as(u32, @intCast(@intFromEnum(gest))) + 4000000,
            };

            if (self_key_val < other_key_val) {
                return .lt;
            } else if (self_key_val > other_key_val) {
                return .gt;
            }
        }

        return .eq; // They are identical
    }

    /// Convert chord to string representation
    pub fn toString(self: *const InputChord, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        if (self.keys.items.len == 0) {
            return try allocator.dupe(u8, "");
        }

        var result = try std.ArrayList(u8).initCapacity(allocator, self.keys.items.len * 10);
        defer result.deinit(allocator);

        for (self.keys.items, 0..) |key, i| {
            if (i > 0) {
                try result.appendSlice(allocator, "+");
            }
            const key_str = try key.toString(allocator);
            defer allocator.free(key_str);
            try result.appendSlice(allocator, key_str);
        }

        return result.toOwnedSlice(allocator);
    }

    /// Parse chord from string representation (e.g., "LeftCtrl+E" or "A")
    pub fn fromString(str: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}!?InputChord {
        var chord = InputChord.init(allocator);

        var iter = std.mem.splitSequence(u8, str, "+");
        while (iter.next()) |key_str| {
            if (InputKey.fromString(key_str, allocator)) |key| {
                try chord.add(allocator, key);
            } else {
                chord.deinit(allocator);
                return null;
            }
        }

        if (chord.keys.items.len == 0) {
            chord.deinit(allocator);
            return null;
        }

        return chord;
    }

    /// Create a clone of this chord
    pub fn clone(self: *const InputChord, allocator: std.mem.Allocator) !InputChord {
        var new_chord = InputChord.init(allocator);
        try new_chord.keys.appendSlice(allocator, self.keys.items);
        return new_chord;
    }
};

/// Represents an action that can be bound to input chords
pub const InputAction = struct {
    name: []const u8,
    description: []const u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !InputAction {
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        const owned_description = try allocator.dupe(u8, description);
        return InputAction{
            .name = owned_name,
            .description = owned_description,
        };
    }

    pub fn deinit(self: *InputAction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
    }

    pub fn eql(self: *const InputAction, other: *const InputAction) bool {
        return std.mem.eql(u8, self.name, other.name);
    }
};

/// Represents a binding between an input chord and an action
pub const InputBinding = struct {
    chord: InputChord,
    action: InputAction,
    enabled: bool = true,

    pub fn init(chord: InputChord, action: InputAction) InputBinding {
        return InputBinding{
            .chord = chord,
            .action = action,
        };
    }

    pub fn deinit(self: *InputBinding, allocator: std.mem.Allocator) void {
        self.chord.deinit(allocator);
        self.action.deinit(allocator);
    }

    /// Check if this binding matches the current input state
    pub fn matches(self: *const InputBinding, current_keys: []const InputKey) bool {
        if (!self.enabled) return false;

        // Single-key chords use subset matching to avoid gesture interference
        // (e.g., MouseLeft binding should work even when GestureTap is also detected)
        if (self.chord.keys.items.len == 1) {
            return self.chord.isSubsetOf(current_keys);
        }

        // Multi-key chords require exact matching to preserve combo behavior
        // (e.g., Ctrl+S should not trigger when Ctrl+Shift+S is pressed)
        return self.chord.matches(current_keys);
    }

    /// Check if this binding could potentially match (is a subset of current keys)
    pub fn couldMatch(self: *const InputBinding, current_keys: []const InputKey) bool {
        if (!self.enabled) return false;
        return self.chord.isSubsetOf(current_keys);
    }

    /// Get the priority of this binding (based on chord length)
    pub fn getPriority(self: *const InputBinding) usize {
        return self.chord.len();
    }

    /// Create a clone of this binding
    pub fn clone(self: *const InputBinding, allocator: std.mem.Allocator) !InputBinding {
        const cloned_chord = try self.chord.clone(allocator);
        return InputBinding{
            .chord = cloned_chord,
            .action = self.action, // Actions are immutable, so we can share them
            .enabled = self.enabled,
        };
    }
};

/// Collection of input bindings with efficient lookup
pub const InputBindings = struct {
    const Self = @This();
    bindings: std.ArrayList(InputBinding),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InputBindings {
        return InputBindings{
            .bindings = std.ArrayList(InputBinding).initCapacity(allocator, 16) catch |err| {
                std.debug.panic("Initializing InputBindings: {s}", .{@errorName(err)});
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.bindings.items) |*binding| {
            binding.deinit(self.allocator);
        }
        self.bindings.deinit(self.allocator);
    }

    /// Add a new binding
    pub fn addBinding(self: *Self, binding: InputBinding) !void {
        try self.bindings.append(self.allocator, binding);
        self.sortBindings();
    }

    /// Remove a binding by action name
    pub fn removeBinding(self: *Self, action_name: []const u8) bool {
        for (self.bindings.items, 0..) |*binding, i| {
            if (std.mem.eql(u8, binding.action.name, action_name)) {
                binding.deinit(self.allocator);
                _ = self.bindings.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Find the best matching binding for the given pressed keys
    /// Returns the binding with the longest matching chord
    pub fn findBestMatch(self: *const Self, pressed_keys: []const InputKey) ?*const InputBinding {
        // Since bindings are sorted by priority (longest first),
        // the first match is the best match
        for (self.bindings.items) |*binding| {
            if (binding.matches(pressed_keys)) {
                return binding;
            }
        }
        return null;
    }

    /// Get all bindings that could potentially match (useful for detecting conflicts)
    pub fn getPotentialMatches(self: *const Self, pressed_keys: []const InputKey, allocator: std.mem.Allocator) ![]const *const InputBinding {
        var matches = std.ArrayList(*const InputBinding){};
        defer matches.deinit(allocator);

        for (self.bindings.items) |*binding| {
            if (binding.couldMatch(pressed_keys)) {
                try matches.append(allocator, binding);
            }
        }

        return matches.toOwnedSlice(allocator);
    }

    /// Sort bindings by priority (longer chords first)
    fn sortBindings(self: *Self) void {
        std.sort.insertion(InputBinding, self.bindings.items, {}, bindingLessThan);
    }

    fn bindingLessThan(context: void, a: InputBinding, b: InputBinding) bool {
        _ = context;
        return a.chord.compare(&b.chord) == .lt;
    }

    /// Get binding by action name
    pub fn getBinding(self: *const Self, action_name: []const u8) ?*const InputBinding {
        for (self.bindings.items) |*binding| {
            if (std.mem.eql(u8, binding.action.name, action_name)) {
                return binding;
            }
        }
        return null;
    }

    /// Enable or disable a binding
    pub fn setBindingEnabled(self: *Self, action_name: []const u8, enabled: bool) bool {
        for (self.bindings.items) |*binding| {
            if (std.mem.eql(u8, binding.action.name, action_name)) {
                binding.enabled = enabled;
                return true;
            }
        }
        return false;
    }

    /// Get all bindings
    pub fn getAllBindings(self: *const Self) []const InputBinding {
        return self.bindings.items;
    }

    /// Clear all bindings
    pub fn clear(self: *Self) void {
        for (self.bindings.items) |*binding| {
            binding.deinit(self.allocator);
        }
        self.bindings.clearRetainingCapacity();
    }

    /// Create a clone of all bindings
    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !InputBindings {
        var new_bindings = InputBindings.init(allocator);

        for (self.bindings.items) |*binding| {
            const cloned_binding = try binding.clone(allocator);
            try new_bindings.bindings.append(allocator, cloned_binding);
        }

        return new_bindings;
    }
};
