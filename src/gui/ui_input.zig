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

const PrevPressed = struct {
    keys: [64]input.InputKey = undefined,
    len: usize = 0,
};

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
        .button = .right_face_down,
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
        .button = .right_face_right,
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

    // Tab key -> focus next
    var tab_focus = input.InputChord.init(allocator);
    try tab_focus.add(allocator, input.InputKey{ .keyboard = .key_tab });
    try input_mgr.addBinding(.{
        .chord = tab_focus,
        .action = try input.InputAction.init(allocator, "ui_focus_next", "UI focus next"),
        .enabled = true,
    });

    // Shift+Tab -> focus previous
    var shift_tab = input.InputChord.init(allocator);
    try shift_tab.add(allocator, input.InputKey{ .keyboard = .key_left_shift });
    try shift_tab.add(allocator, input.InputKey{ .keyboard = .key_tab });
    try input_mgr.addBinding(.{
        .chord = shift_tab,
        .action = try input.InputAction.init(allocator, "ui_focus_prev", "UI focus previous"),
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

    var back_cancel = input.InputChord.init(allocator);
    try back_cancel.add(allocator, input.InputKey{ .keyboard = .key_backspace });
    try input_mgr.addBinding(.{
        .chord = back_cancel,
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
    // Local persistent storage: last hovered entity and previous pressed keys
    last_hover: *zevy_ecs.Local(zevy_ecs.Entity),
    prev_pressed: *zevy_ecs.Local(PrevPressed),

    // Query for buttons
    rel: *zevy_ecs.Relations,
    button_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        button: components.UIButton,
        enabled: ?components.UIEnabled,
        visible: ?components.UIVisible,
    }, .{}),
    // Query yielding currently-focused entities so we can clear focus on click
    focus_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        focus: components.UIFocus,
    }, .{}),
) void {

    // Get input position (handles mouse/touch automatically)
    const cursor_pos = input.getMousePosition() orelse return;

    // Check if click action was triggered this frame. Separate mouse/touch
    // ('ui_click') from confirm (keyboard/gamepad, 'ui_confirm') so we can
    // avoid double-toggling when raygui already handles mouse toggles during
    // rendering.
    const click_triggered_click = input_mgr.ptr.wasActionTriggered("ui_click");
    const click_triggered_confirm = input_mgr.ptr.wasActionTriggered("ui_confirm");

    // Local params are provided as pointers; use them directly
    var last_hover_mut = last_hover;
    var prev_pressed_mut = prev_pressed;

    // Build a small list of newly-pressed keys compared to the previous frame
    const current_keys = input_mgr.ptr.getCurrentState().getPressed();
    var newly_pressed: [12]input.InputKey = undefined;
    var newly_len: usize = 0;

    var prev_slice: []const input.InputKey = current_keys[0..0];
    if (prev_pressed_mut.value()) |pp| {
        prev_slice = pp.keys[0..pp.len];
    }

    for (current_keys) |ck| {
        var found = false;
        for (prev_slice) |pk| {
            if (pk.eql(ck)) {
                found = true;
                break;
            }
        }
        if (!found) {
            newly_pressed[newly_len] = ck;
            newly_len += 1;
        }
    }

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

        // Emit hover events on state change and remember last hovered
        if (is_hovered and !was_hovered) {
            last_hover_mut.set(item.entity);
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

        // Skip if explicitly disabled via UIEnabled component
        if (item.enabled) |en| {
            if (en.state == false) continue;
        }
        // Activated by mouse/touch click
        const activated_by_mouse = is_hovered and click_triggered_click;
        // Activated by keyboard/gamepad confirm (don't require hover;
        // we'll only activate if the entity has a matching UIInputKey child)
        const activated_by_confirm = click_triggered_confirm;

        // Activated by a direct InputKey press that matches a child's UIInputKey
        var activated_by_keypress: bool = false;
        if (newly_len > 0) {
            const children = rel.getChildren(item.entity, zevy_ecs.relations.Child);
            for (children) |child| {
                if (activated_by_keypress) break;
                if (manager.getComponent(child, components.UIInputKey) catch null) |ik| {
                    const slice = ik.asSlice();
                    for (slice) |k| {
                        var j: usize = 0;
                        while (j < newly_len) : (j += 1) {
                            if (k.eql(newly_pressed[j])) {
                                activated_by_keypress = true;
                                break;
                            }
                        }
                        if (activated_by_keypress) break;
                    }
                }
            }
        }

        // If confirm was triggered but we didn't detect the key in newly_pressed
        // (e.g., held keys or matching via action), also consider current
        // pressed keys as a fallback so entities that declare the input
        // are activated even without hover.
        if (!activated_by_keypress and click_triggered_confirm) {
            const children2 = rel.getChildren(item.entity, zevy_ecs.relations.Child);
            for (children2) |child| {
                if (activated_by_keypress) break;
                if (manager.getComponent(child, components.UIInputKey) catch null) |ik| {
                    const slice = ik.asSlice();
                    for (slice) |k| {
                        for (current_keys) |ck| {
                            if (k.eql(ck)) {
                                activated_by_keypress = true;
                                break;
                            }
                        }
                        if (activated_by_keypress) break;
                    }
                }
            }
        }

        if (activated_by_mouse) {
            if (item.button.style != .toggle) {
                item.button.*.pressed = true;
            }
            click_writer.write(.{
                .entity = item.entity,
                .input_device = .mouse,
                .position = cursor_pos,
                .button = .left,
            });

            // Change focus to the clicked element: remove UIFocus from any other
            while (focus_query.next()) |fitem| {
                _ = manager.removeComponent(fitem.entity, components.UIFocus) catch null;
            }
            // Add UIFocus to this entity (if focusable)
            if (manager.getComponent(item.entity, components.UIFocusable) catch null) |ff| {
                _ = ff;
                _ = manager.addComponent(item.entity, components.UIFocus, components.UIFocus{}) catch null;
            } else {
                // Consider common interactive components focusable by default
                if (manager.getComponent(item.entity, components.UIButton) catch null) |b| {
                    _ = b;
                    _ = manager.addComponent(item.entity, components.UIFocus, components.UIFocus{}) catch null;
                }
            }
        } else if (activated_by_confirm or activated_by_keypress) {
            if (item.button.style == .toggle) {
                item.button.*.pressed = !item.button.*.pressed;
            } else {
                item.button.*.pressed = true;
            }
            click_writer.write(.{
                .entity = item.entity,
                .input_device = .mouse,
                .position = cursor_pos,
                .button = .left,
            });
        } else if (item.button.style != .toggle) {
            // Only reset pressed state for non-toggle buttons when not clicking
            item.button.*.pressed = false;
        }
    }

    // Update Local prev_pressed with current keys snapshot for next frame
    var newprev: PrevPressed = PrevPressed{};
    var idx: usize = 0;
    while (idx < current_keys.len and idx < newprev.keys.len) : (idx += 1) {
        newprev.keys[idx] = current_keys[idx];
    }
    newprev.len = @min(current_keys.len, newprev.keys.len);
    prev_pressed_mut.set(newprev);
}

