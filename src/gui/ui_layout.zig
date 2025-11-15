const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

// =============================================================================
// UI LAYOUT COMPONENTS
// =============================================================================

/// Flex layout direction
pub const FlexDirection = enum {
    row,
    column,
    row_reverse,
    column_reverse,
};

/// Flex alignment options
pub const FlexAlign = enum {
    start,
    center,
    end,
    space_between,
    space_around,
    space_evenly,
};

/// Flex item alignment
pub const FlexItemAlign = enum {
    auto,
    start,
    center,
    end,
    stretch,
};

/// Flex wrap mode
pub const FlexWrap = enum {
    no_wrap,
    wrap,
    wrap_reverse,
};

/// Flexible box layout component
pub const FlexLayout = struct {
    direction: FlexDirection = .row,
    justify_content: FlexAlign = .start,
    align_items: FlexItemAlign = .start,
    align_content: FlexAlign = .start,
    wrap: FlexWrap = .no_wrap,
    gap: f32 = 0.0,
    padding: Padding = .{},

    pub fn init() FlexLayout {
        return .{};
    }

    pub fn row() FlexLayout {
        return .{ .direction = .row };
    }

    pub fn column() FlexLayout {
        return .{ .direction = .column };
    }

    pub fn withGap(self: FlexLayout, gap: f32) FlexLayout {
        var result = self;
        result.gap = gap;
        return result;
    }

    pub fn withPadding(self: FlexLayout, padding: Padding) FlexLayout {
        var result = self;
        result.padding = padding;
        return result;
    }

    pub fn withJustify(self: FlexLayout, justify: FlexAlign) FlexLayout {
        var result = self;
        result.justify_content = justify;
        return result;
    }

    pub fn withAlign(self: FlexLayout, alignment: FlexItemAlign) FlexLayout {
        var result = self;
        result.align_items = alignment;
        return result;
    }
};

/// Grid layout component
pub const GridLayout = struct {
    columns: u32,
    rows: u32,
    column_gap: f32 = 0.0,
    row_gap: f32 = 0.0,
    padding: Padding = .{},
    auto_flow: GridAutoFlow = .row,

    pub const GridAutoFlow = enum {
        row,
        column,
        dense,
    };

    pub fn init(columns: u32, rows: u32) GridLayout {
        return .{ .columns = columns, .rows = rows };
    }

    /// Set the gap between columns and rows.
    /// Gap is the spacing between grid cells.
    pub fn withGap(self: GridLayout, column_gap: f32, row_gap: f32) GridLayout {
        var result = self;
        result.column_gap = column_gap;
        result.row_gap = row_gap;
        return result;
    }

    /// Set padding around the grid container.
    /// Padding is the space between the container edges and the grid cells.
    pub fn withPadding(self: GridLayout, padding: Padding) GridLayout {
        var result = self;
        result.padding = padding;
        return result;
    }
};

/// Stack layout (overlapping elements)
pub const StackLayout = struct {
    alignment: StackAlign = .center,
    padding: Padding = .{},

    pub const StackAlign = enum {
        top_left,
        top_center,
        top_right,
        center_left,
        center,
        center_right,
        bottom_left,
        bottom_center,
        bottom_right,
    };

    pub fn init(alignment: StackAlign) StackLayout {
        return .{ .alignment = alignment };
    }

    pub fn withPadding(self: StackLayout, padding: Padding) StackLayout {
        var result = self;
        result.padding = padding;
        return result;
    }
};

/// Absolute positioning layout
pub const AbsoluteLayout = struct {
    anchor: Anchor = .top_left,

    pub const Anchor = enum {
        top_left,
        top_center,
        top_right,
        center_left,
        center,
        center_right,
        bottom_left,
        bottom_center,
        bottom_right,
    };

    pub fn init(anchor: Anchor) AbsoluteLayout {
        return .{ .anchor = anchor };
    }
};

/// Anchor / absolute positioning for a child relative to its container.
/// The child's `UIRect` width/height are taken as-is; only x/y are computed
/// from the container rect and the chosen anchor, with optional offsets.
pub const AnchorLayout = struct {
    anchor: AbsoluteLayout.Anchor = .top_left,
    offset_x: f32 = 0.0,
    offset_y: f32 = 0.0,

    pub fn init(anchor: AbsoluteLayout.Anchor) AnchorLayout {
        return .{ .anchor = anchor };
    }

    pub fn withOffset(self: AnchorLayout, dx: f32, dy: f32) AnchorLayout {
        var result = self;
        result.offset_x = dx;
        result.offset_y = dy;
        return result;
    }
};

/// Dock layout positions children along the edges of a container in order.
/// Docked children consume space from the corresponding side; any child with
/// `.fill` true will fill the remaining space.
pub const DockLayout = struct {
    pub const DockSide = enum {
        left,
        right,
        top,
        bottom,
        fill,
    };

    side: DockSide = .fill,

    pub fn init(side: DockSide) DockLayout {
        return .{ .side = side };
    }
};

