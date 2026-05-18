const std = @import("std");
const rl = @import("raylib");
const zevy_ecs = @import("zevy_ecs");
const io = @import("../io/root.zig");

pub const AssetHandle = io.AssetHandle;
pub const Assets = io.Assets;
pub const ShaderSource = io.ShaderSource;
pub const ShaderSourceLoader = io.ShaderSourceLoader;

/// Component associating an entity with a GLSL shader program.
///
/// - `vert`: handle to a `ShaderSource` asset for the vertex stage, or `null` for raylib's default.
/// - `frag`: handle to a `ShaderSource` asset for the fragment stage, or `null` for raylib's default.
///
/// Both `null` means no custom shader is applied (draw with normal raylib pipeline).
///
/// For entities with at least one non-null handle, register `resolveShaderSystem` at the
/// `PreDraw` stage. Once sources are available in `Assets`, the compiled program is stored
/// in `Assets` and `resolved_handle` holds the key. Use `getShader(assets)` to retrieve it.
///
/// Cleanup: register `cleanupShaderSystem` at the `Exit` stage to unload GPU programs
/// before raylib shuts down.
pub const ShaderComponent = struct {
    vert: ?AssetHandle = null,
    frag: ?AssetHandle = null,
    /// Handle into `Assets` for the compiled `rl.Shader`. Populated by `resolveShaderSystem`.
    /// Do not set manually.
    resolved_handle: ?AssetHandle = null,

    uniforms: std.StringHashMap(ShaderUniformValue),

    pub fn init(allocator: std.mem.Allocator) ShaderComponent {
        return ShaderComponent{
            .uniforms = .init(allocator),
        };
    }

    pub fn initWithHandles(allocator: std.mem.Allocator, vert: ?AssetHandle, frag: ?AssetHandle) ShaderComponent {
        return ShaderComponent{
            .vert = vert,
            .frag = frag,
            .uniforms = .init(allocator),
        };
    }

    /// Create a ShaderComponent from a pre-compiled `rl.Shader` asset handle.
    /// Use this when the shader has already been compiled via `assets.loadAsset(rl.Shader, ...)`.
    /// `resolveShaderSystem` will skip this component since `resolved_handle` is already set.
    pub fn initResolved(allocator: std.mem.Allocator, resolved: AssetHandle) ShaderComponent {
        return ShaderComponent{
            .resolved_handle = resolved,
            .uniforms = .init(allocator),
        };
    }

    pub fn deinit(self: *ShaderComponent) void {
        self.uniforms.deinit();
    }

    pub fn setUniform(self: *ShaderComponent, uniformName: []const u8, value: ShaderUniformValue) error{OutOfMemory}!void {
        try self.uniforms.put(uniformName, value);
    }

    pub fn getUniform(self: *ShaderComponent, name: []const u8) ?ShaderUniformValue {
        return self.uniforms.get(name);
    }

    pub fn applyUniform(self: *const ShaderComponent, shader: rl.Shader, uniformName: []const u8) void {
        if (self.uniforms.get(uniformName)) |value| {
            var buf: [128]u8 = undefined;
            const name = std.fmt.bufPrintSentinel(&buf, "{s}", .{uniformName}, 0) catch return;
            const uf_loc = rl.getShaderLocation(shader, name);
            if (uf_loc >= 0) {
                switch (value) {
                    .float => |f| rl.setShaderValue(shader, uf_loc, @ptrCast(&f), .float),
                    .vec2 => |v| rl.setShaderValue(shader, uf_loc, @ptrCast(&v), .vec2),
                    .vec3 => |v| rl.setShaderValue(shader, uf_loc, @ptrCast(&v), .vec3),
                    .vec4 => |v| rl.setShaderValue(shader, uf_loc, @ptrCast(&v), .vec4),
                    .int => |i| rl.setShaderValue(shader, uf_loc, @ptrCast(&i), .int),
                    .ivec2 => |v| rl.setShaderValue(shader, uf_loc, @ptrCast(&v), .ivec2),
                    .ivec3 => |v| rl.setShaderValue(shader, uf_loc, @ptrCast(&v), .ivec3),
                    .ivec4 => |v| rl.setShaderValue(shader, uf_loc, @ptrCast(&v), .ivec4),
                    .mat4 => |m| rl.setShaderValueMatrix(shader, uf_loc, m),
                    .tex => |t| rl.setShaderValueTexture(shader, uf_loc, t),
                }
            }
        }
    }

    /// Applies all stored uniforms for this component to the currently active shader.
    pub fn applyUniforms(self: *const ShaderComponent, shader: rl.Shader) void {
        var iter = self.uniforms.keyIterator();
        while (iter.next()) |item| {
            self.applyUniform(shader, item.*);
        }
    }

    /// Returns the active custom shader for this component by looking it up in `assets`:
    /// - Both handles null → `null` (no shader mode should be applied).
    /// - At least one handle set → compiled shader, or `null` if not yet resolved.
    pub fn getShader(self: *const ShaderComponent, assets: *const Assets) ?rl.Shader {
        if (self.resolved_handle) |h| {
            return if (assets.get(rl.Shader, h)) |s| s.* else null;
        }
        return null;
    }
};

