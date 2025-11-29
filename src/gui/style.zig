const std = @import("std");
const rl = @import("raylib");

/// Per-feature input icon style used by the UI renderer.
pub const InputIconStyle = struct {
    size: f32 = 16.0,
    spacing: f32 = 4.0,
    // Default to white so icons are visible unless a style explicitly tints them.
    tint: rl.Color = rl.Color.white,

    pub fn init() InputIconStyle {
        return InputIconStyle{};
    }
};

/// Button-specific style values.
pub const ButtonStyle = struct {
    background: rl.Color = rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 },
    text: rl.Color = rl.Color.black,
    hover_tint: rl.Color = rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 },
    disabled_tint: rl.Color = rl.Color{ .r = 128, .g = 128, .b = 128, .a = 255 },
    border_thickness: f32 = 1.0,

    pub fn init() ButtonStyle {
        return ButtonStyle{};
    }
};

/// Panel-specific styling such as background and border.
pub const PanelStyle = struct {
    background: rl.Color = rl.Color{ .r = 220, .g = 220, .b = 220, .a = 255 },
    border: rl.Color = rl.Color{ .r = 128, .g = 128, .b = 128, .a = 255 },
    border_thickness: f32 = 1.0,

    pub fn init() PanelStyle {
        return PanelStyle{};
    }
};

/// Typography/style values for text rendering.
pub const TextStyle = struct {
    color: rl.Color = rl.Color.black,
    font: ?rl.Font = null,
    font_size: i32 = 10,

    pub fn init() TextStyle {
        return TextStyle{};
    }
};

/// Global UI style resource. This centralizes styling values that raylib
/// functions can apply directly (colors, font, sizes, padding).
pub const UIStyle = struct {
    // Basic colors
    background: rl.Color = rl.Color{ .r = 240, .g = 240, .b = 240, .a = 255 },
    text_color: rl.Color = rl.Color.black,

    // Panel styling
    panel_background: rl.Color = rl.Color{ .r = 220, .g = 220, .b = 220, .a = 255 },
    panel_border: rl.Color = rl.Color{ .r = 128, .g = 128, .b = 128, .a = 255 },
    panel_border_thickness: f32 = 1.0,

    // Panel style subtype for more granular overrides
    panel: PanelStyle = PanelStyle.init(),

    // Button styling (legacy top-level fields kept for backward compatibility)
    button_background: rl.Color = rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 },
    button_text: rl.Color = rl.Color.black,
    button_hover_tint: rl.Color = rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 },
    button_disabled_tint: rl.Color = rl.Color{ .r = 128, .g = 128, .b = 128, .a = 255 },

    // Button style subtype for granular button overrides
    button: ButtonStyle = ButtonStyle.init(),

    // Typography (top-level convenience fields)
    font: ?rl.Font = null,
    font_size: i32 = 10,

    // Text style subtype
    text: TextStyle = TextStyle.init(),

    // Layout helpers
    padding: f32 = 6.0,
    margin: f32 = 6.0,

    // Input icon specific style (keeps previous API)
    input_icon: InputIconStyle = InputIconStyle.init(),

    pub fn init() UIStyle {
        return UIStyle{};
    }
};
