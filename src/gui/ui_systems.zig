const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const zevy_ecs = @import("zevy_ecs");
const input = @import("../input/input.zig");
const io_types = @import("../io/types.zig");
const components = @import("ui_components.zig");
const layout = @import("ui_layout.zig");
const renderer = @import("ui_renderer.zig");
const icons = @import("../input/icons.zig");
const Assets = @import("../io/assets.zig").Assets;
const ui_resources = @import("resources.zig");
const ui_style = @import("style.zig");

pub fn startupUiSystem(
    commands: *zevy_ecs.Commands,
) !void {
    rg.loadStyleDefault();
    const default_font = try rl.getFontDefault();
    rg.setFont(default_font);
    // Populate the default style with the default font and register it. Ignore if already present.
    var style = ui_style.UIStyle.init();
    style.font = default_font;
    _ = commands.addResource(ui_style.UIStyle, style) catch {};
}

const ChildInfo = struct {
    child: zevy_ecs.Entity,
    rect: *components.UIRect,
    flex_item: ?*layout.FlexItem,
    base: f32,
    order: i32,
};

/// Collects children from a parent entity, caches their UIRect and FlexItem components,
/// and sorts them by order field for stable, deterministic layout.
fn collectAndSortChildren(
    commands: *zevy_ecs.Commands,
    children: []const zevy_ecs.Entity,
    is_row: bool,
    allocator: std.mem.Allocator,
) !struct {
    infos: std.ArrayList(ChildInfo),
    grow_sum: f32,
    shrink_sum: f32,
    total_base: f32,
} {
    var child_infos = try std.ArrayList(ChildInfo).initCapacity(allocator, children.len);
    var grow_sum: f32 = 0.0;
    var shrink_sum: f32 = 0.0;
    var total_base: f32 = 0.0;

    for (children) |child| {
        // Skip children without UIRect
        if (try commands.getComponent(child, components.UIRect)) |child_rect| {
            // Default flex item if component missing
            var fi: layout.FlexItem = layout.FlexItem.init();
            if (try commands.getComponent(child, layout.FlexItem)) |fptr| fi = fptr.*;

            // Calculate base size from basis or current dimension
            const base = if (fi.basis) |b| b else if (is_row) child_rect.width else child_rect.height;

            grow_sum += fi.grow;
            shrink_sum += fi.shrink;
            total_base += base;

            try child_infos.append(allocator, ChildInfo{
                .child = child,
                .rect = child_rect,
                .flex_item = try commands.getComponent(child, layout.FlexItem),
                .base = base,
                .order = fi.order,
            });
        }
    }

    // Stable insertion sort by order field
    var i: usize = 1;
    while (i < child_infos.items.len) : (i += 1) {
        var j = i;
        while (j > 0 and child_infos.items[j - 1].order > child_infos.items[j].order) : (j -= 1) {
            const tmp = child_infos.items[j - 1];
            child_infos.items[j - 1] = child_infos.items[j];
            child_infos.items[j] = tmp;
        }
    }

    return .{
        .infos = child_infos,
        .grow_sum = grow_sum,
        .shrink_sum = shrink_sum,
        .total_base = total_base,
    };
}

