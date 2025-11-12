const std = @import("std");
const testing = std.testing;
const input = @import("input.zig");

const InputKey = input.InputKey;
const KeyCode = input.KeyCode;
const MouseButton = input.MouseButton;
const GamepadButton = input.GamepadButton;
const InputChord = input.InputChord;
const InputAction = input.InputAction;
const InputBinding = input.InputBinding;
const InputBindingCollection = input.InputBindingCollection;
const InputManager = input.InputManager;

test "InputKey equality and string conversion" {
    const allocator = testing.allocator;

    // Test keyboard key
    const key1 = InputKey{ .keyboard = .key_a };
    const key2 = InputKey{ .keyboard = .key_a };
    const key3 = InputKey{ .keyboard = .key_b };

    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));

    // Test string conversion
    const key1_str = try key1.toString(allocator);
    defer allocator.free(key1_str);
    try testing.expectEqualStrings("A", key1_str);

    // Test parsing from string
    const parsed_key = InputKey.fromString("A", allocator);
    try testing.expect(parsed_key != null);
    try testing.expect(parsed_key.?.eql(key1));

    // Test mouse key
    const mouse_key = InputKey{ .mouse = .left };
    const mouse_str = try mouse_key.toString(allocator);
    defer allocator.free(mouse_str);
    try testing.expectEqualStrings("MouseLeft", mouse_str);

    // Test gamepad key
    const gamepad_key = InputKey{ .gamepad = .{ .gamepad_id = 0, .button = .left_face_up } };
    const gamepad_str = try gamepad_key.toString(allocator);
    defer allocator.free(gamepad_str);
    try testing.expectEqualStrings("Gamepad0_GamepadLeftFaceUp", gamepad_str);
}

test "InputChord creation and matching" {
    const allocator = testing.allocator;

    // Create a simple chord with one key
    const key = InputKey{ .keyboard = .key_space };
    var simple_chord = try input.createSimpleChord(key, allocator);
    defer simple_chord.deinit(allocator);

    try testing.expect(simple_chord.keys.items.len == 1);
    try testing.expect(simple_chord.keys.items[0].eql(key));

    // Create a complex chord with multiple keys
    var complex_chord = InputChord.init(allocator);
    defer complex_chord.deinit(allocator);

    try complex_chord.add(allocator, InputKey{ .keyboard = .key_left_control });
    try complex_chord.add(allocator, InputKey{ .keyboard = .key_e });

    try testing.expect(complex_chord.keys.items.len == 2);
}

test "InputChord string serialization" {
    const allocator = testing.allocator;

    // Test single key chord
    var chord = InputChord.init(allocator);
    defer chord.deinit(allocator);
    try chord.add(allocator, InputKey{ .keyboard = .key_space });

    const chord_str = try chord.toString(allocator);
    defer allocator.free(chord_str);
    try testing.expectEqualStrings("Space", chord_str);

    // Test parsing back
    const parsed_chord = try InputChord.fromString(chord_str, allocator);
    try testing.expect(parsed_chord != null);
    var parsed = parsed_chord.?;
    defer parsed.deinit(allocator);

    try testing.expect(chord.matches(parsed.keys.items));

    // Test complex chord
    var complex_chord = InputChord.init(allocator);
    defer complex_chord.deinit(allocator);
    try complex_chord.add(allocator, InputKey{ .keyboard = .key_left_control });
    try complex_chord.add(allocator, InputKey{ .keyboard = .key_e });

    const complex_str = try complex_chord.toString(allocator);
    defer allocator.free(complex_str);
    try testing.expect(std.mem.indexOf(u8, complex_str, "LeftCtrl") != null);
    try testing.expect(std.mem.indexOf(u8, complex_str, "E") != null);
    try testing.expect(std.mem.indexOf(u8, complex_str, "+") != null);
}

test "InputBinding creation and matching" {
    const allocator = testing.allocator;

    // Create a binding
    var chord = InputChord.init(allocator);
    try chord.add(allocator, InputKey{ .keyboard = .key_space });

    const action = try InputAction.init(allocator, "jump", "Jump action");
    var binding = InputBinding.init(chord, action);
    defer binding.deinit(allocator);

    try testing.expectEqualStrings("jump", binding.action.name);
    try testing.expectEqualStrings("Jump action", binding.action.description);
    try testing.expect(binding.enabled);

    // Test matching
    const pressed_keys = [_]InputKey{InputKey{ .keyboard = .key_space }};
    try testing.expect(binding.matches(pressed_keys[0..]));

    // Test disabling
    binding.enabled = false;
    try testing.expect(!binding.matches(pressed_keys[0..]));
}

