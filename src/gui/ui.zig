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
        const Name: []const u8 = "UIPlugin";

        pub fn build(self: *@This(), e: *zevy_ecs.Manager, plugin_manager: *plugins.PluginManager) anyerror!void {
            _ = self;
            _ = plugin_manager;

            const input_manager_ref = e.getResource(_input.InputManager) orelse
                return error.MissingInputManager;
            defer input_manager_ref.deinit();

            var input_manager_guard = input_manager_ref.lockWrite();
            defer input_manager_guard.deinit();

            input.setupUIInputBindings(input_manager_guard.get(), e.allocator) catch |err| {
                std.log.err("Failed to setup UI input bindings: {}", .{err});
                return err;
            };

            const assets_ref = e.getResource(_assets.Assets) orelse
                return error.MissingAssetsResource;
            defer assets_ref.deinit();

            const scheduler_ref = e.getResource(
                zevy_ecs.schedule.Scheduler,
            ) orelse try e.addResource(
                zevy_ecs.schedule.Scheduler,
                try zevy_ecs.schedule.Scheduler.init(e.allocator),
            );
            defer scheduler_ref.deinit();
            var scheduler_guard = scheduler_ref.lockWrite();
            defer scheduler_guard.deinit();
            const scheduler = scheduler_guard.get();

            try scheduler.registerEvent(e, input.UIClickEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIHoverEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIValueChangedEvent(components.UISlider), ParamRegistry);
            try scheduler.registerEvent(e, input.UIValueChangedEvent(components.UISpinner), ParamRegistry);
            try scheduler.registerEvent(e, input.UIToggleEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UIFocusEvent, ParamRegistry);
            try scheduler.registerEvent(e, input.UISelectionChangedEvent, ParamRegistry);

            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PreStartup),
                systems.startupUiSystem,
                ParamRegistry,
            );

            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                input.sliderInteractionSystem,
                ParamRegistry,
            );

            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                input.toggleInteractionSystem,
                ParamRegistry,
            );

            // Layout systems
            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                systems.anchorLayoutSystem,
                ParamRegistry,
            );
            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                systems.flexLayoutSystem,
                ParamRegistry,
            );
            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                systems.gridLayoutSystem,
                ParamRegistry,
            );
            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                systems.dockLayoutSystem,
                ParamRegistry,
            );

            // Input handling
            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.Update),
                input.uiInteractionDetectionSystem,
                ParamRegistry,
            );

            // Rendering system
            scheduler.addSystem(
                e,
                zevy_ecs.schedule.Stage(zevy_ecs.schedule.Stages.PostDraw),
                zevy_ecs.chain(.{ systems.uiRenderSystem, systems.uiInputKeyRenderSystem }),
                ParamRegistry,
            );
        }

        pub fn deinit(self: *@This(), _: std.mem.Allocator, e: *zevy_ecs.Manager) anyerror!void {
            _ = self;
            _ = e;
        }
    };
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(@import("ui_tests.zig"));
    std.testing.refAllDecls(@import("ui_render_tests.zig"));
}
