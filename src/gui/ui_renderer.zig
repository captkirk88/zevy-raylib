const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const components = @import("ui_components.zig");
const layout = @import("ui_layout.zig");

// Re-export components for convenience
pub const UIRect = components.UIRect;
pub const UIText = components.UIText;
pub const UIButton = components.UIButton;
pub const UIToggle = components.UIToggle;
pub const UISlider = components.UISlider;
pub const UIProgressBar = components.UIProgressBar;
pub const UITextBox = components.UITextBox;
pub const UIPanel = components.UIPanel;
pub const UIScrollPanel = components.UIScrollPanel;
pub const UIDropdown = components.UIDropdown;
pub const UIImage = components.UIImage;
pub const UISpinner = components.UISpinner;
pub const UIColorPicker = components.UIColorPicker;
pub const UIListView = components.UIListView;
pub const UIMessageBox = components.UIMessageBox;
pub const UITabBar = components.UITabBar;
pub const UIVisible = components.UIVisible;
pub const UILayer = components.UILayer;

// Re-export layout for convenience
pub const FlexLayout = layout.FlexLayout;
pub const GridLayout = layout.GridLayout;
pub const StackLayout = layout.StackLayout;
pub const AbsoluteLayout = layout.AbsoluteLayout;
pub const Padding = layout.Padding;
pub const Margin = layout.Margin;
pub const SizeConstraints = layout.SizeConstraints;
pub const FlexItem = layout.FlexItem;
pub const GridItem = layout.GridItem;
pub const AnchorPosition = layout.AnchorPosition;
pub const UIContainer = layout.UIContainer;

// Re-export enums
pub const FlexDirection = layout.FlexDirection;
pub const FlexAlign = layout.FlexAlign;
pub const FlexItemAlign = layout.FlexItemAlign;
pub const FlexWrap = layout.FlexWrap;

/// Render a UI text component
pub fn renderText(rect: *const UIRect, text: *const UIText, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    // Simple label rendering using raygui
    _ = rg.label(bounds, text.text);
}

/// Render a UI button component
pub fn renderButton(rect: UIRect, button: *UIButton, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!button.enabled) {
        rg.disable();
    }

    button.pressed = switch (button.style) {
        .default => rg.button(bounds, button.text),
        .toggle => blk: {
            _ = rg.toggle(bounds, button.text, &button.pressed);
            break :blk button.pressed;
        },
        .flat => rg.labelButton(bounds, button.text),
    };

    button.hovered = rl.checkCollisionPointRec(rl.getMousePosition(), bounds);

    if (!button.enabled) {
        rg.enable();
    }
}

/// Render a UI toggle/checkbox component
pub fn renderToggle(rect: UIRect, toggle: *UIToggle, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!toggle.enabled) {
        rg.disable();
    }

    _ = rg.checkBox(bounds, toggle.text, &toggle.checked);

    if (!toggle.enabled) {
        rg.enable();
    }
}

/// Render a UI slider component
pub fn renderSlider(rect: UIRect, slider: *UISlider, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!slider.enabled) {
        rg.disable();
    }

    _ = rg.slider(
        bounds,
        slider.text_left,
        slider.text_right,
        &slider.value,
        slider.min_value,
        slider.max_value,
    );

    if (!slider.enabled) {
        rg.enable();
    }
}

/// Render a UI progress bar component
pub fn renderProgressBar(rect: UIRect, progress: UIProgressBar, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();
    var val = progress.value;
    _ = rg.progressBar(
        bounds,
        progress.text,
        "",
        &val,
        0.0,
        1.0,
    );
}

/// Render a UI text input box component
pub fn renderTextBox(rect: UIRect, textbox: *UITextBox, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!textbox.enabled) {
        rg.disable();
    }

    // Ensure buffer is null-terminated
    if (textbox.text_len < textbox.buffer.len) {
        textbox.buffer[textbox.text_len] = 0;
    }

    textbox.edit_mode = rg.textBox(
        bounds,
        textbox.buffer[0..textbox.buffer.len :0],
        @intCast(textbox.buffer.len),
        textbox.edit_mode,
    );

    // Update text length
    textbox.text_len = std.mem.indexOf(u8, textbox.buffer, &[_]u8{0}) orelse textbox.buffer.len;

    if (!textbox.enabled) {
        rg.enable();
    }
}