/// Padding specification
pub const Padding = struct {
    top: f32 = 0.0,
    right: f32 = 0.0,
    bottom: f32 = 0.0,
    left: f32 = 0.0,

    pub fn init(top: f32, right: f32, bottom: f32, left: f32) Padding {
        return .{ .top = top, .right = right, .bottom = bottom, .left = left };
    }

    pub fn uniform(value: f32) Padding {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(vert: f32, horiz: f32) Padding {
        return .{ .top = vert, .right = horiz, .bottom = vert, .left = horiz };
    }

    pub fn horizontal(value: f32) Padding {
        return .{ .left = value, .right = value };
    }

    pub fn vertical(value: f32) Padding {
        return .{ .top = value, .bottom = value };
    }

    pub fn getTotalHorizontal(self: Padding) f32 {
        return self.left + self.right;
    }

    pub fn getTotalVertical(self: Padding) f32 {
        return self.top + self.bottom;
    }
};

/// Margin specification (external spacing)
pub const Margin = struct {
    top: f32 = 0.0,
    right: f32 = 0.0,
    bottom: f32 = 0.0,
    left: f32 = 0.0,

    pub fn init(top: f32, right: f32, bottom: f32, left: f32) Margin {
        return .{ .top = top, .right = right, .bottom = bottom, .left = left };
    }

    pub fn uniform(value: f32) Margin {
        return .{ .top = value, .right = value, .bottom = value, .left = value };
    }

    pub fn symmetric(vert: f32, horiz: f32) Margin {
        return .{ .top = vert, .right = horiz, .bottom = vert, .left = horiz };
    }
};

/// Size constraints for UI elements
pub const SizeConstraints = struct {
    min_width: ?f32 = null,
    max_width: ?f32 = null,
    min_height: ?f32 = null,
    max_height: ?f32 = null,

    pub fn init() SizeConstraints {
        return .{};
    }

    pub fn withMinWidth(self: SizeConstraints, width: f32) SizeConstraints {
        var result = self;
        result.min_width = width;
        return result;
    }

    pub fn withMaxWidth(self: SizeConstraints, width: f32) SizeConstraints {
        var result = self;
        result.max_width = width;
        return result;
    }

    pub fn withMinHeight(self: SizeConstraints, height: f32) SizeConstraints {
        var result = self;
        result.min_height = height;
        return result;
    }

    pub fn withMaxHeight(self: SizeConstraints, height: f32) SizeConstraints {
        var result = self;
        result.max_height = height;
        return result;
    }

    pub fn clampWidth(self: SizeConstraints, width: f32) f32 {
        var result = width;
        if (self.min_width) |min| {
            result = @max(result, min);
        }
        if (self.max_width) |max| {
            result = @min(result, max);
        }
        return result;
    }

    pub fn clampHeight(self: SizeConstraints, height: f32) f32 {
        var result = height;
        if (self.min_height) |min| {
            result = @max(result, min);
        }
        if (self.max_height) |max| {
            result = @min(result, max);
        }
        return result;
    }
};

/// Flex item properties for children in flex layouts
pub const FlexItem = struct {
    grow: f32 = 0.0,
    shrink: f32 = 1.0,
    basis: ?f32 = null,
    align_self: FlexItemAlign = .auto,
    order: i32 = 0,
    constraints: SizeConstraints = SizeConstraints.init(),

    pub fn init() FlexItem {
        return .{};
    }

    /// Set the flex grow factor for this flex item.
    /// This determines how much the item will grow relative to other flex items
    /// when there is extra space in the container.
    pub fn withGrow(self: FlexItem, grow: f32) FlexItem {
        var result = self;
        result.grow = grow;
        return result;
    }

    /// Set the flex shrink factor for this flex item.
    /// This determines how much the item will shrink relative to other flex items
    /// when there is not enough space in the container.
    pub fn withShrink(self: FlexItem, shrink: f32) FlexItem {
        var result = self;
        result.shrink = shrink;
        return result;
    }

    /// Set the flex basis size for this flex item.
    /// The flex basis is the initial main size of the flex item before any available space
    /// is distributed according to the flex factors. If set to null (default), the item uses its content size.
    pub fn withBasis(self: FlexItem, basis: f32) FlexItem {
        var result = self;
        result.basis = basis;
        return result;
    }

    /// Set the alignment for this flex item, overriding the container's align_items setting.
    pub fn withAlignSelf(self: FlexItem, alignment: FlexItemAlign) FlexItem {
        var result = self;
        result.align_self = alignment;
        return result;
    }

    /// Set the order of this flex item.
    /// Items with lower order values are laid out first.
    pub fn withOrder(self: FlexItem, order: i32) FlexItem {
        var result = self;
        result.order = order;
        return result;
    }

    /// Set size constraints for this flex item.
    pub fn withConstraints(self: FlexItem, constraints: SizeConstraints) FlexItem {
        var result = self;
        result.constraints = constraints;
        return result;
    }
};

/// Grid item properties for children in grid layouts
pub const GridItem = struct {
    column_start: ?u32 = null,
    column_end: ?u32 = null,
    row_start: ?u32 = null,
    row_end: ?u32 = null,
    column_span: u32 = 1,
    row_span: u32 = 1,

    pub fn init() GridItem {
        return .{};
    }

    pub fn withColumn(self: GridItem, start: u32, end: u32) GridItem {
        var result = self;
        result.column_start = start;
        result.column_end = end;
        return result;
    }

    pub fn withRow(self: GridItem, start: u32, end: u32) GridItem {
        var result = self;
        result.row_start = start;
        result.row_end = end;
        return result;
    }

    pub fn withSpan(self: GridItem, column_span: u32, row_span: u32) GridItem {
        var result = self;
        result.column_span = column_span;
        result.row_span = row_span;
        return result;
    }
};

/// Anchor positioning for absolute layouts
pub const AnchorPosition = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    anchor: AbsoluteLayout.Anchor = .top_left,

    pub fn init(x: f32, y: f32, anchor: AbsoluteLayout.Anchor) AnchorPosition {
        return .{ .x = x, .y = y, .anchor = anchor };
    }
};

/// Container component for grouping child entities
pub const UIContainer = struct {
    /// Optional identifier for this container
    id: []const u8 = "",
    /// Whether this container clips children to its bounds
    clip_children: bool = false,

    pub fn init(id: []const u8) UIContainer {
        return .{ .id = id };
    }

    pub fn withClipping(self: UIContainer, clip: bool) UIContainer {
        var result = self;
        result.clip_children = clip;
        return result;
    }
};
