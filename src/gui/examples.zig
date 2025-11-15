const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const ui = @import("ui.zig");
const zevy_ecs = @import("zevy_ecs");

/// Example: Creating a simple UI with text, button, and slider
///
/// This example demonstrates how to create UI entities using the ECS component system.
/// Each UI element is an entity with various component combinations.
///
/// Usage with zevy_ecs:
/// ```zig
/// const entity = ecs.spawn();
/// try ecs.addComponents(entity, .{
///     ui.UIRect.init(100, 100, 200, 30),
///     ui.UIButton.init("Click Me!"),
/// });
/// ```
pub fn createExampleUI(allocator: std.mem.Allocator, ecs: *zevy_ecs.Manager) !void {
    _ = allocator;

    // Example 1: Simple text label
    _ = ecs.create(.{
        ui.UIRect.init(50, 50, 200, 30),
        ui.UIText.init("Hello World!").withFontSize(20),
        ui.UIVisible.init(true),
    });

    // Example 2: Button with callback tracking
    _ = ecs.create(.{
        ui.UIRect.init(50, 100, 200, 40),
        ui.UIButton.init("Click Me!"),
        ui.UIVisible.init(true),
    });

    // Example 3: Slider for volume control
    _ = ecs.create(.{
        ui.UIRect.init(50, 160, 200, 20),
        ui.UISlider.init(0.5, 0.0, 1.0),
        ui.UIVisible.init(true),
    });

    // Example 4: Progress bar
    _ = ecs.create(.{
        ui.UIRect.init(50, 200, 200, 30),
        ui.UIProgressBar.init(0.75),
        ui.UIVisible.init(true),
    });

    // Example 5: Toggle/Checkbox
    _ = ecs.create(.{
        ui.UIRect.init(50, 250, 200, 30),
        ui.UIToggle.init("Enable Sound", true),
        ui.UIVisible.init(true),
    });

    // Example 6: Text input box
    var text_buffer: [256]u8 = undefined;
    _ = ecs.create(.{
        ui.UIRect.init(50, 300, 200, 30),
        ui.UITextBox.init(&text_buffer),
        ui.UIVisible.init(true),
    });

    // Example 7: Panel with nested UI
    _ = ecs.create(.{
        ui.UIRect.init(300, 50, 300, 400),
        ui.UIPanel.init("Settings Panel").withPadding(10),
        ui.UIVisible.init(true),
    });

    // Example 8: Dropdown menu
    const dropdown_items = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    _ = ecs.create(.{
        ui.UIRect.init(320, 100, 260, 30),
        ui.UIDropdown.init(&dropdown_items),
        ui.UIVisible.init(true),
    });

    // Example 9: Spinner for numeric input
    _ = ecs.create(.{
        ui.UIRect.init(320, 150, 260, 30),
        ui.UISpinner.init(50, 0, 100),
        ui.UIVisible.init(true),
    });

    // Example 10: Tab bar
    const tabs = [_][]const u8{ "General", "Graphics", "Audio", "Controls" };
    _ = ecs.create(.{
        ui.UIRect.init(50, 400, 550, 30),
        ui.UITabBar.init(&tabs),
        ui.UIVisible.init(true),
    });
}

/// Example: Using FlexLayout for responsive UI
pub fn createFlexLayoutExample(allocator: std.mem.Allocator, ecs: *zevy_ecs.Manager) !void {
    _ = allocator;

    // Create a container with flex layout
    _ = ecs.create(.{
        ui.UIRect.init(50, 50, 700, 500),
        ui.FlexLayout.column()
            .withGap(10)
            .withPadding(ui.Padding.uniform(20))
            .withJustify(.space_between),
        ui.UIContainer.init("main-container"),
        ui.UIPanel.init("Flex Container"),
        ui.UIVisible.init(true),
    });

    // Child items would be positioned by the flex layout system
    // In a full implementation, you would query for children and calculate their positions
}

/// Example: Creating a health bar using progress bar
pub fn createHealthBar(ecs: *zevy_ecs.Manager, x: f32, y: f32, width: f32, height: f32) !void {
    _ = ecs.create(.{
        ui.UIRect.init(x, y, width, height),
        ui.UIProgressBar.init(1.0), // Full health
        ui.UIVisible.init(true),
        ui.UILayer.init(10), // Higher layer for HUD
    });
}

/// Example: Creating a modal dialog
pub fn createDialog(
    allocator: std.mem.Allocator,
    ecs: *zevy_ecs.Manager,
    title: []const u8,
    message: []const u8,
) !void {
    _ = allocator;

    // Semi-transparent background overlay
    _ = ecs.create(.{
        ui.UIRect.init(0, 0, 800, 600),
        ui.UIPanel.init("").withColor(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 128 }),
        ui.UIVisible.init(true),
        ui.UILayer.init(100),
    });

    // Dialog box
    _ = ecs.create(.{
        ui.UIRect.init(250, 200, 300, 200),
        ui.UIMessageBox.init(title, message, "OK;Cancel"),
        ui.UIVisible.init(true),
        ui.UILayer.init(101),
    });
}

/// Example: System to update a progress bar from health component
/// Note: Replace HealthComponentType with your actual Health component type
pub fn updateHealthBarSystem(
    comptime HealthComponentType: type,
) fn (health_query: zevy_ecs.Query(struct {
    health: HealthComponentType,
    progress: ui.UIProgressBar,
})) void {
    return struct {
        pub fn system(health_query: zevy_ecs.Query(struct {
            health: HealthComponentType,
            progress: ui.UIProgressBar,
        }, .{})) void {
            if (health_query) |query| {
                var iter = query;
                while (iter.next()) |item| {
                    const health_percent = item.health.percentage();
                    item.progress.setValue(health_percent);
                }
            }
        }
    }.system;
}

/// Example: System to handle button press events
pub fn buttonEventSystem(
    button_query: zevy_ecs.Query(struct {
        button: *ui.UIButton,
        // You could add a custom component here for callbacks
    }, .{}),
) void {
    if (button_query) |query| {
        var iter = query;
        while (iter.next()) |item| {
            if (item.button.isPressed()) {
                // Handle button press
                std.debug.print("Button was pressed!\n", .{});

                // Reset pressed state for next frame
                item.button.pressed = false;
            }
        }
    }
}

test "UI component creation" {
    const testing = std.testing;

    // Test UIRect
    const rect = ui.UIRect.init(10, 20, 100, 50);
    try testing.expectEqual(@as(f32, 10), rect.x);
    try testing.expectEqual(@as(f32, 20), rect.y);
    try testing.expectEqual(@as(f32, 100), rect.width);
    try testing.expectEqual(@as(f32, 50), rect.height);

    // Test UIButton
    const button = ui.UIButton.init("Test Button");
    try testing.expect(button.enabled);
    try testing.expect(!button.pressed);

    // Test UISlider
    const slider = ui.UISlider.init(0.5, 0.0, 1.0);
    try testing.expectEqual(@as(f32, 0.5), slider.value);
    try testing.expectEqual(@as(f32, 0.5), slider.getNormalized());

    // Test FlexLayout
    const flex = ui.FlexLayout.column().withGap(10);
    try testing.expectEqual(ui.FlexDirection.column, flex.direction);
    try testing.expectEqual(@as(f32, 10), flex.gap);
}
