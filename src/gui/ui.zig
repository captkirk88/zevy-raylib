const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const plugins = @import("plugins");

const _assets = @import("../io/assets.zig");
const _input = @import("../input/input.zig");

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

pub fn UIPlugin(comptime ParamRegistry: type) type {
    return struct {
        pub fn build(self: *@This(), e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) !void {
            _ = self;
            _ = plugin_manager;

            const input_manager = e.getResource(_input.InputManager) orelse
                return error.MissingInputManager;

            input.setupUIInputBindings(input_manager, e.allocator) catch |err| {
                std.log.err("Failed to setup UI input bindings: {}", .{err});
                return err;
            };

            const assets = e.getResource(_assets.Assets) orelse
                return error.MissingAssetsResource;
            _ = assets;

            const scheduler = e.getResource(
                zevy_ecs.Scheduler,
            ) orelse try e.addResource(
                zevy_ecs.Scheduler,
                try zevy_ecs.Scheduler.init(e.allocator),
            );

            try scheduler.registerEvent(e, input.UIClickEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIHoverEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIValueChangedEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIToggleEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIFocusEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UISelectionChangedEvent, ParamRegistry);

            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Startup),
                systems.startupUiSystem,
                ParamRegistry,
            );

            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                input.sliderInteractionSystem,
                ParamRegistry,
            );

            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                input.toggleInteractionSystem,
                ParamRegistry,
            );

            // Layout systems
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                systems.anchorLayoutSystem,
                ParamRegistry,
            );
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                systems.flexLayoutSystem,
                ParamRegistry,
            );
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                systems.gridLayoutSystem,
                ParamRegistry,
            );
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                systems.dockLayoutSystem,
                ParamRegistry,
            );

            // Input handling
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.Update),
                input.uiInteractionDetectionSystem,
                ParamRegistry,
            );

            // Rendering system
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.PostDraw),
                systems.uiRenderSystem,
                ParamRegistry,
            );

            // Input key rendering system
            scheduler.addSystem(
                e,
                zevy_ecs.Stage(zevy_ecs.Stages.PostDraw),
                systems.uiInputKeyRenderSystem,
                ParamRegistry,
            );
        }
    };
}

test {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDecls(@import("ui_tests.zig"));
    std.testing.refAllDecls(@import("ui_render_tests.zig"));
}
