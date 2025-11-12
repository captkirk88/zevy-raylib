const std = @import("std");
const rl = @import("raylib");

/// Represents different types of input devices
pub const InputDevice = enum {
    keyboard,
    mouse,
    gamepad,
};

/// Keyboard key codes (based on raylib keys)
pub const KeyCode = enum(c_int) {
    // Alphanumeric keys
    key_a = @intFromEnum(rl.KeyboardKey.a),
    key_b = @intFromEnum(rl.KeyboardKey.b),
    key_c = @intFromEnum(rl.KeyboardKey.c),
    key_d = @intFromEnum(rl.KeyboardKey.d),
    key_e = @intFromEnum(rl.KeyboardKey.e),
    key_f = @intFromEnum(rl.KeyboardKey.f),
    key_g = @intFromEnum(rl.KeyboardKey.g),
    key_h = @intFromEnum(rl.KeyboardKey.h),
    key_i = @intFromEnum(rl.KeyboardKey.i),
    key_j = @intFromEnum(rl.KeyboardKey.j),
    key_k = @intFromEnum(rl.KeyboardKey.k),
    key_l = @intFromEnum(rl.KeyboardKey.l),
    key_m = @intFromEnum(rl.KeyboardKey.m),
    key_n = @intFromEnum(rl.KeyboardKey.n),
    key_o = @intFromEnum(rl.KeyboardKey.o),
    key_p = @intFromEnum(rl.KeyboardKey.p),
    key_q = @intFromEnum(rl.KeyboardKey.q),
    key_r = @intFromEnum(rl.KeyboardKey.r),
    key_s = @intFromEnum(rl.KeyboardKey.s),
    key_t = @intFromEnum(rl.KeyboardKey.t),
    key_u = @intFromEnum(rl.KeyboardKey.u),
    key_v = @intFromEnum(rl.KeyboardKey.v),
    key_w = @intFromEnum(rl.KeyboardKey.w),
    key_x = @intFromEnum(rl.KeyboardKey.x),
    key_y = @intFromEnum(rl.KeyboardKey.y),
    key_z = @intFromEnum(rl.KeyboardKey.z),

    // Function keys
    key_f1 = @intFromEnum(rl.KeyboardKey.f1),
    key_f2 = @intFromEnum(rl.KeyboardKey.f2),
    key_f3 = @intFromEnum(rl.KeyboardKey.f3),
    key_f4 = @intFromEnum(rl.KeyboardKey.f4),
    key_f5 = @intFromEnum(rl.KeyboardKey.f5),
    key_f6 = @intFromEnum(rl.KeyboardKey.f6),
    key_f7 = @intFromEnum(rl.KeyboardKey.f7),
    key_f8 = @intFromEnum(rl.KeyboardKey.f8),
    key_f9 = @intFromEnum(rl.KeyboardKey.f9),
    key_f10 = @intFromEnum(rl.KeyboardKey.f10),
    key_f11 = @intFromEnum(rl.KeyboardKey.f11),
    key_f12 = @intFromEnum(rl.KeyboardKey.f12),

    // Arrow keys
    key_right = @intFromEnum(rl.KeyboardKey.right),
    key_left = @intFromEnum(rl.KeyboardKey.left),
    key_down = @intFromEnum(rl.KeyboardKey.down),
    key_up = @intFromEnum(rl.KeyboardKey.up),

    // Special keys
    key_space = @intFromEnum(rl.KeyboardKey.space),
    key_escape = @intFromEnum(rl.KeyboardKey.escape),
    key_enter = @intFromEnum(rl.KeyboardKey.enter),
    key_tab = @intFromEnum(rl.KeyboardKey.tab),
    key_backspace = @intFromEnum(rl.KeyboardKey.backspace),
    key_insert = @intFromEnum(rl.KeyboardKey.insert),
    key_delete = @intFromEnum(rl.KeyboardKey.delete),
    key_page_up = @intFromEnum(rl.KeyboardKey.page_up),
    key_page_down = @intFromEnum(rl.KeyboardKey.page_down),
    key_home = @intFromEnum(rl.KeyboardKey.home),
    key_end = @intFromEnum(rl.KeyboardKey.end),
    key_caps_lock = @intFromEnum(rl.KeyboardKey.caps_lock),
    key_scroll_lock = @intFromEnum(rl.KeyboardKey.scroll_lock),
    key_num_lock = @intFromEnum(rl.KeyboardKey.num_lock),
    key_print_screen = @intFromEnum(rl.KeyboardKey.print_screen),
    key_pause = @intFromEnum(rl.KeyboardKey.pause),

    // Modifier keys
    key_left_shift = @intFromEnum(rl.KeyboardKey.left_shift),
    key_left_control = @intFromEnum(rl.KeyboardKey.left_control),
    key_left_alt = @intFromEnum(rl.KeyboardKey.left_alt),
    key_left_super = @intFromEnum(rl.KeyboardKey.left_super),
    key_right_shift = @intFromEnum(rl.KeyboardKey.right_shift),
    key_right_control = @intFromEnum(rl.KeyboardKey.right_control),
    key_right_alt = @intFromEnum(rl.KeyboardKey.right_alt),
    key_right_super = @intFromEnum(rl.KeyboardKey.right_super),

    // Numeric keypad
    key_kp_0 = @intFromEnum(rl.KeyboardKey.kp_0),
    key_kp_1 = @intFromEnum(rl.KeyboardKey.kp_1),
    key_kp_2 = @intFromEnum(rl.KeyboardKey.kp_2),
    key_kp_3 = @intFromEnum(rl.KeyboardKey.kp_3),
    key_kp_4 = @intFromEnum(rl.KeyboardKey.kp_4),
    key_kp_5 = @intFromEnum(rl.KeyboardKey.kp_5),
    key_kp_6 = @intFromEnum(rl.KeyboardKey.kp_6),
    key_kp_7 = @intFromEnum(rl.KeyboardKey.kp_7),
    key_kp_8 = @intFromEnum(rl.KeyboardKey.kp_8),
    key_kp_9 = @intFromEnum(rl.KeyboardKey.kp_9),
    key_kp_decimal = @intFromEnum(rl.KeyboardKey.kp_decimal),
    key_kp_divide = @intFromEnum(rl.KeyboardKey.kp_divide),
    key_kp_multiply = @intFromEnum(rl.KeyboardKey.kp_multiply),
    key_kp_subtract = @intFromEnum(rl.KeyboardKey.kp_subtract),
    key_kp_add = @intFromEnum(rl.KeyboardKey.kp_add),
    key_kp_enter = @intFromEnum(rl.KeyboardKey.kp_enter),
    key_kp_equal = @intFromEnum(rl.KeyboardKey.kp_equal),

    // Number keys
    key_0 = @intFromEnum(rl.KeyboardKey.zero),
    key_1 = @intFromEnum(rl.KeyboardKey.one),
    key_2 = @intFromEnum(rl.KeyboardKey.two),
    key_3 = @intFromEnum(rl.KeyboardKey.three),
    key_4 = @intFromEnum(rl.KeyboardKey.four),
    key_5 = @intFromEnum(rl.KeyboardKey.five),
    key_6 = @intFromEnum(rl.KeyboardKey.six),
    key_7 = @intFromEnum(rl.KeyboardKey.seven),
    key_8 = @intFromEnum(rl.KeyboardKey.eight),
    key_9 = @intFromEnum(rl.KeyboardKey.nine),

    // Punctuation and symbol keys
    key_apostrophe = @intFromEnum(rl.KeyboardKey.apostrophe), // '
    key_comma = @intFromEnum(rl.KeyboardKey.comma), // ,
    key_minus = @intFromEnum(rl.KeyboardKey.minus), // -
    key_period = @intFromEnum(rl.KeyboardKey.period), // .
    key_slash = @intFromEnum(rl.KeyboardKey.slash), // /
    key_semicolon = @intFromEnum(rl.KeyboardKey.semicolon), // ;
    key_equal = @intFromEnum(rl.KeyboardKey.equal), // =
    key_left_bracket = @intFromEnum(rl.KeyboardKey.left_bracket), // [
    key_backslash = @intFromEnum(rl.KeyboardKey.backslash), // \
    key_right_bracket = @intFromEnum(rl.KeyboardKey.right_bracket), // ]
    key_grave = @intFromEnum(rl.KeyboardKey.grave), // `

    // Additional special keys
    key_menu = @intFromEnum(rl.KeyboardKey.kb_menu), // Menu key (Windows/Context Menu)

    pub fn toString(self: KeyCode) []const u8 {
        return switch (self) {
            .key_a => "A",
            .key_b => "B",
            .key_c => "C",
            .key_d => "D",
            .key_e => "E",
            .key_f => "F",
            .key_g => "G",
            .key_h => "H",
            .key_i => "I",
            .key_j => "J",
            .key_k => "K",
            .key_l => "L",
            .key_m => "M",
            .key_n => "N",
            .key_o => "O",
            .key_p => "P",
            .key_q => "Q",
            .key_r => "R",
            .key_s => "S",
            .key_t => "T",
            .key_u => "U",
            .key_v => "V",
            .key_w => "W",
            .key_x => "X",
            .key_y => "Y",
            .key_z => "Z",
            .key_0 => "0",
            .key_1 => "1",
            .key_2 => "2",
            .key_3 => "3",
            .key_4 => "4",
            .key_5 => "5",
            .key_6 => "6",
            .key_7 => "7",
            .key_8 => "8",
            .key_9 => "9",
            .key_f1 => "F1",
            .key_f2 => "F2",
            .key_f3 => "F3",
            .key_f4 => "F4",
            .key_f5 => "F5",
            .key_f6 => "F6",
            .key_f7 => "F7",
            .key_f8 => "F8",
            .key_f9 => "F9",
            .key_f10 => "F10",
            .key_f11 => "F11",
            .key_f12 => "F12",
            .key_space => "Space",
            .key_escape => "Escape",
            .key_enter => "Enter",
            .key_tab => "Tab",
            .key_backspace => "Backspace",
            .key_insert => "Insert",
            .key_delete => "Delete",
            .key_right => "Right",
            .key_left => "Left",
            .key_down => "Down",
            .key_up => "Up",
            .key_page_up => "PageUp",
            .key_page_down => "PageDown",
            .key_home => "Home",
            .key_end => "End",
            .key_caps_lock => "CapsLock",
            .key_scroll_lock => "ScrollLock",
            .key_num_lock => "NumLock",
            .key_print_screen => "PrintScreen",
            .key_pause => "Pause",
            .key_left_shift => "LeftShift",
            .key_left_control => "LeftCtrl",
            .key_left_alt => "LeftAlt",
            .key_left_super => "LeftSuper",
            .key_right_shift => "RightShift",
            .key_right_control => "RightCtrl",
            .key_right_alt => "RightAlt",
            .key_right_super => "RightSuper",
            .key_apostrophe => "'",
            .key_comma => ",",
            .key_minus => "-",
            .key_period => ".",
            .key_slash => "/",
            .key_semicolon => ";",
            .key_equal => "=",
            .key_left_bracket => "[",
            .key_backslash => "\\",
            .key_right_bracket => "]",
            .key_grave => "`",
            .key_menu => "Menu",
            else => "Unknown",
        };
    }

    pub fn fromString(str: []const u8) ?KeyCode {
        const string_map = std.StaticStringMap(KeyCode).initComptime(.{
            .{ "A", .key_a },
            .{ "B", .key_b },
            .{ "C", .key_c },
            .{ "D", .key_d },
            .{ "E", .key_e },
            .{ "F", .key_f },
            .{ "G", .key_g },
            .{ "H", .key_h },
            .{ "I", .key_i },
            .{ "J", .key_j },
            .{ "K", .key_k },
            .{ "L", .key_l },
            .{ "M", .key_m },
            .{ "N", .key_n },
            .{ "O", .key_o },
            .{ "P", .key_p },
            .{ "Q", .key_q },
            .{ "R", .key_r },
            .{ "S", .key_s },
            .{ "T", .key_t },
            .{ "U", .key_u },
            .{ "V", .key_v },
            .{ "W", .key_w },
            .{ "X", .key_x },
            .{ "Y", .key_y },
            .{ "Z", .key_z },
            .{ "0", .key_0 },
            .{ "1", .key_1 },
            .{ "2", .key_2 },
            .{ "3", .key_3 },
            .{ "4", .key_4 },
            .{ "5", .key_5 },
            .{ "6", .key_6 },
            .{ "7", .key_7 },
            .{ "8", .key_8 },
            .{ "9", .key_9 },
            .{ "F1", .key_f1 },
            .{ "F2", .key_f2 },
            .{ "F3", .key_f3 },
            .{ "F4", .key_f4 },
            .{ "F5", .key_f5 },
            .{ "F6", .key_f6 },
            .{ "F7", .key_f7 },
            .{ "F8", .key_f8 },
            .{ "F9", .key_f9 },
            .{ "F10", .key_f10 },
            .{ "F11", .key_f11 },
            .{ "F12", .key_f12 },
            .{ "Space", .key_space },
            .{ "Escape", .key_escape },
            .{ "Enter", .key_enter },
            .{ "Tab", .key_tab },
            .{ "Backspace", .key_backspace },
            .{ "Insert", .key_insert },
            .{ "Delete", .key_delete },
            .{ "Right", .key_right },
            .{ "Left", .key_left },
            .{ "Down", .key_down },
            .{ "Up", .key_up },
            .{ "PageUp", .key_page_up },
            .{ "PageDown", .key_page_down },
            .{ "Home", .key_home },
            .{ "End", .key_end },
            .{ "CapsLock", .key_caps_lock },
            .{ "ScrollLock", .key_scroll_lock },
            .{ "NumLock", .key_num_lock },
            .{ "PrintScreen", .key_print_screen },
            .{ "Pause", .key_pause },
            .{ "LeftShift", .key_left_shift },
            .{ "LeftCtrl", .key_left_control },
            .{ "LeftAlt", .key_left_alt },
            .{ "LeftSuper", .key_left_super },
            .{ "RightShift", .key_right_shift },
            .{ "RightCtrl", .key_right_control },
            .{ "RightAlt", .key_right_alt },
            .{ "RightSuper", .key_right_super },
            .{ "'", .key_apostrophe },
            .{ ",", .key_comma },
            .{ "-", .key_minus },
            .{ ".", .key_period },
            .{ "/", .key_slash },
            .{ ";", .key_semicolon },
            .{ "=", .key_equal },
            .{ "[", .key_left_bracket },
            .{ "\\", .key_backslash },
            .{ "]", .key_right_bracket },
            .{ "`", .key_grave },
            .{ "Menu", .key_menu },
        });
        return string_map.get(str);
    }
};

