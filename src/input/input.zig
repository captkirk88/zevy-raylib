//! Input system for handling keyboard, mouse, and gamepad input with customizable bindings
//!
//! This module provides a comprehensive input binding system that supports:
//! - Key chords (e.g., Ctrl+E, Shift+F1)
//! - Proper chord precedence (longer chords take priority)
//! - Keyboard, mouse, and gamepad input
//! - Serialization to/from JSON files
//! - Real-time input processing with raylib integration
//!
//! Usage example:
//! ```zig
//! var input_manager = InputManager.init(allocator);
//! defer input_manager.deinit();
//!
//! // Add a binding
//! var chord = InputChord.init(allocator);
//! try chord.addKey(InputKey{ .keyboard = .key_space });
//! const action = InputAction.init("jump", "Jump action");
//! try input_manager.addBinding(InputBinding.init(chord, action));
//!
//! // In your game loop:
//! try input_manager.update();
//! if (input_manager.wasActionTriggered("jump")) {
//!     // Handle jump
//! }
//! ```

const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

// Re-export all public types and functions
const types = @import("input_types.zig");
pub const bindings = @import("input_bindings.zig");
const input_man = @import("input_manager.zig");
const serialize = @import("serialization.zig");
pub const params = @import("params.zig");

// Raylib function bindings
pub const RaylibBindings = input_man.RaylibBindings;

// Core types
pub const InputKey = types.InputKey;
pub const KeyCode = types.KeyCode;
pub const MouseButton = types.MouseButton;
pub const GamepadButton = types.GamepadButton;
pub const TouchInput = types.TouchInput;
pub const GestureInput = types.GestureInput;
pub const InputDevice = types.InputDevice;

// Binding types
pub const InputChord = bindings.InputChord;
pub const InputAction = bindings.InputAction;
pub const InputBinding = bindings.InputBinding;
pub const InputBindings = bindings.InputBindings;
pub const InputBindingCollection = bindings.InputBindings;

// Manager types
pub const InputState = input_man.InputState;
pub const InputEvent = input_man.InputEvent;
pub const InputEventHandler = input_man.InputEventHandler;
pub const InputManager = input_man.InputManager;

// Serialization
pub const SerializationError = serialize.SerializationError;

// Convenience functions
pub const serializeToFile = serialize.serializeToFile;
pub const deserializeFromFile = serialize.deserializeFromFile;
pub const serializeToSlice = serialize.serializeToSlice;
pub const serializeToString = serialize.serializeToString;
pub const deserializeFromSlice = serialize.deserializeFromSlice;
pub const deserializeFromString = serialize.deserializeFromString;
pub const validateBindings = serialize.validateBindings;
pub const printBindings = serialize.printBindings;

/// Get the current mouse position (or touch position on mobile)
///
/// If no touch points are active on mobile, returns null.
pub fn getMousePosition() ?rl.Vector2 {
    const os = builtin.os.tag;
    const arch = builtin.target.cpu.arch;
    const isAndroid = (os == .linux and (arch == .arm or arch == .armeb or arch == .x86 or arch == .x86_64));
    if (os == .ios or isAndroid) {
        if (rl.getTouchPointCount() == 0) {
            return null; // No touch points
        }
        return rl.getTouchPosition(0);
    } else {
        return rl.getMousePosition();
    }
}

/// Create a simple input chord from a single key
pub fn createSimpleChord(key: InputKey, allocator: std.mem.Allocator) !InputChord {
    var chord = InputChord.init(allocator);
    try chord.add(allocator, key);
    return chord;
}

/// Create a keyboard chord from a key code
pub fn createKeyboardChord(key_code: KeyCode, allocator: std.mem.Allocator) !InputChord {
    return createSimpleChord(InputKey{ .keyboard = key_code }, allocator);
}

/// Create a mouse chord from a button
pub fn createMouseChord(button: MouseButton, allocator: std.mem.Allocator) !InputChord {
    return createSimpleChord(InputKey{ .mouse = button }, allocator);
}

/// Create a gamepad chord from a gamepad ID and button
pub fn createGamepadChord(gamepad_id: u8, button: GamepadButton, allocator: std.mem.Allocator) !InputChord {
    return createSimpleChord(InputKey{ .gamepad = .{ .gamepad_id = gamepad_id, .button = button } }, allocator);
}

