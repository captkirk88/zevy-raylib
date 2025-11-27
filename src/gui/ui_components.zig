const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

// =============================================================================
// UI COMPONENT TYPES
// =============================================================================

/// Base rectangle component for all UI elements
pub const UIRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, width: f32, height: f32) UIRect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn toRectangle(self: *const UIRect) rl.Rectangle {
        return .{ .x = self.x, .y = self.y, .width = self.width, .height = self.height };
    }

    pub fn fromRectangle(rect: rl.Rectangle) UIRect {
        return .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = rect.height };
    }

    pub fn contains(self: *const UIRect, px: f32, py: f32) bool {
        return px >= self.x and px <= self.x + self.width and
            py >= self.y and py <= self.y + self.height;
    }

    pub fn center(self: *const UIRect) struct { x: f32, y: f32 } {
        return .{
            .x = self.x + self.width / 2.0,
            .y = self.y + self.height / 2.0,
        };
    }
};

/// Text label component
pub const UIText = struct {
    text: [:0]const u8,
    font_size: i32 = 10,
    color: rl.Color = rl.Color.black,
    alignment: TextAlignment = .left,
    word_wrap: bool = false,

    pub const TextAlignment = enum {
        left,
        center,
        right,
    };

    pub fn init(text: [:0]const u8) UIText {
        return .{ .text = text };
    }

    pub fn withFontSize(self: UIText, size: i32) UIText {
        var result = self;
        result.font_size = size;
        return result;
    }

    pub fn withColor(self: UIText, color: rl.Color) UIText {
        var result = self;
        result.color = color;
        return result;
    }

    pub fn withAlignment(self: UIText, alignment: TextAlignment) UIText {
        var result = self;
        result.alignment = alignment;
        return result;
    }
};

/// Button component with state tracking
pub const UIButton = struct {
    text: [:0]const u8 = "",
    enabled: bool = true,
    pressed: bool = false,
    hovered: bool = false,
    style: ButtonStyle = .default,

    pub const ButtonStyle = enum {
        default,
        toggle,
        flat,
    };

    pub fn init(text: [:0]const u8) UIButton {
        return .{ .text = text };
    }

    pub fn withStyle(self: UIButton, style: ButtonStyle) UIButton {
        var result = self;
        result.style = style;
        return result;
    }

    pub fn setEnabled(self: *UIButton, enabled: bool) void {
        self.enabled = enabled;
    }

    pub fn isPressed(self: UIButton) bool {
        return self.pressed and self.enabled;
    }
};

/// Toggle/checkbox component
pub const UIToggle = struct {
    checked: bool = false,
    text: [:0]const u8 = "",
    enabled: bool = true,

    pub fn init(text: [:0]const u8, checked: bool) UIToggle {
        return .{ .text = text, .checked = checked };
    }

    pub fn toggle(self: *UIToggle) void {
        if (self.enabled) {
            self.checked = !self.checked;
        }
    }
};

/// Marker component that indicates an entity currently has keyboard/gamepad focus
pub const UIFocus = struct {
    // Empty marker
};

/// Marker/flag that an entity can receive focus. If present, the focus
/// navigation system will include the entity when cycling focusable elements.
pub const UIFocusable = struct {
    pub fn init() UIFocusable { return UIFocusable{}; }
};

/// Slider component for numeric values
pub const UISlider = struct {
    value: f32,
    min_value: f32,
    max_value: f32,
    text_left: [:0]const u8 = "",
    text_right: [:0]const u8 = "",
    show_value: bool = true,
    enabled: bool = true,

    pub fn init(value: f32, min_value: f32, max_value: f32) UISlider {
        return .{
            .value = std.math.clamp(value, min_value, max_value),
            .min_value = min_value,
            .max_value = max_value,
        };
    }

    pub fn setValue(self: *UISlider, value: f32) void {
        self.value = std.math.clamp(value, self.min_value, self.max_value);
    }

    pub fn getNormalized(self: UISlider) f32 {
        if (self.max_value == self.min_value) return 0.0;
        return (self.value - self.min_value) / (self.max_value - self.min_value);
    }
};