/// Mouse button codes
pub const MouseButton = enum(c_int) {
    left = @intFromEnum(rl.MouseButton.left),
    right = @intFromEnum(rl.MouseButton.right),
    middle = @intFromEnum(rl.MouseButton.middle),
    side = @intFromEnum(rl.MouseButton.side),
    extra = @intFromEnum(rl.MouseButton.extra),
    forward = @intFromEnum(rl.MouseButton.forward),
    back = @intFromEnum(rl.MouseButton.back),

    pub fn toString(self: MouseButton) []const u8 {
        return switch (self) {
            .left => "MouseLeft",
            .right => "MouseRight",
            .middle => "MouseMiddle",
            .side => "MouseSide",
            .extra => "MouseExtra",
            .forward => "MouseForward",
            .back => "MouseBack",
        };
    }

    pub fn fromString(str: []const u8) ?MouseButton {
        const string_map = std.StaticStringMap(MouseButton).initComptime(.{
            .{ "MouseLeft", .left },
            .{ "MouseRight", .right },
            .{ "MouseMiddle", .middle },
            .{ "MouseSide", .side },
            .{ "MouseExtra", .extra },
            .{ "MouseForward", .forward },
            .{ "MouseBack", .back },
        });
        return string_map.get(str);
    }
};

/// Gamepad button codes
pub const GamepadButton = enum(c_int) {
    unknown = @intFromEnum(rl.GamepadButton.unknown),
    /// D-pad up
    left_face_up = @intFromEnum(rl.GamepadButton.left_face_up),
    /// D-pad right
    left_face_right = @intFromEnum(rl.GamepadButton.left_face_right),
    /// D-pad down
    left_face_down = @intFromEnum(rl.GamepadButton.left_face_down),
    /// D-pad left
    left_face_left = @intFromEnum(rl.GamepadButton.left_face_left),
    /// Cross/Y/Bottom button
    right_face_up = @intFromEnum(rl.GamepadButton.right_face_up),
    // Circle/B/Right button
    right_face_right = @intFromEnum(rl.GamepadButton.right_face_right),
    /// Square/X/Left button
    right_face_down = @intFromEnum(rl.GamepadButton.right_face_down),
    /// Triagnle/X/Top button
    right_face_left = @intFromEnum(rl.GamepadButton.right_face_left),
    left_trigger_1 = @intFromEnum(rl.GamepadButton.left_trigger_1),
    left_trigger_2 = @intFromEnum(rl.GamepadButton.left_trigger_2),
    right_trigger_1 = @intFromEnum(rl.GamepadButton.right_trigger_1),
    right_trigger_2 = @intFromEnum(rl.GamepadButton.right_trigger_2),
    /// Select/Back button
    back = @intFromEnum(rl.GamepadButton.middle_left),
    /// Center/Home button
    menu = @intFromEnum(rl.GamepadButton.middle),
    /// Start button
    start = @intFromEnum(rl.GamepadButton.middle_right),
    left_thumb = @intFromEnum(rl.GamepadButton.left_thumb),
    right_thumb = @intFromEnum(rl.GamepadButton.right_thumb),

    pub fn toString(self: GamepadButton) []const u8 {
        return switch (self) {
            .unknown => "GamepadUnknown",
            .left_face_up => "GamepadLeftFaceUp",
            .left_face_right => "GamepadLeftFaceRight",
            .left_face_down => "GamepadLeftFaceDown",
            .left_face_left => "GamepadLeftFaceLeft",
            .right_face_up => "GamepadRightFaceUp",
            .right_face_right => "GamepadRightFaceRight",
            .right_face_down => "GamepadRightFaceDown",
            .right_face_left => "GamepadRightFaceLeft",
            .left_trigger_1 => "GamepadLeftTrigger1",
            .left_trigger_2 => "GamepadLeftTrigger2",
            .right_trigger_1 => "GamepadRightTrigger1",
            .right_trigger_2 => "GamepadRightTrigger2",
            .back => "GamepadBack",
            .menu => "GamepadMenu",
            .start => "GamepadStart",
            .left_thumb => "GamepadLeftThumb",
            .right_thumb => "GamepadRightThumb",
        };
    }

    pub fn fromString(str: []const u8) ?GamepadButton {
        const string_map = std.StaticStringMap(GamepadButton).initComptime(.{
            .{ "GamepadUnknown", .unknown },
            .{ "GamepadLeftFaceUp", .left_face_up },
            .{ "GamepadLeftFaceRight", .left_face_right },
            .{ "GamepadLeftFaceDown", .left_face_down },
            .{ "GamepadLeftFaceLeft", .left_face_left },
            .{ "GamepadRightFaceUp", .right_face_up },
            .{ "GamepadRightFaceRight", .right_face_right },
            .{ "GamepadRightFaceDown", .right_face_down },
            .{ "GamepadRightFaceLeft", .right_face_left },
            .{ "GamepadLeftTrigger1", .left_trigger_1 },
            .{ "GamepadLeftTrigger2", .left_trigger_2 },
            .{ "GamepadRightTrigger1", .right_trigger_1 },
            .{ "GamepadRightTrigger2", .right_trigger_2 },
            .{ "GamepadBack", .back },
            .{ "GamepadMenu", .menu },
            .{ "GamepadStart", .start },
            .{ "GamepadLeftThumb", .left_thumb },
            .{ "GamepadRightThumb", .right_thumb },
        });
        return string_map.get(str);
    }
};

