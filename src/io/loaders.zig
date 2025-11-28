const std = @import("std");
const rl = @import("raylib");
const io_util = @import("../io/util.zig");
const types = @import("types.zig");
const input = @import("../input/input.zig");
const loaders = @import("loader.zig");
const known_folders = @import("known_folders");

pub const TextureLoader = struct {
    pub const LoadSettings = struct {
        // Example: add fields as needed, e.g. filtering, mipmaps, etc.
    };
    pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!rl.Texture {
        _ = _settings; // Suppress unused parameter warning
        _ = _file_resolver; // Simple loader doesn't need file resolver

        // Use absolute path directly with raylib
        const path_z = try std.heap.c_allocator.dupeZ(u8, absolute_path);
        defer std.heap.c_allocator.free(path_z);
        const tex = try rl.loadTexture(path_z);
        if (!rl.isTextureValid(tex)) {
            return error.OutOfMemoryGPU;
        }
        return tex;
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{ ".png", ".jpg", ".jpeg", ".bmp", ".tga", ".gif" };
    }

    pub fn unload(_: @This(), texture: rl.Texture) void {
        rl.unloadTexture(texture);
    }
};

pub const ImageLoader = struct {
    pub const LoadSettings = struct {
        // Example: add fields as needed
    };
    pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!rl.Image {
        _ = _settings; // Suppress unused parameter warning
        _ = _file_resolver; // Simple loader doesn't need file resolver

        // Use absolute path directly with raylib
        const path_z = try std.heap.c_allocator.dupeZ(u8, absolute_path);
        defer std.heap.c_allocator.free(path_z);
        const image = try rl.loadImage(path_z);
        if (!rl.isImageValid(image)) {
            return error.OutOfMemoryCPU;
        }
        return image;
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{ ".png", ".jpg", ".jpeg", ".bmp", ".tga", ".gif" };
    }

    pub fn unload(_: @This(), image: rl.Image) void {
        rl.unloadImage(image);
    }
};

pub const SoundLoader = struct {
    pub const LoadSettings = struct {
        // Example: add fields as needed, e.g. streaming, format hints, etc.
    };
    pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!rl.Sound {
        _ = _settings; // Suppress unused parameter warning
        _ = _file_resolver; // Simple loader doesn't need file resolver

        // Use absolute path directly with raylib
        const ext = std.fs.path.extension(absolute_path);
        if (std.mem.eql(u8, ext, ".wav")) {
            const path_z = try std.heap.c_allocator.dupeZ(u8, absolute_path);
            defer std.heap.c_allocator.free(path_z);
            const wave = try rl.loadWave(path_z);
            if (!rl.isWaveValid(wave)) {
                return error.InvalidSound;
            }
            const sound = rl.loadSoundFromWave(wave);
            rl.unloadWave(wave);
            if (!rl.isSoundValid(sound)) {
                return error.InvalidSound;
            }
            return sound;
        }
        const path_z = try std.heap.c_allocator.dupeZ(u8, absolute_path);
        defer std.heap.c_allocator.free(path_z);
        const sound = try rl.loadSound(path_z);
        if (!rl.isSoundValid(sound)) {
            return error.InvalidSound;
        }
        return sound;
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{ ".wav", ".ogg", ".mp3", ".flac" };
    }

    pub fn unload(_: @This(), sound: rl.Sound) void {
        rl.unloadSound(sound);
    }
};

pub const MusicLoader = struct {
    pub const LoadSettings = struct {
        // Example: add fields as needed
    };
    pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!rl.Music {
        _ = _settings; // Suppress unused parameter warning
        _ = _file_resolver; // Simple loader doesn't need file resolver

        // Use absolute path directly with raylib
        const path_z = try std.heap.c_allocator.dupeZ(u8, absolute_path);
        defer std.heap.c_allocator.free(path_z);
        const music = try rl.loadMusicStream(path_z);
        if (!rl.isMusicValid(music)) {
            return error.InvalidMusic;
        }
        return music;
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{ ".mp3", ".wav", ".ogg", ".flac" };
    }

    pub fn unload(_: @This(), music: rl.Music) void {
        rl.unloadMusicStream(music);
    }
};

pub const FontLoader = struct {
    pub const LoadSettings = struct {
        // Example: add fields as needed
    };
    pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!rl.Font {
        _ = _settings; // Suppress unused parameter warning
        _ = _file_resolver; // Simple loader doesn't need file resolver

        // Use absolute path directly with raylib
        const path_z = try std.heap.c_allocator.dupeZ(u8, absolute_path);
        defer std.heap.c_allocator.free(path_z);
        const font = try rl.loadFont(path_z);
        if (!rl.isFontValid(font)) {
            return error.InvalidFont;
        } else if (!rl.isTextureValid(font.texture)) {
            return error.OutOfMemoryGPU;
        }
        return font;
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{ ".ttf", ".otf", ".fnt" };
    }

    pub fn unload(_: @This(), font: rl.Font) void {
        rl.unloadFont(font);
    }
};

