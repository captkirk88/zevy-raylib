const asset_manager = @import("asset_manager.zig");
const loader = @import("loader.zig");

/// Built-in asset types and related utilities
const assets = @import("assets.zig");
/// Assets type for managing asset loading and schemes
pub const Assets = assets.Assets;

/// AssetHandle type for managing asset references
pub const AssetHandle = asset_manager.AssetHandle;
/// AssetManager type for loading and managing assets
pub const AssetManager = asset_manager.AssetManager;

pub const FileResolver = loader.FileResolver;
/// AssetLoader wrapper type: validates that a loader implements the required interface
pub const AssetLoader = loader.AssetLoader;
/// AssetUnloader wrapper type: validates that an unloader implements the required interface
pub const AssetUnloader = loader.AssetUnloader;

/// Built-in asset loaders
pub const loaders = @import("loaders.zig");

/// General IO utility functions
pub const util = @import("util.zig");

/// Scheme resolver for handling different URI schemes (e.g., file://, http://)
pub const schemes = @import("scheme_resolver.zig");