/// Touch input types
pub const TouchInput = enum(u32) {
    touch_tap = 0,
    touch_press = 1,
    touch_release = 2,
    touch_move = 3,
    multi_touch_tap = 4,
    multi_touch_press = 5,
    multi_touch_release = 6,
    multi_touch_move = 7,
    multi_touch_two_finger = 8,
    unrecognized = std.math.maxInt(u32),

    pub fn toString(self: TouchInput) []const u8 {
        return switch (self) {
            .touch_tap => "TouchTap",
            .touch_press => "TouchPress",
            .touch_release => "TouchRelease",
            .touch_move => "TouchMove",
            .multi_touch_tap => "MultiTouchTap",
            .multi_touch_press => "MultiTouchPress",
            .multi_touch_release => "MultiTouchRelease",
            .multi_touch_move => "MultiTouchMove",
            .multi_touch_two_finger => "MultiTouchTwoFinger",
            else => "Unrecognized",
        };
    }

    pub fn fromString(str: []const u8) ?TouchInput {
        const string_map = std.StaticStringMap(TouchInput).initComptime(.{
            .{ "TouchTap", .touch_tap },
            .{ "TouchPress", .touch_press },
            .{ "TouchRelease", .touch_release },
            .{ "TouchMove", .touch_move },
            .{ "MultiTouchTap", .multi_touch_tap },
            .{ "MultiTouchPress", .multi_touch_press },
            .{ "MultiTouchRelease", .multi_touch_release },
            .{ "MultiTouchMove", .multi_touch_move },
            .{ "MultiTouchTwoFinger", .multi_touch_two_finger },
        });
        return string_map.get(str);
    }
};

