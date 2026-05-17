const components = @import("components.zig");
const texture_atlas = @import("texture_atlas.zig");
const shader_mod = @import("shader.zig");
pub const Model = components.Model;
pub const Sprite = components.Sprite;

pub const atlas = struct {
    pub const TextureAtlas = texture_atlas.TextureAtlas;
    pub const NamedTextureAtlas = texture_atlas.NamedTextureAtlas;
    pub const NamedFrame = texture_atlas.NamedFrame;
    pub const FrameRect = texture_atlas.FrameRect;
};

pub const shader = struct {
    pub const ShaderSource = shader_mod.ShaderSource;
    pub const ShaderSourceLoader = shader_mod.ShaderSourceLoader;
    pub const ShaderComponent = shader_mod.ShaderComponent;
    pub const resolveShaderSystem = shader_mod.resolveShaderSystem;
    pub const cleanupShaderSystem = shader_mod.cleanupShaderSystem;
};