test "InputBindings collection operations" {
    const allocator = testing.allocator;

    var bindings = InputBindingCollection.init(allocator);
    defer bindings.deinit();

    // Add first binding (single key)
    {
        var chord = InputChord.init(allocator);
        try chord.add(allocator, InputKey{ .keyboard = .key_e });
        const action = try InputAction.init(allocator, "interact", "Interact with objects");
        try bindings.addBinding(InputBinding.init(chord, action));
    }

    // Add second binding (complex chord)
    {
        var chord = InputChord.init(allocator);
        try chord.add(allocator, InputKey{ .keyboard = .key_left_control });
        try chord.add(allocator, InputKey{ .keyboard = .key_e });
        const action = try InputAction.init(allocator, "advanced_interact", "Advanced interaction");
        try bindings.addBinding(InputBinding.init(chord, action));
    }

    // Test that longer chord takes precedence
    const pressed_keys = [_]InputKey{
        InputKey{ .keyboard = .key_left_control },
        InputKey{ .keyboard = .key_e },
    };

    const best_match = bindings.findBestMatch(pressed_keys[0..]);
    try testing.expect(best_match != null);
    try testing.expectEqualStrings("advanced_interact", best_match.?.action.name);

    // Test single key match
    const single_pressed = [_]InputKey{InputKey{ .keyboard = .key_e }};
    const single_match = bindings.findBestMatch(single_pressed[0..]);
    try testing.expect(single_match != null);
    try testing.expectEqualStrings("interact", single_match.?.action.name);

    // Test getting binding by name
    const found_binding = bindings.getBinding("interact");
    try testing.expect(found_binding != null);
    try testing.expectEqualStrings("interact", found_binding.?.action.name);

    // Test removing binding
    try testing.expect(bindings.removeBinding("interact"));
    try testing.expect(bindings.getBinding("interact") == null);
}

test "InputChord comparison and sorting" {
    const allocator = testing.allocator;

    // Create chords of different lengths
    var short_chord = InputChord.init(allocator);
    defer short_chord.deinit(allocator);
    try short_chord.add(allocator, .{ .keyboard = .key_e });

    var long_chord = InputChord.init(allocator);
    defer long_chord.deinit(allocator);
    try long_chord.add(allocator, .{ .keyboard = .key_left_control });
    try long_chord.add(allocator, .{ .keyboard = .key_e });

    // Longer chord should come first (have lower order)
    try testing.expect(long_chord.compare(&short_chord) == .lt);
    try testing.expect(short_chord.compare(&long_chord) == .gt);
    try testing.expect(short_chord.compare(&short_chord) == .eq);
}

test "Serialization round-trip" {
    const allocator = testing.allocator;

    // Create bindings
    var original_bindings = InputBindingCollection.init(allocator);
    defer original_bindings.deinit();

    // Add some test bindings
    {
        var chord = InputChord.init(allocator);
        try chord.add(allocator, InputKey{ .keyboard = .key_space });
        const action = try InputAction.init(allocator, "jump", "Jump action");
        try original_bindings.addBinding(InputBinding.init(chord, action));
    }

    {
        var chord = InputChord.init(allocator);
        try chord.add(allocator, .{ .keyboard = .key_left_control });
        try chord.add(allocator, .{ .keyboard = .key_e });
        const action = try InputAction.init(allocator, "advanced_interact", "Advanced interaction");
        try original_bindings.addBinding(InputBinding.init(chord, action));
    }

    // Serialize to string
    const json_str = try input.serializeToString(&original_bindings, allocator);
    defer allocator.free(json_str);

    // Verify JSON contains expected content
    try testing.expect(std.mem.indexOf(u8, json_str, "jump") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "Space") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "LeftCtrl+E") != null);

    // Deserialize back
    var deserialized_bindings = try input.deserializeFromString(json_str, allocator);
    defer deserialized_bindings.deinit();

    // Verify we got the same bindings back
    const original_all = original_bindings.getAllBindings();
    const deserialized_all = deserialized_bindings.getAllBindings();

    try testing.expectEqual(original_all.len, deserialized_all.len);

    // Check that we can find the same actions
    try testing.expect(deserialized_bindings.getBinding("jump") != null);
    try testing.expect(deserialized_bindings.getBinding("advanced_interact") != null);
}

