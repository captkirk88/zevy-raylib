const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = zevy_ecs.plugins;

const _assets = @import("../io/assets.zig");
const _input = @import("../input/root.zig");

/// UI Components
pub const components = @import("ui_components.zig");
/// Layout management
pub const layout = @import("ui_layout.zig");
/// Funcs for rendering
pub const renderer = @import("ui_renderer.zig");
/// Essential systems
pub const systems = @import("ui_systems.zig");
/// Input handling
pub const input = @import("ui_input.zig");

pub const UIPlugin = struct {
    const Name: []const u8 = "UIPlugin";
    const ui_render_stage = zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostDraw)
        .sub(1)
        .withOp(.sync);

    pub fn build(self: *@This(), app: *zevy_ecs.app.App, plugin_manager: *plugins.PluginManager) anyerror!void {
        _ = self;
        _ = plugin_manager;

        const input_manager_ref = app.ecs().getResource(_input.InputManager) orelse
            return error.MissingInputManager;
        defer input_manager_ref.deinit();

        var input_manager_guard = input_manager_ref.lockWrite();
        defer input_manager_guard.deinit();

        input.setupUIInputBindings(input_manager_guard.get(), app.allocator()) catch |err| {
            std.log.err("Failed to setup UI input bindings: {}", .{err});
            return err;
        };

        app
            .addEvent(input.UIClickEvent)
            .addEvent(input.UIHoverEvent)
            .addEvent(input.UIValueChangedEvent(components.UISlider))
            .addEvent(input.UIValueChangedEvent(components.UISpinner))
            .addEvent(input.UIToggleEvent)
            .addEvent(input.UIFocusEvent)
            .addEvent(input.UISelectionChangedEvent)
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Startup),
                systems.startupUiSystem,
            )

            // These systems share UI state and must stay ordered even when
            // Update dispatch becomes async outside Debug builds.
            .addSystem(
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                zevy_ecs.chain(.{
                    input.sliderInteractionSystem,
                    input.toggleInteractionSystem,
                    systems.anchorLayoutSystem,
                    systems.flexLayoutSystem,
                    systems.gridLayoutSystem,
                    systems.dockLayoutSystem,
                    input.uiInteractionDetectionSystem,
                }),
            )

            // Rendering system
            .addSystem(
                ui_render_stage,
                zevy_ecs.chain(.{ systems.uiRenderSystem, systems.uiInputKeyRenderSystem }),
            ).done();
    }

    pub fn deinit(self: *@This(), _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
        _ = self;
        _ = e;
    }
};

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(@import("ui_tests.zig"));
    std.testing.refAllDecls(@import("ui_render_tests.zig"));
}
