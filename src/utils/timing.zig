const rl = @import("raylib");

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
///     while (accum.consumeTick()) { /* run fixed-dt systems */ }
/// }
/// ```
pub const FixedTimestepAccumulator = struct {
    const Self = @This();

    accumulator: f32 = 0.0,
    delta: f32,
    /// Maximum fixed updates consumed per frame (spiral-of-death guard).
    max_updates: usize = 5,
    /// Frame times above this are clamped (spiral-of-death guard).
    max_frame_time: f32 = 0.25,
    /// Number of fixed updates consumed in the current frame (reset by beginFrame()).
    updates: usize = 0,

    pub fn init(fixed_dt: f32) Self {
        return .{ .delta = fixed_dt };
    }

    /// Call once per frame. Reads the frame time (or uses fixed_dt in headless mode),
    /// clamps it, and adds it to the accumulator. Resets the per-frame update counter.
    pub fn beginFrame(self: *Self) void {
        const frame_time = if (rl.isWindowReady()) rl.getFrameTime() else self.delta;
        const clamped = @min(frame_time, self.max_frame_time);
        self.accumulator += clamped;
        self.updates = 0;
    }

    /// Returns true while there is accumulated time left to consume and the
    /// per-frame update cap has not been reached. Drains one fixed_dt tick
    /// per call and increments the update counter.
    pub fn canUpdate(self: *Self) bool {
        if (self.updates >= self.max_updates) return false;
        if (self.accumulator < self.delta) return false;
        self.accumulator -= self.delta;
        self.updates += 1;
        return true;
    }
};
