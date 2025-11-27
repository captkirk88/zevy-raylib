const std = @import("std");
const rl = @import("raylib");

/// Per-feature input icon style used by the UI renderer.
pub const UIInputIconStyle = struct {
    size: f32 = 16.0,
    spacing: f32 = 4.0,
    tint: rl.Color = rl.Color.white,

    pub fn init() UIInputIconStyle {
        return UIInputIconStyle{};
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

    // Button styling
    button_background: rl.Color = rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 },
    button_text: rl.Color = rl.Color.black,
    button_hover_tint: rl.Color = rl.Color{ .r = 180, .g = 180, .b = 180, .a = 255 },
    button_disabled_tint: rl.Color = rl.Color{ .r = 128, .g = 128, .b = 128, .a = 255 },

    // Typography
    font: ?rl.Font = null,
    font_size: i32 = 10,

    // Layout helpers
    padding: f32 = 6.0,
    margin: f32 = 6.0,

    // Input icon specific style (keeps previous API)
    input_icon: UIInputIconStyle = UIInputIconStyle.init(),

    pub fn init() UIStyle {
        return UIStyle{};
    }
};