/// Computes the layout size for each child considering grow/shrink and min/max constraints.
/// Returns a list of computed sizes matching child_infos length.
fn computeFlexSizes(
    allocator: std.mem.Allocator,
    child_infos: []const ChildInfo,
    main_size: f32,
    gap_size: f32,
    total_base: f32,
    is_row: bool,
) !std.ArrayList(f32) {
    const gaps_total = if (child_infos.len > 1) gap_size * @as(f32, @floatFromInt(child_infos.len - 1)) else 0.0;
    const available = main_size - total_base - gaps_total;

    var computed_sizes = try std.ArrayList(f32).initCapacity(allocator, child_infos.len);

    if (available > 0) {
        // Distribute grow space with constraint handling
        var sizes = try std.ArrayList(f32).initCapacity(allocator, child_infos.len);
        defer sizes.deinit(allocator);

        for (child_infos) |ci| try sizes.append(allocator, ci.base);

        // Track items still eligible to grow
        var free_indexes = try std.ArrayList(usize).initCapacity(allocator, child_infos.len);
        defer free_indexes.deinit(allocator);

        var grow_sum: f32 = 0.0;
        for (child_infos, 0..) |ci, idx| {
            var fi: layout.FlexItem = layout.FlexItem.init();
            if (ci.flex_item) |f| fi = f.*;
            if (fi.grow > 0) {
                try free_indexes.append(allocator, idx);
                grow_sum += fi.grow;
            }
        }

        var remaining_available = available;
        var remaining_grow = grow_sum;

        while (free_indexes.items.len > 0) {
            var clamped_any = false;

            // Try proportional allocation first
            var j: usize = 0;
            while (j < free_indexes.items.len) : (j += 1) {
                const idx = free_indexes.items[j];
                var fi: layout.FlexItem = layout.FlexItem.init();
                if (child_infos[idx].flex_item) |f| fi = f.*;

                const add = remaining_available * (fi.grow / remaining_grow);
                const tentative = sizes.items[idx] + add;
                const clamped = if (child_infos[idx].flex_item) |f|
                    (if (is_row) f.constraints.clampWidth(tentative) else f.constraints.clampHeight(tentative))
                else
                    tentative;

                if (clamped < tentative) {
                    // Hit max constraint - clamp and remove from grow pool
                    const consumed = clamped - sizes.items[idx];
                    sizes.items[idx] = clamped;
                    remaining_available -= consumed;
                    remaining_grow -= fi.grow;
                    _ = free_indexes.swapRemove(j);
                    clamped_any = true;
                    continue;
                }
                j += 1;
            }

            if (!clamped_any) {
                // Final allocation across remaining free items
                for (free_indexes.items) |idx| {
                    var fi: layout.FlexItem = layout.FlexItem.init();
                    if (child_infos[idx].flex_item) |f| fi = f.*;
                    const add = remaining_available * (fi.grow / remaining_grow);
                    sizes.items[idx] += add;
                }
                break;
            }
        }

        for (sizes.items) |s| try computed_sizes.append(allocator, s);
    } else if (available < 0) {
        // Distribute shrink space
        var shrink_sum: f32 = 0.0;
        for (child_infos) |ci| {
            var fi: layout.FlexItem = layout.FlexItem.init();
            if (ci.flex_item) |f| fi = f.*;
            shrink_sum += fi.shrink;
        }

        if (shrink_sum > 0) {
            const deficit = -available;
            for (child_infos) |ci| {
                var fi: layout.FlexItem = layout.FlexItem.init();
                if (ci.flex_item) |f| fi = f.*;
                const deduct = deficit * (fi.shrink / shrink_sum);
                var final_size = @max(0.0, ci.base - deduct);
                if (ci.flex_item) |f| {
                    final_size = if (is_row) f.constraints.clampWidth(final_size) else f.constraints.clampHeight(final_size);
                }
                try computed_sizes.append(allocator, final_size);
            }
        } else {
            // No grow/shrink applicable - use basis with constraints
            for (child_infos) |ci| {
                var final_size = ci.base;
                if (ci.flex_item) |f| {
                    final_size = if (is_row) f.constraints.clampWidth(final_size) else f.constraints.clampHeight(final_size);
                }
                try computed_sizes.append(allocator, final_size);
            }
        }
    } else {
        // No grow/shrink applicable - use basis with constraints
        for (child_infos) |ci| {
            var final_size = ci.base;
            if (ci.flex_item) |f| {
                final_size = if (is_row) f.constraints.clampWidth(final_size) else f.constraints.clampHeight(final_size);
            }
            try computed_sizes.append(allocator, final_size);
        }
    }

    return computed_sizes;
}

