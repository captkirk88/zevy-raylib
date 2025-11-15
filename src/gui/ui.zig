const std = @import("std");

// Export all UI components
pub const components = @import("ui_components.zig");
pub const layout = @import("ui_layout.zig");
pub const renderer = @import("ui_renderer.zig");
pub const systems = @import("ui_systems.zig");

// Re-export commonly used types for convenience
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

pub const FlexDirection = layout.FlexDirection;
pub const FlexAlign = layout.FlexAlign;
pub const FlexItemAlign = layout.FlexItemAlign;
pub const FlexWrap = layout.FlexWrap;

// Re-export render functions
pub const renderText = renderer.renderText;
pub const renderButton = renderer.renderButton;
pub const renderToggle = renderer.renderToggle;
pub const renderSlider = renderer.renderSlider;
pub const renderProgressBar = renderer.renderProgressBar;
pub const renderTextBox = renderer.renderTextBox;
pub const renderPanel = renderer.renderPanel;
pub const renderScrollPanel = renderer.renderScrollPanel;
pub const renderDropdown = renderer.renderDropdown;
pub const renderImage = renderer.renderImage;
pub const renderSpinner = renderer.renderSpinner;
pub const renderColorPicker = renderer.renderColorPicker;
pub const renderListView = renderer.renderListView;
pub const renderMessageBox = renderer.renderMessageBox;
pub const renderTabBar = renderer.renderTabBar;

// Re-export systems
pub const uiRenderSystem = systems.uiRenderSystem;
pub const uiInputSystem = systems.uiInputSystem;

test {
    std.testing.refAllDeclsRecursive(@This());
}
