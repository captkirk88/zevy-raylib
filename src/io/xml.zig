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