test "Input manager basic functionality" {
    const allocator = testing.allocator;

    var manager = InputManager.init(allocator);
    defer manager.deinit();

    // Add a test binding
    var chord = InputChord.init(allocator);
    try chord.add(allocator, .{ .keyboard = .key_space });
    const action = try InputAction.init(allocator, "jump", "Jump action");
    try manager.addBinding(InputBinding.init(chord, action));

    // Test that we can get the bindings
    const bindings = manager.getBindings();
    try testing.expect(bindings.getBinding("jump") != null);

    // Test enabling/disabling
    try testing.expect(manager.setBindingEnabled("jump", false));
    try testing.expect(manager.setBindingEnabled("nonexistent", false) == false);
}

test "InputBindingBuilder" {
    const allocator = testing.allocator;

    var builder = input.InputBindingBuilder.init(allocator);
    defer builder.deinit();

    // Test building a simple binding
    var binding1 = try builder
        .withKeyboard(.key_space)
        .withAction("jump", "Jump action")
        .build();
    defer binding1.deinit(allocator);

    try testing.expectEqualStrings("jump", binding1.action.name);
    try testing.expect(binding1.enabled);

    // Test building a complex binding
    var binding2 = try builder
        .withKeyboard(.key_left_control)
        .withKeyboard(.key_e)
        .withAction("advanced_interact", "Advanced interaction")
        .enabled(false)
        .build();
    defer binding2.deinit(allocator);

    try testing.expectEqualStrings("advanced_interact", binding2.action.name);
    try testing.expect(!binding2.enabled);
    try testing.expectEqual(@as(usize, 2), binding2.chord.len());

    // Test building from chord string
    var binding3 = try builder
        .withChord("LeftCtrl+A")
        .withAction("select_all", "Select all")
        .build();
    defer binding3.deinit(allocator);

    try testing.expectEqualStrings("select_all", binding3.action.name);
    try testing.expectEqual(@as(usize, 2), binding3.chord.len());
}

test "Binding validation" {
    const allocator = testing.allocator;

    var bindings = InputBindingCollection.init(allocator);
    defer bindings.deinit();

    // Add conflicting bindings (same chord, different actions)
    {
        var chord = InputChord{ .keys = std.ArrayList(InputKey){} };
        try chord.add(allocator, InputKey{ .keyboard = .key_space });
        const action = try InputAction.init(allocator, "jump", "Jump action");
        try bindings.addBinding(InputBinding.init(chord, action));
    }

    {
        var chord = InputChord{ .keys = std.ArrayList(InputKey){} };
        try chord.add(allocator, InputKey{ .keyboard = .key_space });
        const action = try InputAction.init(allocator, "fire", "Fire weapon");
        try bindings.addBinding(InputBinding.init(chord, action));
    }

    // Validate and check for conflicts
    const conflicts = try input.validateBindings(&bindings, allocator);
    defer {
        for (conflicts) |conflict| {
            allocator.free(conflict);
        }
        allocator.free(conflicts);
    }

    try testing.expect(conflicts.len > 0);
    try testing.expect(std.mem.indexOf(u8, conflicts[0], "Duplicate chord") != null);
}

test "Touch input key equality and string conversion" {
    const allocator = testing.allocator;

    // Test touch key
    const touch_key1 = InputKey{ .touch = .{ .touch_id = 0, .input = .touch_tap } };
    const touch_key2 = InputKey{ .touch = .{ .touch_id = 0, .input = .touch_tap } };
    const touch_key3 = InputKey{ .touch = .{ .touch_id = 1, .input = .touch_tap } };
    const touch_key4 = InputKey{ .touch = .{ .touch_id = 0, .input = .touch_press } };

    try testing.expect(touch_key1.eql(touch_key2));
    try testing.expect(!touch_key1.eql(touch_key3)); // Different touch ID
    try testing.expect(!touch_key1.eql(touch_key4)); // Different touch input type

    // Test string conversion
    const touch_str = try touch_key1.toString(allocator);
    defer allocator.free(touch_str);
    try testing.expectEqualStrings("Touch0_TouchTap", touch_str);

    // Test parsing from string
    const parsed_touch = InputKey.fromString("Touch1_TouchPress", allocator);
    try testing.expect(parsed_touch != null);
    const expected_touch = InputKey{ .touch = .{ .touch_id = 1, .input = .touch_press } };
    try testing.expect(parsed_touch.?.eql(expected_touch));

    // Test multi-touch
    const multi_touch = InputKey{ .touch = .{ .touch_id = 2, .input = .multi_touch_two_finger } };
    const multi_str = try multi_touch.toString(allocator);
    defer allocator.free(multi_str);
    try testing.expectEqualStrings("Touch2_MultiTouchTwoFinger", multi_str);
}