/// Gesture input types
pub const GestureInput = enum(u32) {
    unknown = 0,
    gesture_tap = 1,
    gesture_doubletap = 2,
    gesture_hold = 3,
    gesture_drag = 4,
    gesture_swipe_right = 5,
    gesture_swipe_left = 6,
    gesture_swipe_up = 7,
    gesture_swipe_down = 8,
    gesture_pinch_in = 9,
    gesture_pinch_out = 10,

    pub fn toString(self: GestureInput) []const u8 {
        return switch (self) {
            .gesture_tap => "GestureTap",
            .gesture_doubletap => "GestureDoubleTap",
            .gesture_hold => "GestureHold",
            .gesture_drag => "GestureDrag",
            .gesture_swipe_right => "GestureSwipeRight",
            .gesture_swipe_left => "GestureSwipeLeft",
            .gesture_swipe_up => "GestureSwipeUp",
            .gesture_swipe_down => "GestureSwipeDown",
            .gesture_pinch_in => "GesturePinchIn",
            .gesture_pinch_out => "GesturePinchOut",
            else => "Unknown",
        };
    }

    pub fn fromString(str: []const u8) ?GestureInput {
        const string_map = std.StaticStringMap(GestureInput).initComptime(.{
            .{ "GestureTap", .gesture_tap },
            .{ "GestureDoubleTap", .gesture_doubletap },
            .{ "GestureHold", .gesture_hold },
            .{ "GestureDrag", .gesture_drag },
            .{ "GestureSwipeRight", .gesture_swipe_right },
            .{ "GestureSwipeLeft", .gesture_swipe_left },
            .{ "GestureSwipeUp", .gesture_swipe_up },
            .{ "GestureSwipeDown", .gesture_swipe_down },
            .{ "GesturePinchIn", .gesture_pinch_in },
            .{ "GesturePinchOut", .gesture_pinch_out },
        });
        return string_map.get(str);
    }
};

