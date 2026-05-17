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
/// `PreDraw` stage. Once sources are available in `Assets`, `resolved` is populated and
/// `getShader()` returns the compiled program.
///
/// Cleanup: register `cleanupShaderSystem` at the `Exit` stage to unload GPU programs
/// before raylib shuts down.
pub const ShaderComponent = struct {
    vert: ?AssetHandle = null,
    frag: ?AssetHandle = null,
    /// Populated by `resolveShaderSystem` once the source assets are available.
    /// Do not set manually.
    resolved: ?rl.Shader = null,

    /// Returns the active custom shader for this component:
    /// - Both handles null → `null` (no shader mode should be applied).
    /// - At least one handle set → `resolved`, or `null` if not yet compiled.
    pub fn getShader(self: *const ShaderComponent) ?rl.Shader {
        if (self.vert == null and self.frag == null) return null;
        return self.resolved;
    }
};

/// ECS system that compiles `ShaderComponent` source handles into `rl.Shader` programs and
/// stores them in `comp.resolved`. Skips components already resolved or with both handles null.
/// Source assets are looked up from `Res(Assets)` — if not yet loaded, the entity is skipped
/// and retried on the next frame.
///
/// Register in the `PreDraw` stage (before render systems):
///   scheduler.addSystem(&ecs, Stage(Stages.PreDraw), resolveShaderSystem, ParamRegistry);
pub fn resolveShaderSystem(
    _: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { shader: ShaderComponent }),
    assets_res: zevy_ecs.params.Res(Assets),
) !void {
    const assets: *const Assets = assets_res.get();

    while (query.next()) |item| {
        const comp: *ShaderComponent = item.shader;
        // Already resolved or using default shader — nothing to do.
        if (comp.resolved != null or (comp.vert == null and comp.frag == null)) continue;

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

        comp.resolved = try rl.loadShaderFromMemory(vs_source, fs_source);
    }
}

/// ECS system that unloads the compiled `rl.Shader` from every `ShaderComponent`.
/// Register in the `Exit` stage so GPU programs are freed before raylib shuts down:
///   scheduler.addSystem(&ecs, Stage(Stages.Exit), cleanupShaderSystem, ParamRegistry);
pub fn cleanupShaderSystem(
    _: zevy_ecs.params.Commands,
    query: zevy_ecs.params.Query(struct { shader: ShaderComponent }),
) !void {
    while (query.next()) |item| {
        const comp: *ShaderComponent = item.shader;
        if (comp.resolved) |shader| {
            rl.unloadShader(shader);
            comp.resolved = null;
        }
    }
}
