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
        ui.components.UIRect.init(50, 50, 200, 30),
        ui.components.UIText.init("Hello World!").withFontSize(20),
        ui.components.UIVisible.init(true),
    });

    // Example 2: Button with callback tracking
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 100, 200, 40),
        ui.components.UIButton.init("Click Me!"),
        ui.components.UIVisible.init(true),
    });

    // Example 3: Slider for volume control
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 160, 200, 20),
        ui.components.UISlider.init(0.5, 0.0, 1.0),
        ui.components.UIVisible.init(true),
    });

    // Example 4: Progress bar
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 200, 200, 30),
        ui.components.UIProgressBar.init(0.75),
        ui.components.UIVisible.init(true),
    });

    // Example 5: Toggle/Checkbox
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 250, 200, 30),
        ui.components.UIToggle.init("Enable Sound", true),
        ui.components.UIVisible.init(true),
    });

    // Example 6: Text input box
    var text_buffer: [256]u8 = undefined;
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 300, 200, 30),
        ui.components.UITextBox.init(&text_buffer),
        ui.components.UIVisible.init(true),
    });

    // Example 7: Panel with nested UI
    _ = ecs.create(.{
        ui.components.UIRect.init(300, 50, 300, 400),
        ui.components.UIPanel.init("Settings Panel").withPadding(10),
        ui.components.UIVisible.init(true),
    });

    // Example 8: Dropdown menu
    const dropdown_items = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    _ = ecs.create(.{
        ui.components.UIRect.init(320, 100, 260, 30),
        ui.components.UIDropdown.init(&dropdown_items),
        ui.components.UIVisible.init(true),
    });

    // Example 9: Spinner for numeric input
    _ = ecs.create(.{
        ui.components.UIRect.init(320, 150, 260, 30),
        ui.components.UISpinner.init(50, 0, 100),
        ui.components.UIVisible.init(true),
    });

    // Example 10: Tab bar
    const tabs = [_][]const u8{ "General", "Graphics", "Audio", "Controls" };
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 400, 550, 30),
        ui.components.UITabBar.init(&tabs),
        ui.components.UIVisible.init(true),
    });
}

/// Example: Using FlexLayout for responsive UI
pub fn createFlexLayoutExample(allocator: std.mem.Allocator, ecs: *zevy_ecs.Manager) !void {
    _ = allocator;

    // Create a container with flex layout
    _ = ecs.create(.{
        ui.components.UIRect.init(50, 50, 700, 500),
        ui.layout.FlexLayout.column()
            .withGap(10)
            .withPadding(ui.layout.Padding.uniform(20))
            .withJustify(.space_between),
        ui.layout.UIContainer.init("main-container"),
        ui.components.UIPanel.init("Flex Container"),
        ui.components.UIVisible.init(true),
    });

    // Child items would be positioned by the flex layout system
    // In a full implementation, you would query for children and calculate their positions
}

/// Example: Creating a health bar using progress bar
pub fn createHealthBar(ecs: *zevy_ecs.Manager, x: f32, y: f32, width: f32, height: f32) !void {
    _ = ecs.create(.{
        ui.components.UIRect.init(x, y, width, height),
        ui.components.UIProgressBar.init(1.0), // Full health
        ui.components.UIVisible.init(true),
        ui.components.UILayer.init(10), // Higher layer for HUD
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
        ui.components.UIRect.init(0, 0, 800, 600),
        ui.components.UIPanel.init("").withColor(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 128 }),
        ui.components.UIVisible.init(true),
        ui.components.UILayer.init(100),
    });

    // Dialog box
    _ = ecs.create(.{
        ui.components.UIRect.init(250, 200, 300, 200),
        ui.components.UIMessageBox.init(title, message, "OK;Cancel"),
        ui.components.UIVisible.init(true),
        ui.components.UILayer.init(101),
    });
}

/// Example: System to update a progress bar from health component
/// Note: Replace HealthComponentType with your actual Health component type
pub fn updateHealthBarSystem(
    comptime HealthComponentType: type,
) fn (health_query: zevy_ecs.Query(struct {
    health: HealthComponentType,
    progress: ui.components.UIProgressBar,
})) void {
    return struct {
        pub fn system(health_query: zevy_ecs.Query(struct {
            health: HealthComponentType,
            progress: ui.UIProgressBar,
        }, .{})) void {
            while (health_query.next()) |item| {
                const health: *HealthComponentType = item.health;
                var progress: *ui.components.UIProgressBar = item.progress;
                const health_percent = health.percentage();
                progress.setValue(health_percent);
            }
        }
    }.system;
}

/// Example: System to handle button press events
/// This example shows the old way of polling button state directly
/// For new code, prefer using the UI input events system (see handleMainMenuButtons)
pub fn buttonEventSystem(
    button_query: zevy_ecs.Query(struct {
        button: *ui.components.UIButton,
        // You could add a custom component here for callbacks
    }, .{}),
) void {
    while (button_query.next()) |item| {
        var button: *ui.components.UIButton = item.button;
        if (button.isPressed()) {
            // Handle button press
            std.debug.print("Button was pressed!\n", .{});

            // Reset pressed state for next frame
            button.pressed = false;
        }
    }
}

// =============================================================================
// NEW EVENT-BASED UI INTERACTION EXAMPLES
// =============================================================================

/// Example tag component for identifying the play button
pub const PlayButton = struct {};

/// Example tag component for identifying the quit button
pub const QuitButton = struct {};

/// Example tag component for identifying the settings button
pub const SettingsButton = struct {};