/// Render a UI panel component
pub fn renderPanel(rect: *const UIRect, panel: *const UIPanel, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (panel.background) {
        if (panel.color) |color| {
            rl.drawRectangleRec(bounds, color);
        } else {
            _ = rg.panel(bounds, panel.title.ptr);
        }
    }

    if (panel.border) {
        rl.drawRectangleLinesEx(bounds, 1, panel.color orelse rl.Color.gray);
    }
}

/// Render a UI scroll panel component
pub fn renderScrollPanel(rect: UIRect, scroll_panel: *UIScrollPanel, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();
    _ = rg.scrollPanel(
        bounds,
        null,
        scroll_panel.content_rect,
        &scroll_panel.scroll,
        &scroll_panel.view,
    );
}

/// Render a UI dropdown/combobox component
pub fn renderDropdown(rect: UIRect, dropdown: *UIDropdown, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!dropdown.enabled) {
        return;
    }

    // Join items with semicolons for raygui
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    for (dropdown.items, 0..) |item, i| {
        if (i > 0) {
            writer.writeByte(';') catch break;
        }
        writer.writeAll(item) catch break;
    }
    writer.writeByte(0) catch {};
    const items_str = fbs.getWritten();

    _ = rg.comboBox(
        bounds,
        items_str[0 .. items_str.len - 1 :0],
        &dropdown.active,
    );

    if (!dropdown.enabled) {
        rg.enable();
    }
}

/// Render a UI image component
pub fn renderImage(rect: UIRect, image: UIImage, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();
    const source = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(image.texture.width),
        .height = @floatFromInt(image.texture.height),
    };

    rl.drawTexturePro(
        image.texture,
        source,
        bounds,
        rl.Vector2.zero(),
        0,
        image.tint,
    );
}

/// Render a UI spinner component
pub fn renderSpinner(rect: UIRect, spinner: *UISpinner, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!spinner.enabled) {
        rg.disable();
    }

    _ = rg.spinner(
        bounds,
        "",
        &spinner.value,
        spinner.min_value,
        spinner.max_value,
        spinner.edit_mode,
    );

    if (!spinner.enabled) {
        rg.enable();
    }
}

/// Render a UI color picker component
pub fn renderColorPicker(rect: UIRect, picker: *UIColorPicker, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!picker.enabled) {
        rg.disable();
    }

    _ = rg.colorPicker(bounds, "", &picker.color);

    if (!picker.enabled) {
        rg.enable();
    }
}

/// Render a UI list view component
pub fn renderListView(rect: UIRect, list_view: *UIListView, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!list_view.enabled) {
        rg.disable();
    }

    // Join items with semicolons for raygui
    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    for (list_view.items, 0..) |item, i| {
        if (i > 0) {
            writer.writeByte(';') catch break;
        }
        writer.writeAll(item) catch break;
    }
    writer.writeByte(0) catch {};
    const items_str = fbs.getWritten();

    _ = rg.listView(
        bounds,
        items_str[0 .. items_str.len - 1 :0],
        &list_view.scroll_index,
        &list_view.active,
    );

    if (!list_view.enabled) {
        rg.enable();
    }
}

/// Render a UI message box component
pub fn renderMessageBox(rect: UIRect, msg_box: *UIMessageBox, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    if (!msg_box.active or msg_box.result >= 0) return;

    const bounds = rect.toRectangle();
    msg_box.result = rg.messageBox(
        bounds,
        msg_box.title,
        msg_box.message,
        msg_box.buttons,
    );
}

/// Render a UI tab bar component
pub fn renderTabBar(rect: UIRect, tab_bar: *UITabBar, visible: ?UIVisible) void {
    if (visible) |v| {
        if (!v.visible) return;
    }

    const bounds = rect.toRectangle();

    if (!tab_bar.enabled) {
        rg.disable();
    }

    // Convert string slices to null-terminated pointers for raygui
    var tab_ptrs: [32][*:0]const u8 = undefined;
    const tab_count = @min(tab_bar.tabs.len, 32);
    for (tab_bar.tabs[0..tab_count], 0..) |tab, i| {
        tab_ptrs[i] = tab.ptr;
    }

    _ = rg.tabBar(bounds, tab_ptrs[0..tab_count], &tab_bar.active);

    if (!tab_bar.enabled) {
        rg.enable();
    }
}
