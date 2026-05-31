const zevy_app = @import("app");

pub const DeltaTime = struct {
    value: f32,
};

/// Fixed-timestep accumulator for game logic updates.
///
/// Works in both windowed and headless (no window) mode.
///
/// Usage:
/// ```zig
/// var accum = FixedTimestepAccumulator.init(1.0 / 60.0);
/// // each frame:
/// while (!zevy_raylib.shouldClose(io)) {
///     accum.beginFrame();
///     while (accum.update()) { /* run fixed-dt systems */ }
///     if (accum.diagnostics.?.overloaded) {
///         std.log.warn("Fixed-step overload: dropped {d:.2}ms", .{accum.diagnostics.?.dropped_time * 1000.0});
///     }
///     accum.finishFrame();
/// }
/// ```
pub const FixedTimestepAccumulator = zevy_app.FixedTimestepAccumulator;