/// Manages per-entity shader mode switching inside a draw loop.
///
/// Raylib's `beginShaderMode`/`endShaderMode` is global GPU state — only one shader
/// can be active at a time. This helper minimises GPU state changes by tracking the
/// currently active shader and only switching when the entity's shader differs.
///
/// Because the ECS query iterates entities archetype-by-archetype, entities that share
/// the same `ShaderComponent` (same compiled shader) are naturally contiguous, so
/// `beginShaderMode` is called at most once per unique shader per frame.
///
/// Usage:
/// ```zig
/// fn renderSystem(
///     _: zevy_ecs.params.Commands,
///     query: zevy_ecs.params.Query(struct { pos: Position, sprite: Circle, shader: ?ShaderComponent }),
///     assets_res: zevy_ecs.params.Res(Assets),
/// ) !void {
///     var batcher = ShaderBatcher.init(assets_res.get());
///     defer batcher.finish();
///
///     while (query.next()) |item| {
///         batcher.begin(item.shader);
///         rl.drawCircleV(.{ .x = item.pos.x, .y = item.pos.y }, item.sprite.radius, item.sprite.color);
///     }
/// }
/// ```
///
/// Per-draw-call uniforms (values that differ per entity, e.g. a tint colour) can still
/// be pushed inline with `rl.setShaderValue` after `batcher.begin` returns — the shader
/// is already active at that point.
pub const ShaderBatcher = struct {
    assets: *const Assets,
    active_id: u32,

    pub fn init(assets: *const Assets) ShaderBatcher {
        return .{ .assets = assets, .active_id = 0 };
    }

    /// Call once per entity before its draw call.
    /// Switches shader mode only when the active shader changes.
    /// Stored uniforms are re-applied via `applyUniforms` whenever a new shader is activated.
    pub fn begin(self: *ShaderBatcher, sc: ?*const ShaderComponent) void {
        const incoming: ?rl.Shader = if (sc) |c| c.getShader(self.assets) else null;
        const new_id: u32 = if (incoming) |sh| sh.id + 1 else 0;

        if (new_id == self.active_id) return;

        if (self.active_id != 0) rl.endShaderMode();
        if (incoming) |sh| {
            rl.beginShaderMode(sh);
            if (sc) |c| c.applyUniforms(sh);
        }
        self.active_id = new_id;
    }

    /// Call after the draw loop to close any open shader mode.
    /// Safe to call via `defer` at the start of the render system.
    pub fn finish(self: *ShaderBatcher) void {
        if (self.active_id != 0) {
            rl.endShaderMode();
            self.active_id = 0;
        }
    }
};