/// Focus navigation system: cycles focusable UI elements when the
/// `ui_focus_next` action is triggered. Focus is represented by adding
/// or removing the `UIFocus` component on entities.
pub fn uiFocusNavigationSystem(
    manager: *zevy_ecs.Manager,
    input_mgr: zevy_ecs.Res(input.InputManager),
    rel: *zevy_ecs.Relations,
    last_hover: *zevy_ecs.Local(zevy_ecs.Entity),
    focus_writer: zevy_ecs.EventWriter(UIFocusEvent),
    focus_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        focusable: components.UIFocusable,
        enabled: ?components.UIEnabled,
        visible: ?components.UIVisible,
    }, .{}),
) !void {
    // manager is used below; no discard needed

    // If no focus action was pressed, nothing to do
    const next_pressed = input_mgr.ptr.wasActionTriggered("ui_focus_next");
    const prev_pressed = input_mgr.ptr.wasActionTriggered("ui_focus_prev");
    if (!next_pressed and !prev_pressed) return;

    // (helper moved to top-level) use `isFocusable(manager, e)` below

    // Build ordered list of focusable entities (children of parent first)
    var candidates = try std.ArrayList(zevy_ecs.Entity).initCapacity(manager.allocator, 64);
    defer candidates.deinit(manager.allocator);

    // If there's a currently focused entity, prefer siblings (children of its parent)
    var focused_parent: ?zevy_ecs.Entity = null;
    // Find current focused entity
    var current_focused: ?zevy_ecs.Entity = null;
    // Consume the focus_query once and collect all focusable entities.
    var all_focusables = try std.ArrayList(zevy_ecs.Entity).initCapacity(manager.allocator, 64);
    defer all_focusables.deinit(manager.allocator);
    while (focus_query.next()) |item| {
        // Skip invisible or explicitly disabled focusable entities
        if (item.visible) |v| {
            if (!v.visible) continue;
        }
        if (item.enabled) |en| {
            if (en.state == false) continue;
        }

        try all_focusables.append(manager.allocator, item.entity);
        if (try manager.getComponent(item.entity, components.UIFocus)) |f| {
            _ = f;
            current_focused = item.entity;
        }
    }

    if (current_focused) |cf| {
        if (rel.getParent(manager, cf, zevy_ecs.relations.Child) catch null) |p| {
            focused_parent = p;
        }
    } else {
        // No focused entity — prefer the parent of the last-hovered entity
        if (last_hover.value()) |lh| {
            if (rel.getParent(manager, lh, zevy_ecs.relations.Child) catch null) |p2| {
                focused_parent = p2;
            }
        }
    }

    if (focused_parent) |parent| {
        const children = rel.getChildren(parent, zevy_ecs.relations.Child);
        for (children) |child| {
            if (try manager.getComponent(child, components.UIFocusable)) |f| {
                _ = f;
                try candidates.append(manager.allocator, child);
            }
        }
    }

    // After siblings, append all other focusable entities (skip duplicates)
    for (all_focusables.items) |e| {
        // Skip if already in candidates
        var exists = false;
        for (candidates.items) |c| {
            if (c.eql(e)) {
                exists = true;
                break;
            }
        }
        if (exists) continue;
        try candidates.append(manager.allocator, e);
    }

    if (candidates.items.len == 0) return;

    // Sort candidates by their rect.x (left-to-right) for predictable navigation order
    var si: usize = 1;
    while (si < candidates.items.len) : (si += 1) {
        var sj = si;
        while (sj > 0) : (sj -= 1) {
            const a = candidates.items[sj - 1];
            const b = candidates.items[sj];
            var ax: f32 = 0.0;
            var bx: f32 = 0.0;
            if (manager.getComponent(a, components.UIRect) catch null) |r| ax = r.x;
            if (manager.getComponent(b, components.UIRect) catch null) |r2| bx = r2.x;
            if (ax <= bx) break;
            const tmp = candidates.items[sj - 1];
            candidates.items[sj - 1] = candidates.items[sj];
            candidates.items[sj] = tmp;
            if (sj == 0) break;
        }
    }

    // Find current focused entity index
    var current_index: ?usize = null;
    for (candidates.items, 0..) |ent, i| {
        if (try manager.getComponent(ent, components.UIFocus)) |f| {
            _ = f;
            current_index = i;
            break;
        }
    }

    const next_index = if (current_index) |ci| (ci + 1) % candidates.items.len else 0;
    const prev_index = if (current_index) |ci| ((ci + candidates.items.len - 1) % candidates.items.len) else (candidates.items.len - 1);

    // Remove focus from previous and emit event
    if (current_index) |ci| {
        if (ci >= candidates.items.len) {
            // defensive: current index no longer valid
        } else {
            const prev_ent = candidates.items[ci];
            try manager.removeComponent(prev_ent, components.UIFocus);
            focus_writer.write(.{ .entity = prev_ent, .gained = false });
        }
    }

    const chosen_index = if (prev_pressed) prev_index else next_index;
    // defensive bounds check before accessing chosen entity
    if (chosen_index >= candidates.items.len) return;
    const chosen_ent_checked = candidates.items[chosen_index];
    // Add focus to new entity and emit event
    try manager.addComponent(chosen_ent_checked, components.UIFocus, components.UIFocus{});
    focus_writer.write(.{ .entity = chosen_ent_checked, .gained = true });
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
        enabled: ?components.UIEnabled,
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
        if (item.enabled) |en| {
            if (en.state == false) continue;
        }

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
        enabled: ?components.UIEnabled,
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
        if (item.enabled) |en| {
            if (en.state == false) continue;
        }

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
        enabled: ?components.UIEnabled,
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
        if (item.enabled) |en| {
            if (en.state == false) continue;
        }

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
        enabled: ?components.UIEnabled,
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
            if (is_hovered) {
                if (item.enabled) |en| {
                    if (en.state == false) {
                        // disabled: don't enter edit mode
                    } else {
                        item.textbox.*.edit_mode = true;
                        if (!was_editing) {
                            focus_writer.write(.{
                                .entity = item.entity,
                                .gained = true,
                            });
                        }
                    }
                } else {
                    item.textbox.*.edit_mode = true;
                    if (!was_editing) {
                        focus_writer.write(.{
                            .entity = item.entity,
                            .gained = true,
                        });
                    }
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