test "Gesture input key equality and string conversion" {
    const allocator = testing.allocator;

    // Test gesture key
    const gesture_key1 = InputKey{ .gesture = .gesture_tap };
    const gesture_key2 = InputKey{ .gesture = .gesture_tap };
    const gesture_key3 = InputKey{ .gesture = .gesture_swipe_up };

    try testing.expect(gesture_key1.eql(gesture_key2));
    try testing.expect(!gesture_key1.eql(gesture_key3));

    // Test string conversion
    const gesture_str = try gesture_key1.toString(allocator);
    defer allocator.free(gesture_str);
    try testing.expectEqualStrings("GestureTap", gesture_str);

    // Test parsing from string
    const parsed_gesture = InputKey.fromString("GestureSwipeRight", allocator);
    try testing.expect(parsed_gesture != null);
    const expected_gesture = InputKey{ .gesture = .gesture_swipe_right };
    try testing.expect(parsed_gesture.?.eql(expected_gesture));

    // Test pinch gestures
    const pinch_in = InputKey{ .gesture = .gesture_pinch_in };
    const pinch_str = try pinch_in.toString(allocator);
    defer allocator.free(pinch_str);
    try testing.expectEqualStrings("GesturePinchIn", pinch_str);
}

test "Touch and gesture chord creation" {
    const allocator = testing.allocator;

    // Create a chord with touch input
    var chord = InputChord.init(allocator);
    defer chord.deinit(allocator);

    const touch_key = InputKey{ .touch = .{ .touch_id = 0, .input = .touch_tap } };
    try chord.keys.append(allocator, touch_key);

    try testing.expect(chord.keys.items.len == 1);
    try testing.expect(chord.keys.items[0].eql(touch_key));

    // Create a chord with gesture input
    var gesture_chord = InputChord.init(allocator);
    defer gesture_chord.deinit(allocator);

    const gesture_key = InputKey{ .gesture = .gesture_swipe_up };
    try gesture_chord.keys.append(allocator, gesture_key);

    try testing.expect(gesture_chord.keys.items.len == 1);
    try testing.expect(gesture_chord.keys.items[0].eql(gesture_key));

    // Create a mixed chord (touch + keyboard)
    var mixed_chord = InputChord.init(allocator);
    defer mixed_chord.deinit(allocator);

    try mixed_chord.keys.append(allocator, touch_key);
    try mixed_chord.keys.append(allocator, InputKey{ .keyboard = .key_a });

    try testing.expect(mixed_chord.keys.items.len == 2);
}

test "Touch and gesture binding processing" {
    const allocator = testing.allocator;

    // Create a touch binding
    var touch_chord = InputChord.init(allocator);

    const touch_key = InputKey{ .touch = .{ .touch_id = 0, .input = .touch_tap } };
    try touch_chord.keys.append(allocator, touch_key);

    const test_action = try InputAction.init(allocator, "touch_test", "Touch test action");
    var binding = InputBinding.init(touch_chord, test_action);
    defer binding.deinit(allocator);

    // Test chord matching
    const keys = [_]InputKey{touch_key};
    try testing.expect(binding.matches(&keys));

    // Test action name
    try testing.expectEqualStrings("touch_test", binding.action.name);

    // Create a gesture binding
    var gesture_chord = InputChord.init(allocator);

    const gesture_key = InputKey{ .gesture = .gesture_pinch_out };
    try gesture_chord.keys.append(allocator, gesture_key);

    const gesture_action = try InputAction.init(allocator, "zoom_out", "Zoom out action");
    var gesture_binding = InputBinding.init(gesture_chord, gesture_action);
    defer gesture_binding.deinit(allocator);

    // Test gesture chord matching
    const gesture_keys = [_]InputKey{gesture_key};
    try testing.expect(gesture_binding.matches(&gesture_keys));

    // Test gesture action name
    try testing.expectEqualStrings("zoom_out", gesture_binding.action.name);
}
