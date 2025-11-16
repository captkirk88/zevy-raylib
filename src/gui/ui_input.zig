//! UI Input System - Event-based UI interaction handling
//!
//! This module provides ECS-based UI interaction detection that integrates with InputManager.
//! It separates input polling, interaction detection, and logic handling into proper phases:
//!
//! Phase 1 (PreUpdate): InputManager.update() - polls all input devices
//!
//! Phase 2 (Update): UI interaction detection - checks bounds, emits events
//!
//! Phase 3 (Update): Game logic - consumes UI events
//!
//! Phase 4 (Draw): Rendering - no logic, just visuals
//!
//! Usage example:
//! ```zig
//! // Setup in startup
//! try setupUIInputBindings(&input_manager, allocator);
//! try scheduler.registerEvent(&manager, UIClickEvent);
//! try scheduler.registerEvent(&manager, UIHoverEvent);
//! try scheduler.registerEvent(&manager, UIValueChangedEvent);
//!
//! // Add systems to scheduler
//! scheduler.addSystem(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Update),
//!     uiInteractionDetectionSystem, zevy_ecs.DefaultParamRegistry);
//! scheduler.addSystem(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Update),
//!     handleMainMenuButtons, zevy_ecs.DefaultParamRegistry);
//! ```

const std = @import("std");
const rl = @import("raylib");
const zevy_ecs = @import("zevy_ecs");
const input = @import("../input/input.zig");
const components = @import("ui_components.zig");

// =============================================================================
// UI INTERACTION EVENTS
// =============================================================================

/// Event emitted when a UI element is clicked/tapped
pub const UIClickEvent = struct {
    /// The entity that was clicked
    entity: zevy_ecs.Entity,
    /// The input device that triggered the click
    input_device: input.InputDevice,
    /// The position where the click occurred
    position: rl.Vector2,
    /// The mouse button or touch index
    button: input.MouseButton,
};

/// Event emitted when a UI element gains or loses hover state
pub const UIHoverEvent = struct {
    /// The entity that is being hovered
    entity: zevy_ecs.Entity,
    /// The position of the cursor/touch
    position: rl.Vector2,
    /// True if hover started, false if hover ended
    entered: bool,
};

/// Event emitted when a UI element's value changes (sliders, spinners, etc.)
pub const UIValueChangedEvent = struct {
    /// The entity whose value changed
    entity: zevy_ecs.Entity,
    /// The type of component that changed
    component_type_name: []const u8,
    /// The old value (generic f32 for numeric components)
    old_value: f32,
    /// The new value
    new_value: f32,
};

/// Event emitted when a UI element gains or loses focus
pub const UIFocusEvent = struct {
    /// The entity that changed focus state
    entity: zevy_ecs.Entity,
    /// True if focus was gained, false if lost
    gained: bool,
};

/// Event emitted when a toggle/checkbox state changes
pub const UIToggleEvent = struct {
    /// The entity that was toggled
    entity: zevy_ecs.Entity,
    /// The new checked state
    checked: bool,
};

/// Event emitted when a text input's content changes
pub const UITextChangedEvent = struct {
    /// The entity whose text changed
    entity: zevy_ecs.Entity,
    /// The new text content (not owned, temporary reference)
    text: []const u8,
};

/// Event emitted when a dropdown/combo box selection changes
pub const UISelectionChangedEvent = struct {
    /// The entity whose selection changed
    entity: zevy_ecs.Entity,
    /// The old selected index
    old_index: i32,
    /// The new selected index
    new_index: i32,
};

// =============================================================================
// INPUT BINDINGS SETUP
// =============================================================================

