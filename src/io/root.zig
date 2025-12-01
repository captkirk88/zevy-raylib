/// Built-in asset types and related utilities
const assets = @import("assets.zig");
/// Assets type for managing asset loading and schemes
pub const Assets = assets.Assets;

/// AssetHandle type for managing asset references
pub const AssetHandle = assets.AssetHandle;

/// LoadContext for loaders to access parent URI and related assets
pub const LoadContext = assets.LoadContext;

/// Built-in loaders
pub const TextureLoader = assets.TextureLoader;
pub const SoundLoader = assets.SoundLoader;
pub const MusicLoader = assets.MusicLoader;
pub const FontLoader = assets.FontLoader;
pub const ShaderLoader = assets.ShaderLoader;
pub const XmlDocumentLoader = assets.XmlDocumentLoader;
pub const IconAtlasLoader = assets.IconAtlasLoader;

/// General IO utility functions
pub const util = @import("util.zig");

/// Scheme resolver for handling different URI schemes (e.g., file://, embedded://)
pub const schemes = @import("scheme_resolver.zig");

/// XML document utilities
pub const xml = @import("xml.zig");

/// Asset types
pub const types = @import("types.zig");
