const std = @import("std");

// Export all UI components
pub const components = @import("ui_components.zig");
pub const layout = @import("ui_layout.zig");
pub const renderer = @import("ui_renderer.zig");
pub const systems = @import("ui_systems.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDecls(@import("ui_tests.zig"));
    std.testing.refAllDecls(@import("ui_render_tests.zig"));
}