/// Create a touch chord from a touch ID and touch input type
pub fn createTouchChord(touch_id: u8, input: TouchInput, allocator: std.mem.Allocator) !InputChord {
    return createSimpleChord(InputKey{ .touch = .{ .touch_id = touch_id, .input = input } }, allocator);
}

/// Create a gesture chord from a gesture input type
pub fn createGestureChord(gesture: GestureInput, allocator: std.mem.Allocator) !InputChord {
    return createSimpleChord(InputKey{ .gesture = gesture }, allocator);
}

/// Create a complex chord from multiple keys
pub fn createComplexChord(keys: []const InputKey, allocator: std.mem.Allocator) !InputChord {
    var chord = InputChord.init(allocator);
    for (keys) |key| {
        try chord.add(allocator, key);
    }
    return chord;
}

/// Builder pattern for creating input bindings more easily
pub const InputBindingBuilder = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    chord: ?InputChord = null,
    action_name: ?[]const u8 = null,
    action_description: ?[]const u8 = null,
    is_enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) InputBindingBuilder {
        return InputBindingBuilder{
            .allocator = allocator,
        };
    }

    pub fn with(self: *Self, key: InputKey) *Self {
        if (self.chord == null) {
            self.chord = InputChord.init(self.allocator);
        }
        self.chord.?.add(self.allocator, key) catch |err| {
            std.debug.panic("Failed to add key to chord: {s}", .{@errorName(err)});
        };
        return self;
    }

    pub fn withKeyboard(self: *Self, key_code: KeyCode) *Self {
        return self.with(InputKey{ .keyboard = key_code });
    }

    pub fn withMouse(self: *Self, button: MouseButton) *Self {
        return self.with(InputKey{ .mouse = button });
    }

    pub fn withGamepad(self: *Self, gamepad_id: u8, button: GamepadButton) *Self {
        return self.with(InputKey{ .gamepad = .{ .gamepad_id = gamepad_id, .button = button } });
    }

    pub fn withChord(self: *Self, chord_str: []const u8) *Self {
        const _chord = InputChord.fromString(chord_str, self.allocator) catch |err| {
            std.debug.panic("Failed to parse chord from string '{s}': {s}", .{ chord_str, @errorName(err) });
        };
        if (_chord) |chord| {
            if (self.chord) |*existing_chord| {
                existing_chord.deinit(self.allocator);
            }
            self.chord = chord;
        }
        return self;
    }

    pub fn withAction(self: *Self, name: []const u8, description: []const u8) *Self {
        self.action_name = name;
        self.action_description = description;
        return self;
    }

    pub fn enabled(self: *Self, enabled_state: bool) *Self {
        self.is_enabled = enabled_state;
        return self;
    }

    pub fn build(self: *Self) error{ MissingChord, MissingAction, OutOfMemory }!InputBinding {
        if (self.chord == null) {
            return error.MissingChord;
        }
        if (self.action_name == null) {
            return error.MissingAction;
        }

        const action = try InputAction.init(self.allocator, self.action_name.?, self.action_description orelse "");

        var binding = InputBinding.init(self.chord.?, action);
        binding.enabled = self.is_enabled;

        // Reset the builder
        self.chord = null;
        self.action_name = null;
        self.action_description = null;
        self.is_enabled = true;

        return binding;
    }

    pub fn deinit(self: *Self) void {
        if (self.chord) |*chord| {
            chord.deinit(self.allocator);
        }
    }
};

test "input system basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test creating a simple chord
    var chord = try createKeyboardChord(.key_space, allocator);
    defer chord.deinit(allocator);

    // Test chord string representation
    const chord_str = try chord.toString(allocator);
    defer allocator.free(chord_str);
    testing.expect(std.mem.eql(u8, chord_str, "Space")) catch unreachable;

    // Test action creation
    const action = try InputAction.init(allocator, "jump", "Jump action");

    // Test binding creation
    const cloned_chord = try chord.clone(allocator);
    var binding = InputBinding.init(cloned_chord, action);
    defer binding.deinit(allocator);

    // Test binding builder
    var builder = InputBindingBuilder.init(allocator);
    defer builder.deinit();

    var built_binding = try builder
        .withKeyboard(.key_e)
        .withAction("interact", "Interact with objects")
        .build();
    defer built_binding.deinit(allocator);

    testing.expect(std.mem.eql(u8, built_binding.action.name, "interact")) catch unreachable;
}