/// Progress bar component
pub const UIProgressBar = struct {
    value: f32,
    text: [:0]const u8 = "",
    show_value: bool = true,

    pub fn init(value: f32) UIProgressBar {
        return .{ .value = std.math.clamp(value, 0.0, 1.0) };
    }

    pub fn setValue(self: *UIProgressBar, value: f32) void {
        self.value = std.math.clamp(value, 0.0, 1.0);
    }

    pub fn setFromRatio(self: *UIProgressBar, current: f32, maximum: f32) void {
        if (maximum > 0) {
            self.value = std.math.clamp(current / maximum, 0.0, 1.0);
        } else {
            self.value = 0.0;
        }
    }
};

/// Text input field component
pub const UITextBox = struct {
    buffer: []u8,
    text_len: usize = 0,
    edit_mode: bool = false,
    enabled: bool = true,
    placeholder: [:0]const u8 = "",

    pub fn init(buffer: []u8) UITextBox {
        return .{ .buffer = buffer };
    }

    pub fn getText(self: UITextBox) []const u8 {
        return self.buffer[0..self.text_len];
    }

    pub fn setText(self: *UITextBox, text: []const u8) void {
        const len = @min(text.len, self.buffer.len - 1);
        @memcpy(self.buffer[0..len], text[0..len]);
        self.text_len = len;
        self.buffer[len] = 0;
    }

    pub fn clear(self: *UITextBox) void {
        self.text_len = 0;
        if (self.buffer.len > 0) {
            self.buffer[0] = 0;
        }
    }
};

/// Panel/Container component for grouping UI elements
pub const UIPanel = struct {
    title: ?[:0]const u8 = "",
    border: bool = true,
    background: bool = true,
    color: ?rl.Color = null,
    padding: f32 = 5.0,

    pub fn init(title: ?[:0]const u8) UIPanel {
        return .{ .title = title };
    }

    pub fn withPadding(self: UIPanel, padding: f32) UIPanel {
        var result = self;
        result.padding = padding;
        return result;
    }

    pub fn withColor(self: UIPanel, color: rl.Color) UIPanel {
        var result = self;
        result.color = color;
        return result;
    }
};

/// Scroll panel for scrollable content
pub const UIScrollPanel = struct {
    content_rect: rl.Rectangle,
    scroll: rl.Vector2 = .{ .x = 0, .y = 0 },
    view: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

    pub fn init(content_width: f32, content_height: f32) UIScrollPanel {
        return .{
            .content_rect = .{
                .x = 0,
                .y = 0,
                .width = content_width,
                .height = content_height,
            },
        };
    }

    pub fn scrollTo(self: *UIScrollPanel, x: f32, y: f32) void {
        self.scroll.x = x;
        self.scroll.y = y;
    }
};

/// Dropdown/ComboBox component
pub const UIDropdown = struct {
    items: []const [:0]const u8,
    active: i32 = 0,
    edit_mode: bool = false,
    enabled: bool = true,

    pub fn init(items: []const [:0]const u8) UIDropdown {
        return .{ .items = items };
    }

    pub fn getSelected(self: UIDropdown) ?[]const u8 {
        if (self.active >= 0 and self.active < self.items.len) {
            return self.items[@intCast(self.active)];
        }
        return null;
    }

    pub fn setActive(self: *UIDropdown, index: i32) void {
        if (index >= 0 and index < self.items.len) {
            self.active = index;
        }
    }
};

/// Image component for displaying textures
pub const UIImage = struct {
    texture: rl.Texture2D,
    tint: rl.Color = rl.Color.white,
    scale: f32 = 1.0,

    pub fn init(texture: rl.Texture2D) UIImage {
        return .{ .texture = texture };
    }

    pub fn withTint(self: UIImage, tint: rl.Color) UIImage {
        var result = self;
        result.tint = tint;
        return result;
    }

    pub fn withScale(self: UIImage, scale: f32) UIImage {
        var result = self;
        result.scale = scale;
        return result;
    }
};