/// Setup default UI input bindings for mouse, touch, and gamepad
/// This should be called during application startup
pub fn setupUIInputBindings(input_mgr: *input.InputManager, allocator: std.mem.Allocator) !void {
    // Mouse left click
    var mouse_click = input.InputChord.init(allocator);
    try mouse_click.add(allocator, input.InputKey{ .mouse = .left });
    try input_mgr.addBinding(.{
        .chord = mouse_click,
        .action = try input.InputAction.init(allocator, "ui_click", "UI click/select"),
        .enabled = true,
    });

    // Touch tap (touch point 0)
    var touch_tap = input.InputChord.init(allocator);
    try touch_tap.add(allocator, input.InputKey{ .touch = .{
        .touch_id = 0,
        .input = .touch_tap,
    } });
    try input_mgr.addBinding(.{
        .chord = touch_tap,
        .action = try input.InputAction.init(allocator, "ui_click", "UI click/select"),
        .enabled = true,
    });

    // Gamepad A button (confirm)
    var gamepad_confirm = input.InputChord.init(allocator);
    try gamepad_confirm.add(allocator, input.InputKey{ .gamepad = .{
        .gamepad_id = 0,
        .button = .left_face_down,
    } });
    try input_mgr.addBinding(.{
        .chord = gamepad_confirm,
        .action = try input.InputAction.init(allocator, "ui_confirm", "UI confirm/select"),
        .enabled = true,
    });

    // Gamepad B button (cancel)
    var gamepad_cancel = input.InputChord.init(allocator);
    try gamepad_cancel.add(allocator, input.InputKey{ .gamepad = .{
        .gamepad_id = 0,
        .button = .left_face_right,
    } });
    try input_mgr.addBinding(.{
        .chord = gamepad_cancel,
        .action = try input.InputAction.init(allocator, "ui_cancel", "UI cancel/back"),
        .enabled = true,
    });

    // Space key (alternate confirm)
    var space_confirm = input.InputChord.init(allocator);
    try space_confirm.add(allocator, input.InputKey{ .keyboard = .key_space });
    try input_mgr.addBinding(.{
        .chord = space_confirm,
        .action = try input.InputAction.init(allocator, "ui_confirm", "UI confirm/select"),
        .enabled = true,
    });

    // Enter key (confirm)
    var enter_confirm = input.InputChord.init(allocator);
    try enter_confirm.add(allocator, input.InputKey{ .keyboard = .key_enter });
    try input_mgr.addBinding(.{
        .chord = enter_confirm,
        .action = try input.InputAction.init(allocator, "ui_confirm", "UI confirm/select"),
        .enabled = true,
    });

    // Escape key (cancel)
    var escape_cancel = input.InputChord.init(allocator);
    try escape_cancel.add(allocator, input.InputKey{ .keyboard = .key_escape });
    try input_mgr.addBinding(.{
        .chord = escape_cancel,
        .action = try input.InputAction.init(allocator, "ui_cancel", "UI cancel/back"),
        .enabled = true,
    });
}

// =============================================================================
// UI INTERACTION DETECTION SYSTEMS
// =============================================================================

/// Main UI interaction detection system
/// Detects clicks, hovers, and interactions with all UI components
/// This system should run in the Update stage, after InputManager.update()
pub fn uiInteractionDetectionSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    click_writer: zevy_ecs.EventWriter(UIClickEvent),
    hover_writer: zevy_ecs.EventWriter(UIHoverEvent),

    // Query for buttons
    button_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        button: components.UIButton,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    _ = manager;

    // Get input position (handles mouse/touch automatically)
    const cursor_pos = input.getMousePosition() orelse return;

    // Check if click action was triggered this frame
    const click_triggered = input_mgr.ptr.wasActionTriggered("ui_click") or
        input_mgr.ptr.wasActionTriggered("ui_confirm");

    // Process buttons
    while (button_query.next()) |item| {

        // Skip invisible elements
        if (item.visible) |v| {
            if (!v.visible) continue;
        }

        const bounds = item.rect.toRectangle();
        const is_hovered = rl.checkCollisionPointRec(cursor_pos, bounds);

        // Track hover state changes
        const was_hovered = item.button.hovered;
        item.button.*.hovered = is_hovered;

        // Emit hover events on state change
        if (is_hovered and !was_hovered) {
            hover_writer.write(.{
                .entity = item.entity,
                .position = cursor_pos,
                .entered = true,
            });
        } else if (!is_hovered and was_hovered) {
            hover_writer.write(.{
                .entity = item.entity,
                .position = cursor_pos,
                .entered = false,
            });
        }

        // Handle clicks
        if (is_hovered and click_triggered and item.button.enabled) {
            item.button.*.pressed = true;
            click_writer.write(.{
                .entity = item.entity,
                .input_device = .mouse, // TODO: Detect actual device from InputManager
                .position = cursor_pos,
                .button = .left,
            });
        } else {
            // Reset pressed state every frame when not clicking
            item.button.*.pressed = false;
        }
    }
}