pub const ShaderUniformValue = union(enum) {
    float: f32,
    vec2: rl.Vector2,
    vec3: rl.Vector3,
    vec4: rl.Vector4,
    int: i32,
    ivec2: struct { x: i32, y: i32 },
    ivec3: struct { x: i32, y: i32, z: i32 },
    ivec4: struct { x: i32, y: i32, z: i32, w: i32 },
    mat4: rl.Matrix,
    tex: rl.Texture2D,
};

const PairKey = struct { v: AssetHandle, f: AssetHandle };

/// ECS system that compiles `ShaderComponent` source handles into `rl.Shader` programs,
/// stores them in `Assets`, and records the handle in `comp.resolved_handle`.
/// Skips components already resolved or with both handles null.
/// Source assets are looked up from `ResMut(Assets)` — if not yet loaded, the entity is
/// skipped and retried on the next frame.
///
/// Multiple entities that share the same `(vert, frag)` source-handle pair are deduplicated:
/// the shader is compiled exactly once and all entities receive the same `resolved_handle`.
///
/// Register in the `PreDraw` stage (before render systems):
///   scheduler.addSystem(&ecs, Stage(Stages.PreDraw), resolveShaderSystem, ParamRegistry);
pub fn resolveShaderSystem(
    commands: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { shader: ShaderComponent }),
    assets_res: zevy_ecs.params.ResMut(Assets),
    compiled_local: zevy_ecs.params.Local(std.AutoHashMap(PairKey, AssetHandle)),
) !void {
    const assets = assets_res.get();

    // Deduplication map: (vert_handle orelse 0, frag_handle orelse 0) → compiled AssetHandle.
    // Entities sharing the same source handles receive the same compiled GPU program.
    if (compiled_local.isSet() == false) {
        compiled_local.set(std.AutoHashMap(PairKey, AssetHandle).init(commands.allocator()));
    }
    const compiled = compiled_local.getPtr();

    while (query.next()) |item| {
        const comp: *ShaderComponent = item.shader;
        // Already resolved or using default shader — nothing to do.
        if (comp.resolved_handle != null or (comp.vert == null and comp.frag == null)) continue;

        const key = PairKey{
            .v = comp.vert orelse 0,
            .f = comp.frag orelse 0,
        };

        // Reuse an already-compiled shader if a previous entity had the same source pair.
        if (compiled.get(key)) |handle| {
            comp.resolved_handle = handle;
            continue;
        }

        var vs_source: ?[:0]const u8 = null;
        var fs_source: ?[:0]const u8 = null;

        if (comp.vert) |h| {
            const src = assets.get(ShaderSource, h) orelse continue; // retry next frame
            vs_source = src.source;
        }
        if (comp.frag) |h| {
            const src = assets.get(ShaderSource, h) orelse continue; // retry next frame
            fs_source = src.source;
        }

        const shader = try rl.loadShaderFromMemory(vs_source, fs_source);

        // Hand the compiled shader to the asset manager — it owns the GPU resource from here.
        const handle = try assets.insert(rl.Shader, shader);
        try compiled.put(key, handle);
        comp.resolved_handle = handle;
    }

    // Unload source assets for every unique pair compiled this invocation.
    // Pointers into source strings are no longer needed after loadShaderFromMemory.
    var iter = compiled.keyIterator();
    while (iter.next()) |key| {
        if (key.v != 0) assets.unload(ShaderSource, key.v);
        if (key.f != 0) assets.unload(ShaderSource, key.f);
    }
}

/// ECS system that unloads the compiled `rl.Shader` from every `ShaderComponent` via
/// the asset manager. Register in the `Exit` stage so GPU programs are freed before
/// raylib shuts down:
///   scheduler.addSystem(&ecs, Stage(Stages.Exit), cleanupShaderSystem, ParamRegistry);
pub fn cleanupShaderSystem(
    _: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { shader: ShaderComponent }),
    assets_res: zevy_ecs.params.ResMut(Assets),
) !void {
    const assets = assets_res.get();
    while (query.next()) |item| {
        const comp: *ShaderComponent = item.shader;
        if (comp.resolved_handle) |h| {
            assets.unload(rl.Shader, h);
            comp.resolved_handle = null;
        }
    }
}