/// Represents a single input (key, mouse button, gamepad button, touch, or gesture)
pub const InputKey = union(enum) {
    keyboard: KeyCode,
    mouse: MouseButton,
    gamepad: struct {
        gamepad_id: u8,
        button: GamepadButton,
    },
    touch: struct {
        touch_id: u8,
        input: TouchInput,
    },
    gesture: GestureInput,

    pub fn toString(self: InputKey, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        return switch (self) {
            .keyboard => |key| try allocator.dupe(u8, key.toString()),
            .mouse => |button| try allocator.dupe(u8, button.toString()),
            .gamepad => |gamepad| try std.fmt.allocPrint(allocator, "Gamepad{}_{s}", .{ gamepad.gamepad_id, gamepad.button.toString() }),
            .touch => |touch| try std.fmt.allocPrint(allocator, "Touch{}_{s}", .{ touch.touch_id, touch.input.toString() }),
            .gesture => |gesture| try allocator.dupe(u8, gesture.toString()),
        };
    }

    pub fn fromString(str: []const u8, allocator: std.mem.Allocator) ?InputKey {
        _ = allocator;

        // Try keyboard first
        if (KeyCode.fromString(str)) |key| {
            return InputKey{ .keyboard = key };
        }

        // Try mouse
        if (MouseButton.fromString(str)) |button| {
            return InputKey{ .mouse = button };
        }

        // Try gamepad (format: Gamepad0_GamepadLeftFaceUp)
        if (std.mem.startsWith(u8, str, "Gamepad")) {
            if (std.mem.indexOf(u8, str, "_")) |underscore_pos| {
                const gamepad_id_str = str[7..underscore_pos];
                const button_str = str[underscore_pos + 1 ..];

                const gamepad_id = std.fmt.parseInt(u8, gamepad_id_str, 10) catch return null;
                const button = GamepadButton.fromString(button_str) orelse return null;

                return InputKey{ .gamepad = .{ .gamepad_id = gamepad_id, .button = button } };
            }
        }

        // Try touch (format: Touch0_TouchTap)
        if (std.mem.startsWith(u8, str, "Touch")) {
            if (std.mem.indexOf(u8, str, "_")) |underscore_pos| {
                const touch_id_str = str[5..underscore_pos];
                const input_str = str[underscore_pos + 1 ..];

                const touch_id = std.fmt.parseInt(u8, touch_id_str, 10) catch return null;
                const input = TouchInput.fromString(input_str) orelse return null;

                return InputKey{ .touch = .{ .touch_id = touch_id, .input = input } };
            }
        }

        // Try gesture
        if (GestureInput.fromString(str)) |gesture| {
            return InputKey{ .gesture = gesture };
        }

        return null;
    }

    pub fn eql(self: InputKey, other: InputKey) bool {
        return switch (self) {
            .keyboard => |key| switch (other) {
                .keyboard => |other_key| key == other_key,
                else => false,
            },
            .mouse => |button| switch (other) {
                .mouse => |other_button| button == other_button,
                else => false,
            },
            .gamepad => |gamepad| switch (other) {
                .gamepad => |other_gamepad| gamepad.gamepad_id == other_gamepad.gamepad_id and gamepad.button == other_gamepad.button,
                else => false,
            },
            .touch => |touch| switch (other) {
                .touch => |other_touch| touch.touch_id == other_touch.touch_id and touch.input == other_touch.input,
                else => false,
            },
            .gesture => |gesture| switch (other) {
                .gesture => |other_gesture| gesture == other_gesture,
                else => false,
            },
        };
    }
};
