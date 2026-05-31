const std = @import("std");
const rl = @import("raylib");
const input_bindings = @import("input_bindings.zig");
const platform = @import("platform.zig");
const input_types = @import("input_types.zig");

pub const InputBinding = input_bindings.InputBinding;
pub const InputBindings = input_bindings.InputBindings;
pub const InputChord = input_bindings.InputChord;
pub const InputAction = input_bindings.InputAction;
pub const InputKey = input_types.InputKey;
pub const KeyCode = input_types.KeyCode;
pub const MouseButton = input_types.MouseButton;
pub const GamepadButton = input_types.GamepadButton;
pub const TouchInput = input_types.TouchInput;
pub const GestureInput = input_types.GestureInput;

/// Represents the current state of input devices
pub const InputState = struct {
    pressed_keys: std.ArrayList(InputKey),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InputState {
        return InputState{
            .pressed_keys = std.ArrayList(InputKey).initCapacity(allocator, 8) catch |err| {
                std.debug.panic("Initializing InputState: {s}", .{@errorName(err)});
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InputState) void {
        self.pressed_keys.deinit(self.allocator);
    }

    pub fn clear(self: *InputState) void {
        self.pressed_keys.clearRetainingCapacity();
    }

    pub fn add(self: *InputState, key: InputKey) !void {
        // Check if key is already pressed to avoid duplicates
        for (self.pressed_keys.items) |pressed_key| {
            if (pressed_key.eql(key)) {
                return; // Already pressed
            }
        }
        try self.pressed_keys.append(self.allocator, key);
    }

    pub fn remove(self: *InputState, key: InputKey) void {
        for (self.pressed_keys.items, 0..) |pressed_key, i| {
            if (pressed_key.eql(key)) {
                _ = self.pressed_keys.orderedRemove(i);
                return;
            }
        }
    }

    pub fn isPressed(self: *const InputState, key: InputKey) bool {
        for (self.pressed_keys.items) |pressed_key| {
            if (pressed_key.eql(key)) {
                return true;
            }
        }
        return false;
    }

    pub fn getPressed(self: *const InputState) []const InputKey {
        return self.pressed_keys.items;
    }
};

/// Event fired when an input binding is triggered
pub const InputEvent = struct {
    action: InputAction,
    chord: InputChord,
    timestamp: i64,

    pub fn init(action: InputAction, chord: InputChord) InputEvent {
        return InputEvent{
            .action = action,
            .chord = chord,
            .timestamp = @as(i64, @intFromFloat(rl.getTime() * @as(f64, @floatFromInt(std.time.us_per_s)))),
        };
    }
};

/// Callback function type for input events
pub const InputEventHandler = *const fn (event: InputEvent, user_data: ?*anyopaque) void;

/// Event handler struct
const EventHandlerInfo = struct {
    handler: InputEventHandler,
    user_data: ?*anyopaque,
};

/// Wrapper for raylib function callbacks; groups platform-specific
/// function pointers so callers can set them in one place.
pub const RaylibBindings = struct {
    is_key_down: ?*const fn (c_int) bool,
    is_mouse_button_down: ?*const fn (c_int) bool,
    is_gamepad_available: ?*const fn (i32) bool,
    is_gamepad_button_down: ?*const fn (i32, c_int) bool,
    get_touch_point_count: ?*const fn () i32,
    get_touch_position: ?*const fn (index: i32) rl.Vector2,
    get_gesture_detected: ?*const fn () rl.Gesture,
    is_gesture_detected: ?*const fn (gesture: rl.Gesture) bool,

    fn isKeyDownAdapter(key: c_int) bool {
        return rl.isKeyDown(@enumFromInt(key));
    }

    fn isMouseButtonDownAdapter(button: c_int) bool {
        return rl.isMouseButtonDown(@enumFromInt(button));
    }

    fn isGamepadButtonDownAdapter(gamepad: i32, button: c_int) bool {
        return rl.isGamepadButtonDown(gamepad, @enumFromInt(button));
    }

    pub fn default() RaylibBindings {
        return RaylibBindings{
            .is_key_down = isKeyDownAdapter,
            .is_mouse_button_down = isMouseButtonDownAdapter,
            .is_gamepad_available = rl.isGamepadAvailable,
            .is_gamepad_button_down = isGamepadButtonDownAdapter,
            .get_touch_point_count = rl.getTouchPointCount,
            .get_touch_position = rl.getTouchPosition,
            .get_gesture_detected = rl.getGestureDetected,
            .is_gesture_detected = rl.isGestureDetected,
        };
    }
};

/// Main input manager that processes input and triggers bindings
pub const InputManager = struct {
    raylib: RaylibBindings = undefined,
    bindings: InputBindings,
    current_state: InputState,
    previous_state: InputState,
    frames_to_skip_before_polling: u10,
    event_handlers: std.ArrayList(EventHandlerInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InputManager {
        //const log = std.log.scoped(.zevy_raylib);
        return InputManager{
            .bindings = InputBindings.init(allocator),
            .current_state = InputState.init(allocator),
            .previous_state = InputState.init(allocator),
            .frames_to_skip_before_polling = 1,
            .event_handlers = std.ArrayList(EventHandlerInfo).initCapacity(allocator, 10) catch |err| {
                std.debug.panic("Initializing InputManager: {s}", .{@errorName(err)});
            },
            .raylib = RaylibBindings.default(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InputManager) void {
        self.bindings.deinit();
        self.current_state.deinit();
        self.previous_state.deinit();
        self.event_handlers.deinit(self.allocator);
    }

    /// Set all raylib bindings at once
    pub fn setRaylibBindings(self: *InputManager, bindings: RaylibBindings) void {
        self.raylib = bindings;
    }

    /// Add an input binding
    pub fn addBinding(self: *InputManager, binding: InputBinding) !void {
        try self.bindings.addBinding(binding);
    }

    /// Remove an input binding by action name
    pub fn removeBinding(self: *InputManager, action_name: []const u8) bool {
        return self.bindings.removeBinding(action_name);
    }

    /// Add an event handler
    pub fn addEventHandler(self: *InputManager, handler: InputEventHandler, user_data: ?*anyopaque) !void {
        try self.event_handlers.append(self.allocator, EventHandlerInfo{
            .handler = handler,
            .user_data = user_data,
        });
    }

    pub fn removeEventHandler(self: *InputManager, handler: InputEventHandler) bool {
        for (self.event_handlers.items, 0..) |handler_info, i| {
            if (handler_info.handler == handler) {
                _ = self.event_handlers.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn clearBindings(self: *InputManager) void {
        self.bindings.clear();
    }

    /// Update input state and process bindings
    pub fn update(self: *InputManager) !void {
        // Store previous state
        self.previous_state.clear();
        try self.previous_state.pressed_keys.appendSlice(self.allocator, self.current_state.pressed_keys.items);

        // Update current state
        self.current_state.clear();
        try self.updateInputState();

        // Treat startup polls as a baseline so inputs held while the window is
        // appearing do not become synthetic triggers when the app first begins.
        if (self.frames_to_skip_before_polling != 0) {
            self.previous_state.clear();
            try self.previous_state.pressed_keys.appendSlice(self.allocator, self.current_state.pressed_keys.items);
            self.frames_to_skip_before_polling -= 1;
            return;
        }

        // Process input events
        try self.processInputEvents();
    }

    /// Update the current input state by checking raylib functions
    fn updateInputState(self: *InputManager) !void {
        // Check keyboard keys
        if (self.raylib.is_key_down) |is_key_down_fn| {
            const keys_to_check = std.enums.values(input_types.KeyCode);

            for (keys_to_check) |key| {
                if (is_key_down_fn(@intFromEnum(key))) {
                    try self.current_state.add(InputKey{ .keyboard = key });
                }
            }
        }

        // Check mouse buttons
        if (self.raylib.is_mouse_button_down) |is_mouse_button_down_fn| {
            const buttons_to_check = std.enums.values(input_types.MouseButton);

            for (buttons_to_check) |button| {
                if (is_mouse_button_down_fn(@intFromEnum(button))) {
                    try self.current_state.add(InputKey{ .mouse = button });
                }
            }
        }

        // Check gamepad buttons (check up to 4 gamepads)
        if (self.raylib.is_gamepad_available != null and self.raylib.is_gamepad_button_down != null) {
            if (self.raylib.is_gamepad_available) |gamepad_available_fn| {
                if (self.raylib.is_gamepad_button_down) |is_gamepad_button_down_fn| {
                    for (0..4) |gamepad_id| {
                        if (gamepad_available_fn(@intCast(gamepad_id))) {
                            const buttons_to_check = std.enums.values(input_types.GamepadButton);

                            for (buttons_to_check) |button| {
                                if (button == .any) continue;
                                if (is_gamepad_button_down_fn(@intCast(gamepad_id), @intFromEnum(button))) {
                                    try self.current_state.add(InputKey{ .gamepad = .{
                                        .gamepad_id = @intCast(gamepad_id),
                                        .button = button,
                                    } });
                                }
                            }
                        }
                    }
                }
            }
        }

        if (platform.usesTouchPrimaryPointer()) {
            // Touch and gesture input are only polled on touch-primary platforms.
            // On desktop Linux, raylib can surface pseudo-touch state that keeps
            // ui_click continuously active and suppresses mouse edge detection.

            // Check touch inputs
            if (self.raylib.get_touch_point_count) |get_count_fn| {
                const touch_count = get_count_fn();

                // Check each touch point (up to 10 supported by raylib)
                var i: c_int = 0;
                while (i < touch_count and i < 10) : (i += 1) {
                    if (self.raylib.get_touch_position) |get_pos_fn| {
                        const pos = get_pos_fn(i);
                        // Touch is considered active if we have a valid position
                        if (pos.x >= 0 and pos.y >= 0) {
                            try self.current_state.add(InputKey{ .touch = .{
                                .touch_id = @intCast(i),
                                .input = .touch_tap,
                            } });
                        }
                    }
                }
            }

            // Check gesture inputs
            if (self.raylib.get_gesture_detected) |get_gesture_fn| {
                const detected_gesture = get_gesture_fn();
                var gesture_input: ?GestureInput = null;

                if (detected_gesture.tap) {
                    gesture_input = .gesture_tap;
                } else if (detected_gesture.doubletap) {
                    gesture_input = .gesture_doubletap;
                } else if (detected_gesture.hold) {
                    gesture_input = .gesture_hold;
                } else if (detected_gesture.drag) {
                    gesture_input = .gesture_drag;
                } else if (detected_gesture.pinch_in) {
                    gesture_input = .gesture_pinch_in;
                } else if (detected_gesture.pinch_out) {
                    gesture_input = .gesture_pinch_out;
                } else if (detected_gesture.swipe_up) {
                    gesture_input = .gesture_swipe_up;
                } else if (detected_gesture.swipe_down) {
                    gesture_input = .gesture_swipe_down;
                } else if (detected_gesture.swipe_left) {
                    gesture_input = .gesture_swipe_left;
                } else if (detected_gesture.swipe_right) {
                    gesture_input = .gesture_swipe_right;
                }

                if (gesture_input) |gesture| {
                    try self.current_state.add(InputKey{ .gesture = gesture });
                }
            }
        }
    }

    /// Process input events by checking for newly triggered bindings
    fn processInputEvents(self: *InputManager) !void {
        // Find bindings that match the current state but didn't match the previous state
        const current_keys = self.current_state.getPressed();
        const previous_keys = self.previous_state.getPressed();

        // Check all bindings to see if any are newly triggered
        for (self.bindings.getAllBindings()) |*binding| {
            const matches_current = binding.matches(current_keys);
            const matches_previous = binding.matches(previous_keys);

            // If it matches now but didn't match before, it's a new trigger
            if (matches_current and !matches_previous) {
                const event = InputEvent.init(binding.action, binding.chord);
                try self.fireEvent(event);
            }
        }
    }

    /// Fire an input event to all registered handlers
    fn fireEvent(self: *InputManager, event: InputEvent) !void {
        for (self.event_handlers.items) |handler_info| {
            handler_info.handler(event, handler_info.user_data);
        }
    }

    /// Check if a specific action is currently active
    pub fn isActionActive(self: *const InputManager, action_name: []const u8) bool {
        const current_keys = self.current_state.getPressed();
        return self.bindings.actionMatches(action_name, current_keys);
    }

    /// Check if a specific action was just triggered (pressed this frame)
    pub fn wasActionTriggered(self: *const InputManager, action_name: []const u8) bool {
        const current_keys = self.current_state.getPressed();
        const previous_keys = self.previous_state.getPressed();
        return self.bindings.actionTriggered(action_name, current_keys, previous_keys);
    }

    /// Get the current input state
    pub fn getCurrentState(self: *const InputManager) *const InputState {
        return &self.current_state;
    }

    /// Get the input bindings
    pub fn getBindings(self: *const InputManager) *const InputBindings {
        return &self.bindings;
    }

    /// Enable or disable a binding
    pub fn setBindingEnabled(self: *InputManager, action_name: []const u8, enabled: bool) bool {
        return self.bindings.setBindingEnabled(action_name, enabled);
    }

    /// Clear all event handlers
    pub fn clearEventHandlers(self: *InputManager) void {
        self.event_handlers.clearRetainingCapacity();
    }

    /// Get debug information about current input state
    pub fn getDebugInfo(self: *const InputManager, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayList(u8) = .empty;
        defer result.deinit(allocator);

        try result.appendSlice(allocator, "Current Input State:\n");

        const current_keys = self.current_state.getPressed();
        if (current_keys.len == 0) {
            try result.appendSlice(allocator, "  No keys pressed\n");
        } else {
            try result.appendSlice(allocator, "  Pressed keys: ");
            for (current_keys, 0..) |key, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                const key_str = try key.toString(allocator);
                defer allocator.free(key_str);
                try result.appendSlice(allocator, key_str);
            }
            try result.appendSlice(allocator, "\n");
        }

        try result.appendSlice(allocator, "\nActive Bindings:\n");
        var found_active = false;
        for (self.bindings.getAllBindings()) |*binding| {
            if (binding.matches(current_keys)) {
                found_active = true;
                const chord_str = try binding.chord.toString(allocator);
                defer allocator.free(chord_str);
                try result.writer(allocator).print("  {s} -> {s}\n", .{ chord_str, binding.action.name });
            }
        }

        if (!found_active) {
            try result.appendSlice(allocator, "  No active bindings\n");
        }

        return result.toOwnedSlice(allocator);
    }
};
