const std = @import("std");
const xml = @import("xml");

/// Convenience wrapper around zig-xml's Reader/Writer APIs.
/// XmlDocument owns the underlying file handle, buffering, and parser state
/// so callers only need to focus on iterating nodes or emitting output.
pub const XmlDocument = struct {
    allocator: std.mem.Allocator,
    mode: Mode,
    state: State,

    pub const Mode = enum { reader, writer };

    pub const ReaderOptions = struct {
        buffer_size: usize = 4 * 1024,
        xml: xml.Reader.Options = .{},
    };

    pub const WriterOptions = struct {
        buffer_size: usize = 4 * 1024,
        xml: xml.Writer.Options = .{},
    };

    pub const Error = error{
        InvalidMode,
        MissingAttribute,
        InvalidIntegerValue,
        MalformedXml,
        ReadFailed,
        OutOfMemory,
    };

    const State = union(enum) {
        reader: ReaderState,
        writer: WriterState,
    };

    /// Parsed atlas data return type
    pub const AtlasParseResult = struct {
        image_path: ?[]u8,
        frames: std.ArrayList(@import("../graphics/texture_atlas.zig").NamedFrame),
    };

    const ReaderState = struct {
        data: []const u8,
        static_reader: xml.Reader.Static,

        fn deinit(self: *ReaderState, allocator: std.mem.Allocator) void {
            self.static_reader.deinit();
            allocator.free(self.data);
            self.* = undefined;
        }
    };

    const WriterState = struct {
        file: std.fs.File,
        buffer: []u8,
        file_writer: std.fs.File.Writer,
        writer: xml.Writer,

        fn deinit(self: *WriterState, allocator: std.mem.Allocator) void {
            self.writer.deinit();
            allocator.free(self.buffer);
            self.file.close();
            self.* = undefined;
        }
    };

    pub fn openReader(allocator: std.mem.Allocator, path: []const u8, options: ReaderOptions) !XmlDocument {
        var file = try std.fs.cwd().openFile(path, .{});
        errdefer file.close();
        return initReader(allocator, file, options) catch |err| {
            file.close();
            return err;
        };
    }

    pub fn initReader(allocator: std.mem.Allocator, file: std.fs.File, options: ReaderOptions) !XmlDocument {
        const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        errdefer allocator.free(data);

        const static_reader: xml.Reader.Static = xml.Reader.Static.init(allocator, data, options.xml);
        errdefer static_reader.deinit();

        const state: ReaderState = .{
            .data = data,
            .static_reader = static_reader,
        };

        // we read the file contents into `data` so we can close the file here
        _ = file.close();

        return .{
            .allocator = allocator,
            .mode = .reader,
            .state = .{ .reader = state },
        };
    }

    /// Initialize a reader from an owned byte slice. XmlDocument takes ownership
    /// of `data` and will free it with `allocator` on deinit.
    pub fn initFromSlice(allocator: std.mem.Allocator, data: []const u8, options: ReaderOptions) !XmlDocument {
        const static_reader: xml.Reader.Static = xml.Reader.Static.init(allocator, data, options.xml);
        // static_reader owns no additional heap memory beyond what `data` provides

        const state: ReaderState = .{
            .data = data,
            .static_reader = static_reader,
        };

        return .{
            .allocator = allocator,
            .mode = .reader,
            .state = .{ .reader = state },
        };
    }

    pub fn openWriter(allocator: std.mem.Allocator, path: []const u8, options: WriterOptions) !XmlDocument {
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        errdefer file.close();
        return initWriter(allocator, file, options) catch |err| {
            file.close();
            return err;
        };
    }

    pub fn initWriter(allocator: std.mem.Allocator, file: std.fs.File, options: WriterOptions) !XmlDocument {
        const buffer = try allocator.alloc(u8, options.buffer_size);
        errdefer allocator.free(buffer);
        const file_writer = file.writer(buffer);

        var state: WriterState = .{
            .file = file,
            .buffer = buffer,
            .file_writer = file_writer,
            .writer = undefined,
        };

        state.writer = xml.Writer.init(allocator, &state.file_writer.interface, options.xml);
        errdefer state.writer.deinit();

        return .{
            .allocator = allocator,
            .mode = .writer,
            .state = .{ .writer = state },
        };
    }

    pub fn deinit(self: *XmlDocument) void {
        switch (self.state) {
            .reader => |*reader_state| reader_state.deinit(self.allocator),
            .writer => |*writer_state| writer_state.deinit(self.allocator),
        }
        self.* = undefined;
    }

    pub fn reader(self: *XmlDocument) Error!*xml.Reader {
        return switch (self.state) {
            .reader => |*state| &state.static_reader.interface,
            .writer => return error.InvalidMode,
        };
    }

    pub fn writer(self: *XmlDocument) Error!*xml.Writer {
        return switch (self.state) {
            .writer => |*state| &state.writer,
            .reader => return error.InvalidMode,
        };
    }

    pub fn readNode(self: *XmlDocument) !xml.Reader.Node {
        const reader_ptr = try self.reader();
        return reader_ptr.read();
    }

    pub fn attributeValue(self: *XmlDocument, name: []const u8) Error!?[]const u8 {
        const reader_ptr = try self.reader();
        if (reader_ptr.attributeIndex(name)) |idx| {
            const val = try reader_ptr.attributeValue(idx);
            return val;
        }
        return null;
    }

    pub fn requireAttributeValue(self: *XmlDocument, name: []const u8) Error![]const u8 {
        return (try self.attributeValue(name)) orelse return error.MissingAttribute;
    }

    pub fn parseAttributeInt(self: *XmlDocument, comptime T: type, name: []const u8) Error!T {
        const raw = try self.requireAttributeValue(name);
        return std.fmt.parseInt(T, raw, 10) catch return error.InvalidIntegerValue;
    }

    /// Convenience helper: parse a TextureAtlas-style XML document and return
    /// the imagePath (if present) and an ArrayList of NamedFrame entries.
    /// The returned ArrayList and any image_path buffer are owned by `allocator`
    /// and must be freed by the caller when done.
    pub fn parseTextureAtlas(self: *XmlDocument, allocator: std.mem.Allocator) Error!AtlasParseResult {
        const NamedFrame = @import("../graphics/texture_atlas.zig").NamedFrame;

        const rdr = try self.reader();

        var frames = try std.ArrayList(NamedFrame).initCapacity(allocator, 16);
        var frames_owned: bool = true;
        defer if (frames_owned) frames.deinit(allocator);

        var image_path_rel: ?[]u8 = null;
        errdefer if (image_path_rel) |p| allocator.free(p);

        while (true) {
            const node = self.readNode() catch |err| {
                frames.deinit(allocator);
                return err;
            };
            switch (node) {
                .eof => break,
                .element_start => {
                    const element_name = rdr.elementName();
                    if (std.mem.eql(u8, element_name, "TextureAtlas")) {
                        if (image_path_rel == null) {
                            const maybe_path = try self.attributeValue("imagePath");
                            if (maybe_path) |path_slice| {
                                image_path_rel = try allocator.dupe(u8, path_slice);
                                if (image_path_rel) |p| {
                                    const unescaped = try unescapeXmlEntities(allocator, p);
                                    allocator.free(p);
                                    image_path_rel = unescaped;
                                }
                            }
                        }
                    } else if (std.mem.eql(u8, element_name, "SubTexture")) {
                        const frame_name = try allocator.dupe(u8, try self.requireAttributeValue("name"));
                        var frame_name_owned: bool = true;
                        defer if (frame_name_owned) allocator.free(frame_name);
                        const frame_rect = @import("../graphics/texture_atlas.zig").FrameRect{
                            .x = try self.parseAttributeInt(i32, "x"),
                            .y = try self.parseAttributeInt(i32, "y"),
                            .w = try self.parseAttributeInt(i32, "width"),
                            .h = try self.parseAttributeInt(i32, "height"),
                        };
                        try frames.append(allocator, .{ .name = frame_name, .frame = frame_rect });
                        // ownership transferred to frames; prevent deferred free
                        frame_name_owned = false;
                    }
                },
                else => {},
            }
        }

        // transfer ownership out of errdefer context
        const result = AtlasParseResult{
            .image_path = image_path_rel,
            .frames = frames,
        };

        // Prevent the frames.deinit defer from running since we're returning the list
        frames_owned = false;
        return result;
    }
};

pub fn unescapeXmlEntities(allocator: std.mem.Allocator, in: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, in.len);
    defer result.deinit(allocator);
    var i: usize = 0;
    while (i < in.len) {
        if (std.mem.startsWith(u8, in[i..], "&amp;")) {
            try result.append(allocator, '&');
            i += 5;
        } else if (std.mem.startsWith(u8, in[i..], "&lt;")) {
            try result.append(allocator, '<');
            i += 4;
        } else if (std.mem.startsWith(u8, in[i..], "&gt;")) {
            try result.append(allocator, '>');
            i += 4;
        } else if (std.mem.startsWith(u8, in[i..], "&quot;")) {
            try result.append(allocator, '"');
            i += 6;
        } else if (std.mem.startsWith(u8, in[i..], "&apos;")) {
            try result.append(allocator, '\'');
            i += 6;
        } else {
            try result.append(allocator, in[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}
