const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const rg = @import("raygui");

const zevy_reflect = @import("zevy_reflect");
const zevy_ecs = @import("zevy_ecs");
const input = @import("../input/root.zig");
const io_types = @import("../io/types.zig");
const components = @import("ui_components.zig");
const layout = @import("ui_layout.zig");
const renderer = @import("ui_renderer.zig");
const icons = @import("../input/icons.zig");
const Assets = @import("../io/assets.zig").Assets;
const ui_resources = @import("res.zig");
const ui_style = @import("style.zig");
const app_plugin = @import("../app.plugin.zig");

comptime {
    @setEvalBranchQuota(4000);
}

pub fn startupUiSystem(commands: zevy_ecs.params.Commands, assets: zevy_ecs.params.ResMut(Assets), local_test: zevy_ecs.params.Local(u8)) !void {
    _ = assets;

    if (local_test.get() == null) {
        local_test.set(1);
    } else {
        local_test.getPtr().?.* += 1;
        if (builtin.is_test) std.debug.print("Startup system called {d} times\n", .{local_test.get().?});
    }
    commands.addResource(ui_style.UIStyle, ui_style.UIStyle.init()) catch {};

    if (!rl.isWindowReady()) {
        std.debug.print("Window not ready, skipping UI startup.\n", .{});
        return;
    }

    rg.loadStyleDefault();
    const default_font = try rl.getFontDefault();
    rg.setFont(default_font);

    if (commands.manager().getResource(ui_style.UIStyle)) |style_ref| {
        defer style_ref.deinit();
        var style_guard = style_ref.lockWrite();
        defer style_guard.deinit();
        style_guard.get().font = default_font;
    }

    //const assets_ref = assets.get();
    // Register the default icon atlas from assets. This allows UI components to use icons in their default state.
    //registerIconAtlasFromAssets(commands.manager(), assets_ref, "embedded://Keyboard & Mouse/keyboard-&-mouse_sheet_default.xml", .{});
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
    commands: zevy_ecs.params.Commands,
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
        if (try commands.manager().getComponent(child, components.UIRect)) |child_rect| {
            // Default flex item if component missing
            var fi: layout.FlexItem = layout.FlexItem.init();
            if (try commands.manager().getComponent(child, layout.FlexItem)) |fptr| fi = fptr.*;

            // Calculate base size from basis or current dimension
            const base = if (fi.basis) |b| b else if (is_row) child_rect.rect.width else child_rect.rect.height;

            grow_sum += fi.grow;
            shrink_sum += fi.shrink;
            total_base += base;

            try child_infos.append(allocator, ChildInfo{
                .child = child,
                .rect = child_rect,
                .flex_item = try commands.manager().getComponent(child, layout.FlexItem),
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
        container_rect.rect.width - flex.padding.getTotalHorizontal()
    else
        container_rect.rect.height - flex.padding.getTotalVertical();

    var sum_computed: f32 = 0.0;
    for (computed_sizes) |s| sum_computed += s;

    const gaps_total = if (child_infos.len > 1) flex.gap * @as(f32, @floatFromInt(child_infos.len - 1)) else 0.0;
    const remaining_space = main_size - (sum_computed + gaps_total);

    var offset: f32 = if (is_row) container_rect.rect.x + flex.padding.left else container_rect.rect.y + flex.padding.top;
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
                crect.rect.x = pos - size;
                crect.rect.width = size;
                // Apply align_self or align_items
                var item_align = flex.align_items;
                if (child_infos[i].flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.rect.y = container_rect.rect.y + flex.padding.top,
                    .start => crect.rect.y = container_rect.rect.y + flex.padding.top,
                    .center => crect.rect.y = container_rect.rect.y + flex.padding.top + (cross_size - crect.rect.height) / 2.0,
                    .end => crect.rect.y = container_rect.rect.y + flex.padding.top + cross_size - crect.rect.height,
                    .stretch => crect.rect.height = cross_size,
                }
            } else {
                crect.rect.y = pos - size;
                crect.rect.height = size;
                var item_align = flex.align_items;
                if (child_infos[i].flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.rect.x = container_rect.rect.x + flex.padding.left,
                    .start => crect.rect.x = container_rect.rect.x + flex.padding.left,
                    .center => crect.rect.x = container_rect.rect.x + flex.padding.left + (cross_size - crect.rect.width) / 2.0,
                    .end => crect.rect.x = container_rect.rect.x + flex.padding.left + cross_size - crect.rect.width,
                    .stretch => crect.rect.width = cross_size,
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
                crect.rect.x = offset;
                crect.rect.width = size;
                var item_align = flex.align_items;
                if (ci.flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.rect.y = container_rect.rect.y + flex.padding.top,
                    .start => crect.rect.y = container_rect.rect.y + flex.padding.top,
                    .center => crect.rect.y = container_rect.rect.y + flex.padding.top + (cross_size - crect.rect.height) / 2.0,
                    .end => crect.rect.y = container_rect.rect.y + flex.padding.top + cross_size - crect.rect.height,
                    .stretch => crect.rect.height = cross_size,
                }
            } else {
                crect.rect.y = offset;
                crect.rect.height = size;
                var item_align = flex.align_items;
                if (ci.flex_item) |f| {
                    if (f.align_self != layout.FlexItemAlign.auto) item_align = f.align_self;
                }
                switch (item_align) {
                    .auto => crect.rect.x = container_rect.rect.x + flex.padding.left,
                    .start => crect.rect.x = container_rect.rect.x + flex.padding.left,
                    .center => crect.rect.x = container_rect.rect.x + flex.padding.left + (cross_size - crect.rect.width) / 2.0,
                    .end => crect.rect.x = container_rect.rect.x + flex.padding.left + cross_size - crect.rect.width,
                    .stretch => crect.rect.width = cross_size,
                }
            }

            offset += size + gap;
        }
    }
}

pub fn onAddedUiText(
    commands: zevy_ecs.params.Commands,
    added: zevy_ecs.params.OnAdded(components.UIText),
    ui_style_res: zevy_ecs.params.Res(ui_style.UIStyle),
    rel: zevy_ecs.params.Relations,
) !void {
    for (added.iter()) |entry| {
        if ((commands.manager().hasComponent(entry.entity, components.UIRect) catch false) == false) {
            const comp = entry.comp;
            const measurement = rl.measureTextEx(ui_style_res.get().font, comp.text, @floatFromInt(comp.font_size), 1.0);
            if (try rel.getParent(commands.manager(), entry.entity, zevy_ecs.relations.kinds.Child)) |parent| {
                // Adjust for parent's padding if applicable
                var pad: layout.Padding = undefined;
                if (commands.manager().getComponent(parent, layout.FlexLayout) catch null) |fl_comp| {
                    pad = fl_comp.padding;
                } else if (commands.manager().getComponent(parent, layout.GridLayout) catch null) |gl_comp| {
                    pad = gl_comp.padding;
                } else {
                    pad = layout.Padding.uniform(0.0);
                }
                _ = try commands.addComponent(entry.entity, components.UIRect, components.UIRect{
                    .x = pad.left,
                    .y = pad.top,
                    .width = measurement.x,
                    .height = measurement.y,
                });
            } else {
                _ = try commands.addComponent(entry.entity, components.UIRect, components.UIRect{
                    .x = 0,
                    .y = 0,
                    .width = measurement.x,
                    .height = measurement.y,
                });
            }
        }
    }
}

/// UI Render System
/// Renders all UI entities based on their components
/// This system should be called during the render stage of your game loop
const TextRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    text: components.UIText,
    vis: ?components.UIVisible,
});

const ButtonRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    button: components.UIButton,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const ToggleRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    toggle: components.UIToggle,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const SliderRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    slider: components.UISlider,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const ProgressRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    progress: components.UIProgressBar,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const TextBoxRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    textbox: components.UITextBox,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const PanelRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    panel: components.UIPanel,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const ScrollPanelRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    scroll_panel: components.UIScrollPanel,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const DropdownRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    dropdown: components.UIDropdown,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const ImageRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    image: components.UIImage,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const SpinnerRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    spinner: components.UISpinner,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const ColorPickerRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    picker: components.UIColorPicker,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const ListViewRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    list_view: components.UIListView,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const MessageBoxRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    message_box: components.UIMessageBox,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

const TabBarRenderQuery = zevy_ecs.params.Query(struct {
    rect: components.UIRect,
    tab_bar: components.UITabBar,
    vis: ?components.UIVisible,
    enabled: ?components.UIEnabled,
});

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
    text_query: TextRenderQuery,
    // Query for buttons
    button_query: ButtonRenderQuery,
    // Query for toggles
    toggle_query: ToggleRenderQuery,
    // Query for sliders
    slider_query: SliderRenderQuery,
    // Query for progress bars
    progress_query: ProgressRenderQuery,
    // Query for text boxes
    textbox_query: TextBoxRenderQuery,
    // Query for panels
    panel_query: PanelRenderQuery,
    // Query for scroll panels
    scroll_panel_query: ScrollPanelRenderQuery,
    // Query for dropdowns
    dropdown_query: DropdownRenderQuery,
    // Query for images
    image_query: ImageRenderQuery,
    // Query for spinners
    spinner_query: SpinnerRenderQuery,
    // Query for color pickers
    color_picker_query: ColorPickerRenderQuery,
    // Query for list views
    list_view_query: ListViewRenderQuery,
    // Query for message boxes
    message_box_query: MessageBoxRenderQuery,
    // Query for tab bars
    tab_bar_query: TabBarRenderQuery,
) anyerror!void {
    // Early out if window not ready to avoid unnecessary processing
    if (!rl.isWindowReady()) return;

    // Render panels first (backgrounds)
    var panel_count: usize = 0;
    while (panel_query.next()) |q| {
        panel_count += 1;
        const vis = if (q.vis) |v| v.* else null;
        const rect = q.rect;
        renderer.renderPanel(rect.*, q.panel, vis);
    }

    // Render scroll panels
    while (scroll_panel_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderScrollPanel(rect.*, q.scroll_panel, vis);
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Render images
    while (image_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        const rect = q.rect;
        renderer.renderImage(rect.*, q.image.*, vis);
    }

    // Render text labels
    while (text_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        const rect = q.rect;
        renderer.renderText(rect.*, q.text, vis);
    }

    // Render progress bars
    while (progress_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        const rect = q.rect;
        renderer.renderProgressBar(rect.*, q.progress.*, vis);
    }

    // Render buttons
    while (button_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderButton(rect.*, q.button, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render toggles
    while (toggle_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderToggle(rect.*, q.toggle, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render sliders
    while (slider_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderSlider(rect.*, q.slider, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render text boxes
    while (textbox_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderTextBox(rect.*, q.textbox, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render dropdowns
    while (dropdown_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderDropdown(rect.*, q.dropdown, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render spinners
    while (spinner_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderSpinner(rect.*, q.spinner, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render color pickers
    while (color_picker_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderColorPicker(rect.*, q.picker, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render list views
    while (list_view_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderListView(rect.*, q.list_view, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render tab bars
    while (tab_bar_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderTabBar(rect.*, q.tab_bar, vis);
        rg.setState(@intFromEnum(rg.State.normal));
    }

    // Render message boxes last (modal overlays)
    while (message_box_query.next()) |q| {
        const vis = if (q.vis) |v| v.* else null;
        if (q.enabled) |en| rg.setState(@intFromEnum(if (en.state == false) rg.State.disabled else rg.State.normal)) else rg.setState(@intFromEnum(rg.State.normal));
        const rect = q.rect;
        renderer.renderMessageBox(rect.*, q.message_box, vis);
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
    commands: zevy_ecs.params.Commands,
    // Query for input keys that are children
    input_key_query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        input_key: components.UIInputKey,
        children: zevy_ecs.relations.Relation(zevy_ecs.relations.kinds.Child),
    }),
    style: zevy_ecs.params.Res(@import("style.zig").UIStyle),
) anyerror!void {
    // Early out if window not ready to avoid unnecessary processing
    if (!rl.isWindowReady()) return;

    var atlas_ptr: ?*const io_types.IconAtlas = null;
    if (commands.manager().getResource(ui_resources.UIIconAtlasHandle)) |atlas_ref| {
        defer atlas_ref.deinit();
        var atlas_guard = atlas_ref.lockRead();
        defer atlas_guard.deinit();
        atlas_ptr = atlas_guard.get().atlas;
    }

    while (input_key_query.next()) |q| {
        const ui_key: *components.UIInputKey = q.input_key;
        const parent: zevy_ecs.Entity = q.children.target;
        const parent_rect_opt = commands.manager().getComponent(parent, components.UIRect) catch continue;
        const parent_rect = parent_rect_opt orelse continue;
        renderer.renderInputKeyAt(parent_rect.*.rect, ui_key.asSlice()[0], atlas_ptr, style.get());
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
    manager.addResourceRetained(ui_resources.UIIconAtlasHandle, ui_resources.UIIconAtlasHandle.init(handle)) catch |err| {
        std.log.err("Failed to register icon atlas resource: {}", .{err});
    };
}

/// Layout calculation system for flex layouts
/// Uses extracted helper functions for child collection, size computation, and positioning.
pub fn flexLayoutSystem(
    commands: zevy_ecs.params.Commands,
    container_query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        flex: layout.FlexLayout,
        container: layout.UIContainer,
    }),
    rel: zevy_ecs.params.Relations,
) anyerror!void {
    var container_count: usize = 0;
    while (container_query.next()) |cq| {
        container_count += 1;
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.kinds.Child);
        if (children.len == 0) continue;
        const flex: *layout.FlexLayout = cq.flex;

        const is_row = switch (cq.flex.direction) {
            .row, .row_reverse => true,
            .column, .column_reverse => false,
        };
        const is_reverse = switch (cq.flex.direction) {
            .row_reverse, .column_reverse => true,
            else => false,
        };

        // Collect and sort children
        var collected = try collectAndSortChildren(commands, children, is_row, commands.allocator());
        defer collected.infos.deinit(commands.allocator());

        if (collected.infos.items.len == 0) continue;

        // Calculate available space
        const main_size = if (is_row)
            cq.rect.rect.width - flex.padding.getTotalHorizontal()
        else
            cq.rect.rect.height - flex.padding.getTotalVertical();

        const cross_size = if (is_row)
            cq.rect.rect.height - flex.padding.getTotalVertical()
        else
            cq.rect.rect.width - flex.padding.getTotalHorizontal();

        // Compute sizes considering grow/shrink and constraints
        var computed_sizes = try computeFlexSizes(
            commands.allocator(),
            collected.infos.items,
            main_size,
            cq.flex.gap,
            collected.total_base,
            is_row,
        );
        defer computed_sizes.deinit(commands.allocator());

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
    commands: zevy_ecs.params.Commands,
    container_query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        grid: layout.GridLayout,
        container: layout.UIContainer,
    }),
    rel: zevy_ecs.params.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.kinds.Child);
        if (children.len == 0) continue;

        // Collect children (no sorting needed for grid - order by insertion)
        var child_infos = try std.ArrayList(ChildInfo).initCapacity(commands.allocator(), children.len);
        defer child_infos.deinit(commands.allocator());

        for (children) |child| {
            var ent_cmds = commands.entity(child);
            defer ent_cmds.deinit();
            if (try ent_cmds.get(components.UIRect)) |child_rect| {
                try child_infos.append(commands.allocator(), ChildInfo{
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
        const available_width = cq.rect.rect.width - grid.padding.getTotalHorizontal();
        const available_height = cq.rect.rect.height - grid.padding.getTotalVertical();

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

            const x = cq.rect.rect.x + grid.padding.left + @as(f32, @floatFromInt(col)) * (cell_width + grid.column_gap);
            const y = cq.rect.rect.y + grid.padding.top + @as(f32, @floatFromInt(row)) * (cell_height + grid.row_gap);

            ci.rect.rect.x = x;
            ci.rect.rect.y = y;
            ci.rect.rect.width = cell_width;
            ci.rect.rect.height = cell_height;
        }
    }
}

pub fn anchorLayoutSystem(
    commands: zevy_ecs.params.Commands,
    container_query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        container: layout.UIContainer,
    }),
    rel: zevy_ecs.params.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const container_rect: rl.Rectangle = cq.rect.*.rect;
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.kinds.Child);
        if (children.len == 0) continue;

        for (children) |child| {
            var ent_cmds = commands.entity(child);
            defer ent_cmds.deinit();
            const child_ui_rect = try ent_cmds.get(components.UIRect) orelse continue;
            const anchor = try ent_cmds.get(layout.AnchorLayout) orelse continue;

            const cw = child_ui_rect.rect.width;
            const ch = child_ui_rect.rect.height;

            var x = container_rect.x;
            var y = container_rect.y;

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

            child_ui_rect.rect.x = x + anchor.offset_x;
            child_ui_rect.rect.y = y + anchor.offset_y;
        }
    }
}

pub fn dockLayoutSystem(
    commands: zevy_ecs.params.Commands,
    container_query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        rect: components.UIRect,
        container: layout.UIContainer,
    }),
    rel: zevy_ecs.params.Relations,
) anyerror!void {
    while (container_query.next()) |cq| {
        const container_rect = cq.rect.*.rect;
        const children = rel.getChildren(cq.entity, zevy_ecs.relations.kinds.Child);
        if (children.len == 0) continue;

        var remaining = container_rect;

        for (children) |child| {
            const ui_rect = try commands.manager().getComponent(child, components.UIRect) orelse continue;
            const dock = try commands.manager().getComponent(child, layout.DockLayout) orelse continue;

            switch (dock.side) {
                .left => {
                    ui_rect.rect.x = remaining.x;
                    ui_rect.rect.y = remaining.y;
                    ui_rect.rect.height = remaining.height;
                    remaining.x += ui_rect.rect.width;
                    remaining.width -= ui_rect.rect.width;
                },
                .right => {
                    ui_rect.rect.x = remaining.x + remaining.width - ui_rect.rect.width;
                    ui_rect.rect.y = remaining.y;
                    ui_rect.rect.height = remaining.height;
                    remaining.width -= ui_rect.rect.width;
                },
                .top => {
                    ui_rect.rect.x = remaining.x;
                    ui_rect.rect.y = remaining.y;
                    ui_rect.rect.width = remaining.width;
                    remaining.y += ui_rect.rect.height;
                    remaining.height -= ui_rect.rect.height;
                },
                .bottom => {
                    ui_rect.rect.x = remaining.x;
                    ui_rect.rect.y = remaining.y + remaining.height - ui_rect.rect.height;
                    ui_rect.rect.width = remaining.width;
                    remaining.height -= ui_rect.rect.height;
                },
                .fill => {
                    ui_rect.rect.x = remaining.x;
                    ui_rect.rect.y = remaining.y;
                    ui_rect.rect.width = remaining.width;
                    ui_rect.rect.height = remaining.height;
                },
            }
        }
    }
}

pub fn uiHierarchySystem(
    commands: zevy_ecs.params.Commands,
    added_nodes: zevy_ecs.params.OnAdded(components.UINode),
    removed_nodes: zevy_ecs.params.OnRemoved(components.UINode),
    added_containers: zevy_ecs.params.OnAdded(layout.UIContainer),
    removed_containers: zevy_ecs.params.OnRemoved(layout.UIContainer),
    container_query: zevy_ecs.params.Query(struct {
        entity: zevy_ecs.Entity,
        container: layout.UIContainer,
    }),
    relations: zevy_ecs.params.Relations,
) anyerror!void {
    const allocator = commands.allocator();
    // Process removed components/entities first
    for (removed_nodes.iter()) |entity| {
        relations.removeEntity(entity);
    }
    for (removed_containers.iter()) |entity| {
        relations.removeEntity(entity);
    }

    // Collect all containers from the query to iterate them multiple times without reset()
    var containers = try std.ArrayList(struct { entity: zevy_ecs.Entity, container: layout.UIContainer }).initCapacity(commands.allocator(), 128);
    defer containers.deinit(allocator);

    while (container_query.next()) |p| {
        try containers.append(allocator, .{ .entity = p.entity, .container = p.container.* });
    }
    container_query.deinit();

    // Process added UINode components
    for (added_nodes.iter()) |entry| {
        if (entry.comp.parent_id) |p_id| {
            var found_parent: ?zevy_ecs.Entity = null;
            for (containers.items) |p| {
                if (std.mem.eql(u8, p.container.id, p_id)) {
                    found_parent = p.entity;
                    break;
                }
            }
            if (found_parent) |parent| {
                if (!try relations.has(commands.manager(), entry.entity, parent, zevy_ecs.relations.kinds.Child)) {
                    try relations.add(commands.manager(), entry.entity, parent, zevy_ecs.relations.kinds.Child);
                }
            } else {
                std.log.warn("UI hierarchy system: parent container '{s}' not found for entity", .{p_id});
            }
        }
    }

    // Process added UIContainer components (if they have parent_id set)
    for (added_containers.iter()) |entry| {
        if (entry.comp.parent_id) |p_id| {
            var found_parent: ?zevy_ecs.Entity = null;
            for (containers.items) |p| {
                if (std.mem.eql(u8, p.container.id, p_id)) {
                    if (!p.entity.eql(entry.entity)) {
                        found_parent = p.entity;
                        break;
                    }
                }
            }
            if (found_parent) |parent| {
                if (!try relations.has(commands.manager(), entry.entity, parent, zevy_ecs.relations.kinds.Child)) {
                    try relations.add(commands.manager(), entry.entity, parent, zevy_ecs.relations.kinds.Child);
                }
            } else {
                std.log.warn("UI hierarchy system: parent container '{s}' not found for container ID '{s}'", .{ p_id, entry.comp.id });
            }
        }
    }
}