/// Positions children within a container based on justify_content and align_items alignment.
/// Handles both forward and reverse flex directions.
fn positionChildren(
    child_infos: []const ChildInfo,
    computed_sizes: []const f32,
    container_rect: components.UIRect,
    flex: *const layout.FlexLayout,
    cross_size: f32,
    is_row: bool,
    is_reverse: bool,
) void {
    const main_size = if (is_row)
        container_rect.width - flex.padding.getTotalHorizontal()
    else
        container_rect.height - flex.padding.getTotalVertical();

    var sum_computed: f32 = 0.0;
    for (computed_sizes) |s| sum_computed += s;

    const gaps_total = if (child_infos.len > 1) flex.gap * @as(f32, @floatFromInt(child_infos.len - 1)) else 0.0;
    const remaining_space = main_size - (sum_computed + gaps_total);

    var offset: f32 = if (is_row) container_rect.x + flex.padding.left else container_rect.y + flex.padding.top;
    var gap = flex.gap;

    // Apply justify_content
    switch (flex.justify_content) {
        .start => {},
        .center => offset += remaining_space / 2.0,
        .end => offset += remaining_space,
        .space_between => {
            if (child_infos.len > 1) {
                gap = flex.gap + (remaining_space / @as(f32, @floatFromInt(child_infos.len - 1)));
            }
        },
        .space_around => {
            const gap_extra = remaining_space / @as(f32, @floatFromInt(child_infos.len));
            offset += gap_extra / 2.0;
            gap += gap_extra;
        },
        .space_evenly => {
            const gap_extra = remaining_space / @as(f32, @floatFromInt(child_infos.len + 1));
            offset += gap_extra;
            gap += gap_extra;
        },
    }

    // Position children (reverse or forward)
    if (is_reverse) {
        var pos = offset + sum_computed;
        var i = child_infos.len - 1;
        while (true) {
            const size = computed_sizes[i];
            const crect = child_infos[i].rect;

            if (is_row) {
                crect.x = pos - size;
                crect.width = size;
                // Apply align_self or align_items
                var item_align = flex.align_items;
                if (child_infos[i].flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.y = container_rect.y + flex.padding.top,
                    .start => crect.y = container_rect.y + flex.padding.top,
                    .center => crect.y = container_rect.y + flex.padding.top + (cross_size - crect.height) / 2.0,
                    .end => crect.y = container_rect.y + flex.padding.top + cross_size - crect.height,
                    .stretch => crect.height = cross_size,
                }
            } else {
                crect.y = pos - size;
                crect.height = size;
                var item_align = flex.align_items;
                if (child_infos[i].flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.x = container_rect.x + flex.padding.left,
                    .start => crect.x = container_rect.x + flex.padding.left,
                    .center => crect.x = container_rect.x + flex.padding.left + (cross_size - crect.width) / 2.0,
                    .end => crect.x = container_rect.x + flex.padding.left + cross_size - crect.width,
                    .stretch => crect.width = cross_size,
                }
            }

            pos -= (size + gap);
            if (i == 0) break;
            i -= 1;
        }
    } else {
        for (child_infos, 0..) |ci, i| {
            const size = computed_sizes[i];
            const crect = ci.rect;

            if (is_row) {
                crect.x = offset;
                crect.width = size;
                var item_align = flex.align_items;
                if (ci.flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.y = container_rect.y + flex.padding.top,
                    .start => crect.y = container_rect.y + flex.padding.top,
                    .center => crect.y = container_rect.y + flex.padding.top + (cross_size - crect.height) / 2.0,
                    .end => crect.y = container_rect.y + flex.padding.top + cross_size - crect.height,
                    .stretch => crect.height = cross_size,
                }
            } else {
                crect.y = offset;
                crect.height = size;
                var item_align = flex.align_items;
                if (ci.flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.x = container_rect.x + flex.padding.left,
                    .start => crect.x = container_rect.x + flex.padding.left,
                    .center => crect.x = container_rect.x + flex.padding.left + (cross_size - crect.width) / 2.0,
                    .end => crect.x = container_rect.x + flex.padding.left + cross_size - crect.width,
                    .stretch => crect.width = cross_size,
                }
            }

            offset += size + gap;
        }
    }
}

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
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for toggles
    toggle_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        toggle: components.UIToggle,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for sliders
    slider_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        slider: components.UISlider,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for progress bars
    progress_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        progress: components.UIProgressBar,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for text boxes
    textbox_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        textbox: components.UITextBox,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for panels
    panel_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        panel: components.UIPanel,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for scroll panels
    scroll_panel_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        scroll_panel: components.UIScrollPanel,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for dropdowns
    dropdown_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        dropdown: components.UIDropdown,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for images
    image_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        image: components.UIImage,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for spinners
    spinner_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        spinner: components.UISpinner,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for color pickers
    color_picker_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        picker: components.UIColorPicker,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for list views
    list_view_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        list_view: components.UIListView,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for message boxes
    message_box_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        message_box: components.UIMessageBox,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
    // Query for tab bars
    tab_bar_query: zevy_ecs.Query(struct {
        rect: components.UIRect,
        tab_bar: components.UITabBar,
        visible: ?components.UIVisible,
        enabled: ?components.UIEnabled,
    }, .{}),
) anyerror!void {
    // Render panels first (backgrounds)
    var panel_count: usize = 0;
    while (panel_query.next()) |q| {
        panel_count += 1;
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderPanel(q.rect, q.panel, vis);
    }

    // Render scroll panels
    while (scroll_panel_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderScrollPanel(q.rect.*, q.scroll_panel, vis);
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Render images
    while (image_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderImage(q.rect.*, q.image.*, vis);
    }

    // Render text labels
    while (text_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderText(q.rect, q.text, vis);
    }

    // Render progress bars
    while (progress_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        renderer.renderProgressBar(q.rect.*, q.progress.*, vis);
    }

    // Render buttons
    while (button_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderButton(q.rect.*, q.button, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render toggles
    while (toggle_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderToggle(q.rect.*, q.toggle, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render sliders
    while (slider_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderSlider(q.rect.*, q.slider, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render text boxes
    while (textbox_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderTextBox(q.rect.*, q.textbox, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render dropdowns
    while (dropdown_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderDropdown(q.rect.*, q.dropdown, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render spinners
    while (spinner_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderSpinner(q.rect.*, q.spinner, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render color pickers
    while (color_picker_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderColorPicker(q.rect.*, q.picker, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render list views
    while (list_view_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderListView(q.rect.*, q.list_view, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render tab bars
    while (tab_bar_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderTabBar(q.rect.*, q.tab_bar, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render message boxes last (modal overlays)
    while (message_box_query.next()) |q| {
        const vis = if (q.visible) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        renderer.renderMessageBox(q.rect.*, q.message_box, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }
}

/// UI Input Key Render System
/// Renders input key icons/text for UIInputKey components that are children of other UI elements
/// This system should be called after uiRenderSystem during the render stage
///
/// Example usage with zevy_ecs:
/// ```zig
/// scheduler.addSystem(
///     zevy_ecs.Stage(zevy_ecs.Stages.Render),
///     uiInputKeyRenderSystem,
///     zevy_ecs.DefaultParamRegistry,
/// );
/// ```
pub fn uiInputKeyRenderSystem(
    commands: *zevy_ecs.Commands,
    // Query for input keys that are children
    input_key_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        input_key: components.UIInputKey,
        children: zevy_ecs.Relation(zevy_ecs.relations.Child),
    }, .{}),
    style: zevy_ecs.Res(@import("style.zig").UIStyle),
    icon_atlas: zevy_ecs.Res(ui_resources.UIIconAtlasHandle),
) anyerror!void {
    while (input_key_query.next()) |q| {
        const ui_key: *components.UIInputKey = q.input_key;
        const parent: zevy_ecs.Entity = q.children.target;
        const parent_rect_opt = commands.getComponent(parent, components.UIRect) catch continue;
        const parent_rect = parent_rect_opt orelse continue;
        const atlas_ptr = icon_atlas.ptr.atlas;
        renderer.renderInputKeyAt(parent_rect.toRectangle(), ui_key.asSlice()[0], atlas_ptr, style.ptr);
    }
}

/// Helper: load an IconAtlas via `Assets` and register it as an ECS resource.
pub fn registerIconAtlasFromAssets(manager: *zevy_ecs.Manager, assets: *Assets, path: []const u8, settings: anytype) void {
    const IconAtlas = @import("../io/types.zig").IconAtlas;

    // Register the handle as an ECS resource so systems can look it up via Assets.getAsset
    const handle = assets.loadAssetNow(IconAtlas, path, settings) catch |err| {
        std.log.err("Failed to load icon atlas from '{s}': {}", .{ path, err });
        return;
    };
    _ = manager.addResource(@import("resources.zig").UIIconAtlasHandle, @import("resources.zig").UIIconAtlasHandle.init(handle)) catch |err| {
        std.log.err("Failed to register icon atlas resource: {}", .{err});
    };
}

/// Layout calculation system for flex layouts
/// Uses extracted helper functions for child collection, size computation, and positioning.
pub fn flexLayoutSystem(
    commands: *zevy_ecs.Commands,
    container_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        flex: layout.FlexLayout,
        container: layout.UIContainer,
    }, .{}),
    rel: *zevy_ecs.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.Child);
        if (children.len == 0) continue;

        const is_row = switch (cq.flex.direction) {
            .row, .row_reverse => true,
            .column, .column_reverse => false,
        };
        const is_reverse = switch (cq.flex.direction) {
            .row_reverse, .column_reverse => true,
            else => false,
        };

        // Collect and sort children
        var collected = try collectAndSortChildren(commands, children, is_row, commands.allocator);
        defer collected.infos.deinit(commands.allocator);

        if (collected.infos.items.len == 0) continue;

        // Calculate available space
        const main_size = if (is_row)
            cq.rect.width - cq.flex.padding.getTotalHorizontal()
        else
            cq.rect.height - cq.flex.padding.getTotalVertical();

        const cross_size = if (is_row)
            cq.rect.height - cq.flex.padding.getTotalVertical()
        else
            cq.rect.width - cq.flex.padding.getTotalHorizontal();

        // Compute sizes considering grow/shrink and constraints
        var computed_sizes = try computeFlexSizes(
            commands.allocator,
            collected.infos.items,
            main_size,
            cq.flex.gap,
            collected.total_base,
            is_row,
        );
        defer computed_sizes.deinit(commands.allocator);

        // Position children
        positionChildren(
            collected.infos.items,
            computed_sizes.items,
            cq.rect.*,
            cq.flex,
            cross_size,
            is_row,
            is_reverse,
        );
    }
}

/// Layout calculation system for grid layouts
/// Positions UI elements in a grid based on column/row configuration and gap settings.
pub fn gridLayoutSystem(
    commands: *zevy_ecs.Commands,
    container_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        grid: layout.GridLayout,
        container: layout.UIContainer,
    }, .{}),
    rel: *zevy_ecs.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.Child);
        if (children.len == 0) continue;

        // Collect children (no sorting needed for grid - order by insertion)
        var child_infos = try std.ArrayList(ChildInfo).initCapacity(commands.allocator, children.len);
        defer child_infos.deinit(commands.allocator);

        for (children) |child| {
            if (try commands.getComponent(child, components.UIRect)) |child_rect| {
                try child_infos.append(commands.allocator, ChildInfo{
                    .child = child,
                    .rect = child_rect,
                    .flex_item = null, // Grid doesn't use flex items
                    .base = 0, // unused for grid
                    .order = 0, // no ordering in grid
                });
            }
        }

        if (child_infos.items.len == 0) continue;
        // Calculate grid dimensions
        const grid = cq.grid;
        const available_width = cq.rect.width - grid.padding.getTotalHorizontal();
        const available_height = cq.rect.height - grid.padding.getTotalVertical();

        const num_columns = if (grid.columns > 0) grid.columns else @max(1, @as(u32, @intCast(@divFloor(@as(i32, @intCast(child_infos.items.len)) + @as(i32, @intCast(grid.rows)) - 1, @as(i32, @intCast(grid.rows))))));
        const num_rows = if (grid.rows > 0) grid.rows else @max(1, @as(u32, @intCast(@divFloor(@as(i32, @intCast(child_infos.items.len)) + @as(i32, @intCast(num_columns)) - 1, @as(i32, @intCast(num_columns))))));

        // Calculate cell dimensions
        const total_col_gap = if (num_columns > 1) grid.column_gap * @as(f32, @floatFromInt(num_columns - 1)) else 0.0;
        const total_row_gap = if (num_rows > 1) grid.row_gap * @as(f32, @floatFromInt(num_rows - 1)) else 0.0;

        const cell_width = (available_width - total_col_gap) / @as(f32, @floatFromInt(num_columns));
        const cell_height = (available_height - total_row_gap) / @as(f32, @floatFromInt(num_rows));

        // Position children in grid
        for (child_infos.items, 0..) |ci, idx| {
            const col = idx % num_columns;
            const row = @divFloor(idx, num_columns);

            const x = cq.rect.x + grid.padding.left + @as(f32, @floatFromInt(col)) * (cell_width + grid.column_gap);
            const y = cq.rect.y + grid.padding.top + @as(f32, @floatFromInt(row)) * (cell_height + grid.row_gap);

            ci.rect.x = x;
            ci.rect.y = y;
            ci.rect.width = cell_width;
            ci.rect.height = cell_height;
        }
    }
}

pub fn anchorLayoutSystem(
    commands: *zevy_ecs.Commands,
    container_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        container: layout.UIContainer,
    }, .{}),
    rel: *zevy_ecs.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const container_rect = cq.rect.*;
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.Child);
        if (children.len == 0) continue;

        for (children) |child| {
            const rect = try commands.getComponent(child, components.UIRect) orelse continue;
            const anchor = try commands.getComponent(child, layout.AnchorLayout) orelse continue;

            const cw = rect.width;
            const ch = rect.height;

            var x: f32 = container_rect.x;
            var y: f32 = container_rect.y;

            switch (anchor.anchor) {
                .top_left => {},
                .top_center => {
                    x += (container_rect.width - cw) / 2.0;
                },
                .top_right => {
                    x += container_rect.width - cw;
                },
                .center_left => {
                    y += (container_rect.height - ch) / 2.0;
                },
                .center => {
                    x += (container_rect.width - cw) / 2.0;
                    y += (container_rect.height - ch) / 2.0;
                },
                .center_right => {
                    x += container_rect.width - cw;
                    y += (container_rect.height - ch) / 2.0;
                },
                .bottom_left => {
                    y += container_rect.height - ch;
                },
                .bottom_center => {
                    x += (container_rect.width - cw) / 2.0;
                    y += container_rect.height - ch;
                },
                .bottom_right => {
                    x += container_rect.width - cw;
                    y += container_rect.height - ch;
                },
            }

            rect.x = x + anchor.offset_x;
            rect.y = y + anchor.offset_y;
        }
    }
}

pub fn dockLayoutSystem(
    commands: *zevy_ecs.Commands,
    container_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        container: layout.UIContainer,
    }, .{}),
    rel: *zevy_ecs.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const container_rect = cq.rect.*;
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.Child);
        if (children.len == 0) continue;

        var remaining = container_rect;

        for (children) |child| {
            const rect = try commands.getComponent(child, components.UIRect) orelse continue;
            const dock = try commands.getComponent(child, layout.DockLayout) orelse continue;

            switch (dock.side) {
                .left => {
                    rect.x = remaining.x;
                    rect.y = remaining.y;
                    rect.height = remaining.height;
                    remaining.x += rect.width;
                    remaining.width -= rect.width;
                },
                .right => {
                    rect.x = remaining.x + remaining.width - rect.width;
                    rect.y = remaining.y;
                    rect.height = remaining.height;
                    remaining.width -= rect.width;
                },
                .top => {
                    rect.x = remaining.x;
                    rect.y = remaining.y;
                    rect.width = remaining.width;
                    remaining.y += rect.height;
                    remaining.height -= rect.height;
                },
                .bottom => {
                    rect.x = remaining.x;
                    rect.y = remaining.y + remaining.height - rect.height;
                    rect.width = remaining.width;
                    remaining.height -= rect.height;
                },
                .fill => {
                    rect.x = remaining.x;
                    rect.y = remaining.y;
                    rect.width = remaining.width;
                    rect.height = remaining.height;
                },
            }
        }
    }
}