/// Spinner for numeric input
pub const UISpinner = struct {
    value: i32,
    min_value: i32,
    max_value: i32,
    edit_mode: bool = false,
    enabled: bool = true,

    pub fn init(value: i32, min_value: i32, max_value: i32) UISpinner {
        return .{
            .value = std.math.clamp(value, min_value, max_value),
            .min_value = min_value,
            .max_value = max_value,
        };
    }

    pub fn increment(self: *UISpinner) void {
        if (self.value < self.max_value) {
            self.value += 1;
        }
    }

    pub fn decrement(self: *UISpinner) void {
        if (self.value > self.min_value) {
            self.value -= 1;
        }
    }
};

/// Color picker component
pub const UIColorPicker = struct {
    color: rl.Color,
    enabled: bool = true,

    pub fn init(color: rl.Color) UIColorPicker {
        return .{ .color = color };
    }

    pub fn setColor(self: *UIColorPicker, color: rl.Color) void {
        self.color = color;
    }
};

/// List view component
pub const UIListView = struct {
    items: []const [:0]const u8,
    scroll_index: i32 = 0,
    active: i32 = 0,
    enabled: bool = true,

    pub fn init(items: []const [:0]const u8) UIListView {
        return .{ .items = items };
    }

    pub fn getSelected(self: UIListView) ?[]const u8 {
        if (self.active >= 0 and self.active < self.items.len) {
            return self.items[@intCast(self.active)];
        }
        return null;
    }
};

/// Message box/dialog component
pub const UIMessageBox = struct {
    title: [:0]const u8,
    message: [:0]const u8,
    buttons: [:0]const u8,
    result: i32 = -1,
    active: bool = true,

    pub fn init(title: [:0]const u8, message: [:0]const u8, buttons: [:0]const u8) UIMessageBox {
        return .{
            .title = title,
            .message = message,
            .buttons = buttons,
        };
    }

    pub fn isOpen(self: UIMessageBox) bool {
        return self.active and self.result < 0;
    }

    pub fn close(self: *UIMessageBox) void {
        self.active = false;
    }
};

/// Tab bar component
pub const UITabBar = struct {
    tabs: []const [:0]const u8,
    active: i32 = 0,
    enabled: bool = true,

    pub fn init(tabs: []const [:0]const u8) UITabBar {
        return .{ .tabs = tabs };
    }

    pub fn getActiveTab(self: UITabBar) ?[:0]const u8 {
        if (self.active >= 0 and self.active < self.tabs.len) {
            return self.tabs[@intCast(self.active)];
        }
        return null;
    }

    pub fn setActiveTab(self: *UITabBar, index: i32) void {
        if (index >= 0 and index < self.tabs.len) {
            self.active = index;
        }
    }
};

/// Visibility toggle for hiding/showing UI elements
pub const UIVisible = struct {
    visible: bool = true,

    pub fn init(visible: bool) UIVisible {
        return .{ .visible = visible };
    }

    pub fn show(self: *UIVisible) void {
        self.visible = true;
    }

    pub fn hide(self: *UIVisible) void {
        self.visible = false;
    }

    pub fn toggle(self: *UIVisible) void {
        self.visible = !self.visible;
    }
};

/// Z-order for layering UI elements
pub const UILayer = struct {
    layer: i32 = 0,

    pub fn init(layer: i32) UILayer {
        return .{ .layer = layer };
    }
};

const input = @import("../input/input.zig");

/// Component representing a single input key or a small key chord associated with a UI element.
/// Stores up to 4 keys inline to avoid allocator ownership in components.
pub const UIInputKey = struct {
    keys: [4]input.InputKey,
    len: u8,

    pub fn initSingle(key: input.InputKey) UIInputKey {
        var k: [4]input.InputKey = undefined;
        k[0] = key;
        return UIInputKey{ .keys = k, .len = 1 };
    }

    pub fn initFromSlice(keys_slice: []const input.InputKey) UIInputKey {
        var k: [4]input.InputKey = undefined;
        var i: usize = 0;
        while (i < keys_slice.len and i < k.len) : (i += 1) {
            k[i] = keys_slice[i];
        }
        var count = keys_slice.len;
        if (count > k.len) count = k.len;
        return UIInputKey{ .keys = k, .len = @as(u8, @intCast(count)) };
    }

    pub fn asSlice(self: *const UIInputKey) []const input.InputKey {
        return self.keys[0..@as(usize, self.len)];
    }
};