pub const ShaderLoader = struct {
    pub const LoadSettings = struct {
        // Optional fragment shader path - if not provided, derive from vertex shader path
        frag: ?[]const u8 = null,
    };

    pub fn load(_: @This(), absolute_path: []const u8, file_resolver: ?*const loaders.FileResolver, settings: ?*const LoadSettings) anyerror!rl.Shader {
        // Vertex shader is the main file
        const vertex_path = absolute_path;

        // Determine fragment shader path
        const frag_path = blk: {
            if (settings) |s| {
                if (s.frag) |explicit_path| {
                    // If explicit path provided, resolve it relative to base directory
                    if (file_resolver) |resolver| {
                        break :blk try resolver.resolve_path(resolver, std.heap.page_allocator, explicit_path);
                    } else {
                        // No resolver, assume it's already absolute or relative to cwd
                        break :blk try std.heap.page_allocator.dupe(u8, explicit_path);
                    }
                }
            }
            // Derive fragment shader path from vertex shader (default case)
            const base = std.fs.path.stem(absolute_path);
            const dir = std.fs.path.dirname(absolute_path) orelse ".";
            break :blk try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ dir, try std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{ base, ".fs" }) });
        };
        defer std.heap.page_allocator.free(frag_path);

        // Load shader from memory
        const vertex_path_z = try std.heap.c_allocator.dupeZ(u8, vertex_path);
        defer std.heap.c_allocator.free(vertex_path_z);
        const frag_path_z = try std.heap.c_allocator.dupeZ(u8, frag_path);
        defer std.heap.c_allocator.free(frag_path_z);
        std.log.info("Loading shader: vertex='{s}', fragment='{s}'\n", .{ std.fs.path.basename(vertex_path), std.fs.path.basename(frag_path) });
        const shader = try rl.loadShader(vertex_path_z, frag_path_z);
        if (!rl.isShaderValid(shader)) {
            return error.InvalidShader;
        }
        return shader;
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{ ".vs", ".fs", ".*" };
    }

    pub fn unload(_: @This(), shader: rl.Shader) void {
        rl.unloadShader(shader);
    }
};

pub const XmlDocumentLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: @This(), absolute_path: []const u8, _file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!@import("../io/xml.zig").XmlDocument {
        _ = _settings;
        _ = _file_resolver;
        const allocator = std.heap.page_allocator;
        const file = try std.fs.openFileAbsolute(absolute_path, .{});
        defer file.close();

        const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        // XmlDocument will take ownership of `data` and free it on deinit
        return try @import("../io/xml.zig").XmlDocument.initFromSlice(allocator, data, .{});
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{".xml"};
    }

    pub fn unload(_: @This(), doc: @import("../io/xml.zig").XmlDocument) void {
        var d = doc;
        d.deinit();
    }
};

pub const InputIconsLoader = struct {
    pub const LoadSettings = struct {};

    pub fn load(_: @This(), absolute_path: []const u8, file_resolver: ?*const loaders.FileResolver, _settings: ?*const LoadSettings) anyerror!types.IconAtlas {
        _ = _settings;

        const allocator = std.heap.page_allocator;
        const resolver = file_resolver orelse return error.RequiresFileResolver;

        // Read XML file into memory
        const file = try std.fs.openFileAbsolute(absolute_path, .{});
        defer file.close();
        const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10 MB limit

        // Parse XML using XmlDocument and the reusable helper
        const XmlDocument = @import("../io/xml.zig").XmlDocument;
        var doc = try XmlDocument.initFromSlice(allocator, data, .{});
        defer doc.deinit();

        const parsed = try doc.parseTextureAtlas(allocator);
        const rel = parsed.image_path orelse return error.InvalidFile;
        const frames = parsed.frames;

        var tex: rl.Texture = undefined;
        var owns_tex: bool = true;

        const base_dir = resolver.base_dir;
        const image_path = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, rel });
        defer allocator.free(image_path);
        tex = try resolver.loaders.loadNow(rl.Texture, image_path);
        owns_tex = false;

        // Build IconAtlas (owns the texture)
        const IconAtlas = types.IconAtlas;
        // Build parsed_keys parallel array
        var parsed_keys = try std.ArrayList(?input.InputKey).initCapacity(allocator, frames.items.len);
        // Attempt to parse each frame.name into an InputKey
        for (frames.items) |f| {
            if (input.InputKey.fromString(f.name, allocator)) |k| {
                const opt: ?input.InputKey = k;
                try parsed_keys.append(allocator, opt);
            } else {
                try parsed_keys.append(allocator, null);
            }
        }

        return IconAtlas{
            .texture = tex,
            .frames = frames,
            .allocator = allocator,
            .owns_texture = owns_tex,
            .parsed_keys = parsed_keys,
        };
    }

    pub fn extensions() []const []const u8 {
        return &[_][]const u8{".xml"};
    }

    pub fn unload(_: @This(), atlas: types.IconAtlas) void {
        var a = atlas;
        a.deinit();
    }
};