/// Example: Handle main menu button clicks using the event-based system
/// This demonstrates the recommended approach using UI input events
pub fn handleMainMenuButtons(
    manager: *zevy_ecs.Manager,
    click_reader: zevy_ecs.EventReader(ui.input.UIClickEvent),

    // Query for buttons with their tag components
    play_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        tag: PlayButton,
    }, .{}),
    quit_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        tag: QuitButton,
    }, .{}),
    settings_query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        tag: SettingsButton,
    }, .{}),
) void {
    _ = manager;
    while (click_reader.read()) |event| {
        // Check if it's the play button
        while (play_query.next()) |item| {
            if (ui.input.isEntityClicked(&event.data, item.entity)) {
                std.debug.print("Play button clicked at ({d}, {d})!\n", .{
                    event.data.position.x,
                    event.data.position.y,
                });
                // Call your game start logic here
                // startGame(manager);
                event.handled = true;
                break;
            }
        }

        // Check if it's the quit button
        while (quit_query.next()) |item| {
            if (ui.input.isEntityClicked(&event.data, item.entity)) {
                std.debug.print("Quit button clicked!\n", .{});
                // Call your exit logic here
                // exitGame(manager);
                event.handled = true;
                break;
            }
        }

        // Check if it's the settings button
        while (settings_query.next()) |item| {
            if (ui.input.isEntityClicked(&event.data, item.entity)) {
                std.debug.print("Settings button clicked!\n", .{});
                // Call your settings menu logic here
                // openSettings(manager);
                event.handled = true;
                break;
            }
        }
    }
}

/// Example: Handle slider value changes
pub fn handleVolumeSlider(
    _: *zevy_ecs.Manager,
    value_reader: zevy_ecs.EventReader(ui.input.UIValueChangedEvent),
    // Use a tag to identify the volume slider
    query: zevy_ecs.Query(struct {
        entity: zevy_ecs.Entity,
        tag: VolumeSliderTag,
    }, .{}),
) void {
    while (value_reader.read()) |event| {
        while (query.next()) |item| {
            if (event.data.entity.eql(item.entity)) {
                std.debug.print("Volume changed from {d:.2} to {d:.2}\n", .{
                    event.data.old_value,
                    event.data.new_value,
                });
                // Update your audio system volume here
                event.handled = true;
                break;
            }
        }
    }
}

/// Example tag for volume slider
pub const VolumeSliderTag = struct {};

/// Example: Create a main menu with event-based interaction
pub fn createMainMenuWithEvents(allocator: std.mem.Allocator, ecs: *zevy_ecs.Manager) !void {
    _ = allocator;

    // Create play button with tag
    _ = ecs.create(.{
        ui.components.UIRect.init(300, 200, 200, 50),
        ui.components.UIButton.init("Play"),
        ui.components.UIVisible.init(true),
        PlayButton{},
    });

    // Create settings button with tag
    _ = ecs.create(.{
        ui.components.UIRect.init(300, 270, 200, 50),
        ui.components.UIButton.init("Settings"),
        ui.components.UIVisible.init(true),
        SettingsButton{},
    });

    // Create quit button with tag
    _ = ecs.create(.{
        ui.components.UIRect.init(300, 340, 200, 50),
        ui.components.UIButton.init("Quit"),
        ui.components.UIVisible.init(true),
        QuitButton{},
    });

    // Create volume slider
    _ = ecs.create(.{
        ui.components.UIRect.init(300, 420, 200, 30),
        ui.components.UISlider.init(0.5, 0.0, 1.0),
        ui.components.UIVisible.init(true),
        VolumeSliderTag{},
    });
}

/// Example: Setup function to register UI input events and systems
/// Call this during application startup
pub fn setupUIInputExample(
    manager: *zevy_ecs.Manager,
    scheduler: *zevy_ecs.Scheduler,
    input_manager: *@import("../input/input.zig").InputManager,
    allocator: std.mem.Allocator,
) !void {
    // Setup input bindings for UI
    try ui.input.setupUIInputBindings(input_manager, allocator);

    // Register UI events
    try scheduler.registerEvent(manager, ui.input.UIClickEvent);
    try scheduler.registerEvent(manager, ui.input.UIHoverEvent);
    try scheduler.registerEvent(manager, ui.input.UIValueChangedEvent);
    try scheduler.registerEvent(manager, ui.input.UIToggleEvent);
    try scheduler.registerEvent(manager, ui.input.UIFocusEvent);
    try scheduler.registerEvent(manager, ui.input.UISelectionChangedEvent);

    // Add UI input detection systems to the Update stage
    scheduler.addSystem(
        manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        ui.input.uiInteractionDetectionSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        ui.input.sliderInteractionSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        ui.input.toggleInteractionSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    // Add game logic systems that consume UI events
    scheduler.addSystem(
        manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        handleMainMenuButtons,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        handleVolumeSlider,
        zevy_ecs.DefaultParamRegistry,
    );
}

test "UI component creation" {
    const testing = std.testing;

    // Test UIRect
    const rect = ui.components.UIRect.init(10, 20, 100, 50);
    try testing.expectEqual(@as(f32, 10), rect.x);
    try testing.expectEqual(@as(f32, 20), rect.y);
    try testing.expectEqual(@as(f32, 100), rect.width);
    try testing.expectEqual(@as(f32, 50), rect.height);

    // Test UIButton
    const button = ui.components.UIButton.init("Test Button");
    try testing.expect(button.enabled);
    try testing.expect(!button.pressed);

    // Test UISlider
    const slider = ui.components.UISlider.init(0.5, 0.0, 1.0);
    try testing.expectEqual(@as(f32, 0.5), slider.value);
    try testing.expectEqual(@as(f32, 0.5), slider.getNormalized());

    // Test FlexLayout
    const flex = ui.layout.FlexLayout.column().withGap(10);
    try testing.expectEqual(ui.FlexDirection.column, flex.direction);
    try testing.expectEqual(@as(f32, 10), flex.gap);
}
