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

    uniforms: std.AutoHashMap([]const u8, ShaderUniformValue),

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

    pub fn deinit(self: *ShaderComponent) void {
        self.uniforms.deinit();
    }

    pub fn setUniform(self: *ShaderComponent, uniformName: []const u8, value: ShaderUniformValue) error{OutOfMemory}!void {
        if (self.resolved) |r| {
            const uf_loc = rl.getShaderLocation(r, uniformName);
            if (uf_loc >= 0) {
                switch (value) {
                    .Float => |f| rl.setShaderValue(r, uf_loc, @ptrCast(&f), .float),
                    .Vec2 => |v| rl.setShaderValue(r, uf_loc, @ptrCast(&v), .vec2),
                    .Vec3 => |v| rl.setShaderValue(r, uf_loc, @ptrCast(&v), .vec3),
                    .Vec4 => |v| rl.setShaderValue(r, uf_loc, @ptrCast(&v), .vec4),
                    .Int => |i| rl.setShaderValue(r, uf_loc, @ptrCast(&i), .int),
                    .IVec2 => |v| rl.setShaderValue(r, uf_loc, @ptrCast(&v), .ivec2),
                    .IVec3 => |v| rl.setShaderValue(r, uf_loc, @ptrCast(&v), .ivec3),
                    .IVec4 => |v| rl.setShaderValue(r, uf_loc, @ptrCast(&v), .ivec4),
                    .Mat4 => |m| rl.setShaderValueMatrix(r, uf_loc, m),
                    .Texture => |t| rl.setShaderValueTexture(r, uf_loc, t),
                    else => @compileError("Unhandled ShaderUniformValue type"),
                }
            }
        }

        try self.uniforms.put(uniformName, value);
    }

    pub fn getUniform(self: *ShaderComponent, name: []const u8) ?ShaderUniformValue {
        return self.uniforms.get(name);
    }

    /// Returns the active custom shader for this component:
    /// - Both handles null → `null` (no shader mode should be applied).
    /// - At least one handle set → `resolved`, or `null` if not yet compiled.
    pub fn getShader(self: *const ShaderComponent) ?rl.Shader {
        if (self.vert == null and self.frag == null) return null;
        return self.resolved;
    }
};

pub const ShaderUniformValue = union(enum) {
    Float: f32,
    Vec2: rl.Vector2,
    Vec3: rl.Vector3,
    Vec4: rl.Vector4,
    Int: i32,
    IVec2: struct { x: i32, y: i32 },
    IVec3: struct { x: i32, y: i32, z: i32 },
    IVec4: struct { x: i32, y: i32, z: i32, w: i32 },
    Mat4: rl.Matrix,
    Texture: rl.Texture2D,
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
    assets_res: zevy_ecs.params.ResMut(Assets),
) !void {
    const assets = assets_res.get();

    while (query.next()) |item| {
        const comp: *ShaderComponent = item.shader;
        // Already resolved or using default shader — nothing to do.
        if (comp.resolved != null or (comp.vert == null and comp.frag == null)) continue;

        var vs_source: ?[:0]const u8 = null;
        var fs_source: ?[:0]const u8 = null;

        if (comp.vert) |h| {
            const src = assets.get(ShaderSource, h) orelse continue; // retry next frame
            vs_source = src.source;
            assets.unload(ShaderSource, h); // source no longer needed after compilation
        }
        if (comp.frag) |h| {
            const src = assets.get(ShaderSource, h) orelse continue; // retry next frame
            fs_source = src.source;
            assets.unload(ShaderSource, h); // source no longer needed after compilation
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