/// Slider interaction detection system
/// Handles dragging sliders to change values
pub fn sliderInteractionSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    value_writer: zevy_ecs.EventWriter(UIValueChangedEvent),
    query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        slider: components.UISlider,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    _ = manager;

    // Get cursor position
    const cursor_pos = input.getMousePosition() orelse return;

    // Check if primary input is being held down
    const is_holding = input_mgr.ptr.isActionActive("ui_click");

    if (!is_holding) return;

    // Process sliders
    while (query.next()) |item| {
        // Skip invisible or disabled elements
        if (item.visible) |v| {
            if (!v.visible) continue;
        }
        if (!item.slider.*.enabled) continue;

        const bounds = item.rect.toRectangle();
        const is_hovered = rl.checkCollisionPointRec(cursor_pos, bounds);

        if (is_hovered) {
            const old_value = item.slider.*.value;

            // Calculate new value from cursor position
            const normalized = std.math.clamp(
                (cursor_pos.x - bounds.x) / bounds.width,
                0.0,
                1.0,
            );
            const new_value = item.slider.*.min_value +
                (normalized * (item.slider.*.max_value - item.slider.*.min_value));

            item.slider.*.setValue(new_value);

            // Emit value changed event if value actually changed
            if (@abs(new_value - old_value) > 0.001) {
                value_writer.write(.{
                    .entity = item.entity,
                    .component_type_name = "UISlider",
                    .old_value = old_value,
                    .new_value = new_value,
                });
            }
        }
    }
}

/// Toggle/checkbox interaction detection system
pub fn toggleInteractionSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    click_writer: zevy_ecs.EventWriter(UIClickEvent),
    toggle_writer: zevy_ecs.EventWriter(UIToggleEvent),
    query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        toggle: components.UIToggle,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    _ = manager;

    const cursor_pos = input.getMousePosition() orelse return;
    const click_triggered = input_mgr.ptr.wasActionTriggered("ui_click") or
        input_mgr.ptr.wasActionTriggered("ui_confirm");

    while (query.next()) |item| {
        if (item.visible) |v| {
            if (!v.visible) continue;
        }
        if (!item.toggle.*.enabled) continue;

        const bounds = item.rect.toRectangle();
        const is_hovered = rl.checkCollisionPointRec(cursor_pos, bounds);

        if (is_hovered and click_triggered) {
            // Toggle the checked state
            item.toggle.*.toggle();

            // Emit click event
            click_writer.write(.{
                .entity = item.entity,
                .input_device = .mouse,
                .position = cursor_pos,
                .button = .left,
            });

            // Emit toggle event
            toggle_writer.write(.{
                .entity = item.entity,
                .checked = item.toggle.*.checked,
            });
        }
    }
}

/// Spinner interaction detection system
pub fn spinnerInteractionSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    value_writer: zevy_ecs.EventWriter(UIValueChangedEvent),
    query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        spinner: components.UISpinner,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    _ = manager;

    const cursor_pos = input.getMousePosition() orelse return;
    const click_triggered = input_mgr.ptr.wasActionTriggered("ui_click");

    while (query.next()) |item| {
        if (item.visible) |v| {
            if (!v.visible) continue;
        }
        if (!item.spinner.*.enabled) continue;

        const bounds = item.rect.toRectangle();
        const is_hovered = rl.checkCollisionPointRec(cursor_pos, bounds);

        if (is_hovered and click_triggered) {
            const old_value = item.spinner.*.value;

            // Determine if click was on left or right side
            const half_width = bounds.width / 2.0;
            const relative_x = cursor_pos.x - bounds.x;

            if (relative_x < half_width) {
                item.spinner.*.decrement();
            } else {
                item.spinner.*.increment();
            }

            const new_value = item.spinner.*.value;

            if (new_value != old_value) {
                value_writer.write(.{
                    .entity = item.entity,
                    .component_type_name = "UISpinner",
                    .old_value = @floatFromInt(old_value),
                    .new_value = @floatFromInt(new_value),
                });
            }
        }
    }
}

