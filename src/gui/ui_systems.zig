const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const zevy_ecs = @import("zevy_ecs");
const input = @import("../input/input.zig");
const components = @import("ui_components.zig");
const layout = @import("ui_layout.zig");
const renderer = @import("ui_renderer.zig");

/// UI Render System
/// Renders all UI entities based on their components
/// This system should be called during the render stage of your game loop
///
/// Example usage with zevy_ecs:
/// ```zig
/// scheduler.addSystem(
///     zevy_ecs.Stage(zevy_ecs.Stages.Render),
///     ecs.createSystemCached(uiRenderSystem, zevy_ecs.DefaultParamRegistry),
/// );
/// ```
pub fn uiRenderSystem(
    _: *zevy_ecs.Manager,
    // Query for text labels
    text_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        text: components.UIText,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for buttons
    button_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        button: components.UIButton,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for toggles
    toggle_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        toggle: components.UIToggle,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for sliders
    slider_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        slider: components.UISlider,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for progress bars
    progress_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        progress: components.UIProgressBar,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for text boxes
    textbox_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        textbox: components.UITextBox,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for panels
    panel_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        panel: components.UIPanel,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for scroll panels
    scroll_panel_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        scroll_panel: components.UIScrollPanel,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for dropdowns
    dropdown_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        dropdown: components.UIDropdown,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for images
    image_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        image: components.UIImage,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for spinners
    spinner_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        spinner: components.UISpinner,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for color pickers
    color_picker_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        picker: components.UIColorPicker,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for list views
    list_view_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        list_view: components.UIListView,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for message boxes
    message_box_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        message_box: components.UIMessageBox,
        visible: ?components.UIVisible,
    }, .{}),
    // Query for tab bars
    tab_bar_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        tab_bar: components.UITabBar,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    // Render panels first (backgrounds)
    while (panel_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderPanel(q.rect.*, q.panel.*, vis);
    }

    // Render scroll panels
    while (scroll_panel_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderScrollPanel(q.rect.*, q.scroll_panel, vis);
    }

    // Render images
    while (image_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderImage(q.rect.*, q.image.*, vis);
    }

    // Render text labels
    while (text_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderText(q.rect.*, q.text.*, vis);
    }

    // Render progress bars
    while (progress_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderProgressBar(q.rect.*, q.progress.*, vis);
    }

    // Render buttons
    while (button_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderButton(q.rect.*, q.button, vis);
    }

    // Render toggles
    while (toggle_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderToggle(q.rect.*, q.toggle, vis);
    }

    // Render sliders
    while (slider_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderSlider(q.rect.*, q.slider, vis);
    }

    // Render text boxes
    while (textbox_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderTextBox(q.rect.*, q.textbox, vis);
    }

    // Render dropdowns
    while (dropdown_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderDropdown(q.rect.*, q.dropdown, vis);
    }

    // Render spinners
    while (spinner_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderSpinner(q.rect.*, q.spinner, vis);
    }

    // Render color pickers
    while (color_picker_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderColorPicker(q.rect.*, q.picker, vis);
    }

    // Render list views
    while (list_view_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderListView(q.rect.*, q.list_view, vis);
    }

    // Render tab bars
    while (tab_bar_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderTabBar(q.rect.*, q.tab_bar, vis);
    }

    // Render message boxes last (modal overlays)
    while (message_box_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderMessageBox(q.rect.*, q.message_box, vis);
    }
}

/// UI Input System
/// Handles input for interactive UI components
/// This system should be called during the update stage before rendering
///
/// Example usage with zevy_ecs:
/// ```zig
/// scheduler.addSystem(
///     zevy_ecs.Stage(zevy_ecs.Stages.Update),
///     ecs.createSystemCached(uiInputSystem, zevy_ecs.DefaultParamRegistry),
/// );
/// ```
pub fn uiInputSystem(
    _: *zevy_ecs.Manager,
    // Query for buttons
    button_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        button: components.UIButton,
        visible: ?components.UIVisible,
    }, .{}),
) void {
    // Update button hover states
    const mouse_pos = input.getMousePosition() orelse return;
    while (button_query.next()) |q| {
        if (q.visible) |v| {
            if (!v.visible) continue;
        }

        const bounds = q.rect.toRectangle();
        q.button.hovered = rl.checkCollisionPointRec(mouse_pos, bounds);
    }
}

/// Layout calculation system for flex layouts
/// This is a placeholder for future implementation
pub fn flexLayoutSystem(
    _: *zevy_ecs.Manager,
    container_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        flex: layout.FlexLayout,
        container: layout.UIContainer,
    }, .{}),
) void {
    _ = container_query;
    // TODO: Implement flex layout algorithm
    // This would query child entities and position them according to flex rules
}

/// Layout calculation system for grid layouts
/// This is a placeholder for future implementation
pub fn gridLayoutSystem(
    _: *zevy_ecs.Manager,
    container_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        grid: layout.GridLayout,
        container: layout.UIContainer,
    }, .{}),
) void {
    _ = container_query;
    // TODO: Implement grid layout algorithm
    // This would query child entities and position them in a grid
}