/// Dropdown interaction detection system
pub fn dropdownInteractionSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    selection_writer: zevy_ecs.EventWriter(UISelectionChangedEvent),
    query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        dropdown: components.UIDropdown,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    _ = manager;
    _ = input_mgr;
    _ = selection_writer;

    // Note: Dropdown interaction is complex and typically handled by raygui internally
    // This is a placeholder for custom dropdown logic if needed
    while (query.next()) |item| {
        if (item.visible) |v| {
            if (!v.visible) continue;
        } else continue;

        // Track selection changes from raygui's internal handling
        // This would need to be implemented based on actual raygui behavior
    }
}

/// Text box focus detection system
pub fn textBoxFocusSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    focus_writer: zevy_ecs.EventWriter(UIFocusEvent),
    query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        textbox: components.UITextBox,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    _ = manager;

    const cursor_pos = input.getMousePosition() orelse return;
    const click_triggered = input_mgr.ptr.wasActionTriggered("ui_click");

    while (query.next()) |item| {
        if (item.visible) |v| {
            if (!v.visible) continue;
        }

        const bounds = item.rect.toRectangle();
        const is_hovered = rl.checkCollisionPointRec(cursor_pos, bounds);

        const was_editing = item.textbox.*.edit_mode;

        if (click_triggered) {
            if (is_hovered and item.textbox.*.enabled) {
                item.textbox.*.edit_mode = true;

                if (!was_editing) {
                    focus_writer.write(.{
                        .entity = item.entity,
                        .gained = true,
                    });
                }
            } else if (was_editing) {
                item.textbox.*.edit_mode = false;
                focus_writer.write(.{
                    .entity = item.entity,
                    .gained = false,
                });
            }
        }
    }
}

// =============================================================================
// HELPER UTILITIES
// =============================================================================

/// Helper to check if an entity matches a click event
pub fn isEntityClicked(event: *const UIClickEvent, entity: zevy_ecs.Entity) bool {
    return event.entity.id == entity.id and event.entity.generation == entity.generation;
}

/// Helper to check if an entity is being hovered
pub fn isEntityHovered(event: *const UIHoverEvent, entity: zevy_ecs.Entity) bool {
    return event.entity.id == entity.id and event.entity.generation == entity.generation;
}

// =============================================================================
// TESTS
// =============================================================================

test "UI input event types" {
    const testing = std.testing;

    // Test UIClickEvent creation
    const click_event = UIClickEvent{
        .entity = .{ .id = 1, .generation = 0 },
        .input_device = .mouse,
        .position = .{ .x = 100, .y = 200 },
        .button = .left,
    };

    try testing.expectEqual(@as(u32, 1), click_event.entity.id);
    try testing.expectEqual(@as(f32, 100), click_event.position.x);

    // Test UIValueChangedEvent
    const value_event = UIValueChangedEvent{
        .entity = .{ .id = 2, .generation = 0 },
        .component_type_name = "UISlider",
        .old_value = 0.5,
        .new_value = 0.75,
    };

    try testing.expectEqual(@as(f32, 0.5), value_event.old_value);
    try testing.expectEqual(@as(f32, 0.75), value_event.new_value);
}

test "UI input helper functions" {
    const testing = std.testing;

    const entity = zevy_ecs.Entity{ .id = 42, .generation = 1 };
    const click_event = UIClickEvent{
        .entity = entity,
        .input_device = .mouse,
        .position = .{ .x = 0, .y = 0 },
        .button = .left,
    };

    try testing.expect(isEntityClicked(&click_event, entity));
    try testing.expect(!isEntityClicked(&click_event, .{ .id = 43, .generation = 1 }));
}
