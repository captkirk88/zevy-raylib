const std = @import("std");
const input_bindings = @import("input_bindings.zig");
const input_types = @import("input_types.zig");

pub const InputBindings = input_bindings.InputBindings;
pub const InputBinding = input_bindings.InputBinding;
pub const InputChord = input_bindings.InputChord;
pub const InputAction = input_bindings.InputAction;
pub const InputKey = input_types.InputKey;

/// Error types for serialization
pub const SerializationError = error{
    InvalidFormat,
    UnsupportedVersion,
    MissingField,
    InvalidKeyCode,
    InvalidChord,
} || std.mem.Allocator.Error || std.fmt.ParseIntError;

/// Serialization format version
const SERIALIZATION_VERSION: u32 = 1;

/// JSON structure for a single input binding
const BindingJson = struct {
    action_name: []const u8,
    action_description: []const u8,
    chord: []const u8,
    enabled: bool,
};

/// JSON structure for the entire input bindings file
const BindingsFileJson = struct {
    version: u32,
    bindings: []BindingJson,
};

/// Serialize input bindings to a writer
/// Accepts std.Io.Writer type for JSON serialization
pub fn serializeToWriter(bindings: *const InputBindings, writer: anytype, allocator: std.mem.Allocator) !void {
    var binding_jsons = std.ArrayList(BindingJson){};
    defer binding_jsons.deinit(allocator);

    // Convert bindings to JSON structures
    for (bindings.getAllBindings()) |*binding| {
        const chord_str = try binding.chord.toString(allocator);
        defer allocator.free(chord_str);

        // We need to allocate these strings for the JSON structure
        const action_name = try allocator.dupe(u8, binding.action.name);
        const action_description = try allocator.dupe(u8, binding.action.description);
        const chord_copy = try allocator.dupe(u8, chord_str);

        try binding_jsons.append(allocator, BindingJson{
            .action_name = action_name,
            .action_description = action_description,
            .chord = chord_copy,
            .enabled = binding.enabled,
        });
    }

    const file_json = BindingsFileJson{
        .version = SERIALIZATION_VERSION,
        .bindings = binding_jsons.items,
    };

    // Serialize to JSON using std.json
    const json_str = try std.json.Stringify.valueAlloc(allocator, file_json, .{
        .whitespace = .indent_2,
    });
    defer allocator.free(json_str);
    try writer.writeAll(json_str);

    // Clean up allocated strings
    for (binding_jsons.items) |binding_json| {
        allocator.free(binding_json.action_name);
        allocator.free(binding_json.action_description);
        allocator.free(binding_json.chord);
    }
}

/// Deserialize input bindings from a reader
/// Accepts any reader type that implements the reader interface
pub fn deserializeFromReader(reader: anytype, allocator: std.mem.Allocator) !InputBindings {
    // Read all content
    const content = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Parse JSON
    var parsed = std.json.parseFromSlice(BindingsFileJson, allocator, content, .{}) catch |err| {
        switch (err) {
            error.SyntaxError, error.UnexpectedToken => return SerializationError.InvalidFormat,
            else => return err,
        }
    };
    defer parsed.deinit();

    const file_json = parsed.value;

    // Check version
    if (file_json.version != SERIALIZATION_VERSION) {
        return SerializationError.UnsupportedVersion;
    }

    // Create bindings collection
    var bindings = InputBindings.init(allocator);
    errdefer bindings.deinit();

    // Parse each binding
    for (file_json.bindings) |binding_json| {
        // Parse the chord
        const chord = try InputChord.fromString(binding_json.chord, allocator) orelse return SerializationError.InvalidChord;

        // Create action (init will duplicate the strings)
        const action = try InputAction.init(allocator, binding_json.action_name, binding_json.action_description);

        // Create binding
        var binding = InputBinding.init(chord, action);
        binding.enabled = binding_json.enabled;

        try bindings.addBinding(binding);
    }

    return bindings;
}

/// Convenience function to serialize to a file
pub fn serializeToFile(bindings: *const InputBindings, file_path: []const u8, allocator: std.mem.Allocator) !void {
    const create_flags = std.fs.File.CreateFlags{
        .truncate = true,
        .exclusive = true,
    };
    const file = try std.fs.cwd().createFile(file_path, create_flags);
    defer file.close();

    var writer = file.deprecatedWriter().any();
    try serializeToWriter(bindings, &writer, allocator);
}

/// Convenience function to deserialize from a file
pub fn deserializeFromFile(file_path: []const u8, allocator: std.mem.Allocator) !InputBindings {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var rdr = file.deprecatedReader().any();
    return try deserializeFromReader(&rdr, allocator);
}

/// Serialize input bindings to a slice
pub fn serializeToSlice(bindings: *const InputBindings, allocator: std.mem.Allocator) ![]u8 {
    var string_writer = std.ArrayList(u8){};
    defer string_writer.deinit(allocator);

    var writer = string_writer.writer(allocator).any();
    try serializeToWriter(bindings, &writer, allocator);
    return try string_writer.toOwnedSlice(allocator);
}

/// Alias for serializeToSlice for convenience
pub const serializeToString = serializeToSlice;

/// Deserialize input bindings from a string (alias for deserializeFromSlice)
pub const deserializeFromString = deserializeFromSlice;

/// Deserialize input bindings from a slice
pub fn deserializeFromSlice(json_data: []const u8, allocator: std.mem.Allocator) !InputBindings {
    // Parse JSON directly from slice
    var parsed = std.json.parseFromSlice(BindingsFileJson, allocator, json_data, .{}) catch |err| {
        switch (err) {
            error.SyntaxError, error.UnexpectedToken => return SerializationError.InvalidFormat,
            else => return err,
        }
    };
    defer parsed.deinit();

    const file_json = parsed.value;

    // Check version
    if (file_json.version != SERIALIZATION_VERSION) {
        return SerializationError.UnsupportedVersion;
    }

    // Create bindings collection
    var bindings = InputBindings.init(allocator);
    errdefer bindings.deinit();

    // Parse each binding
    for (file_json.bindings) |binding_json| {
        // Parse the chord
        const chord = try InputChord.fromString(binding_json.chord, allocator) orelse return SerializationError.InvalidChord;

        // Create action (init will duplicate the strings)
        const action = try InputAction.init(allocator, binding_json.action_name, binding_json.action_description);

        // Create binding
        var binding = InputBinding.init(chord, action);
        binding.enabled = binding_json.enabled;

        try bindings.addBinding(binding);
    }

    return bindings;
}

/// Validate that a set of bindings doesn't have conflicts
pub fn validateBindings(bindings: *const InputBindings, allocator: std.mem.Allocator) ![]const []const u8 {
    var conflicts = std.ArrayList([]const u8){};

    const all_bindings = bindings.getAllBindings();

    // Check for exact duplicates and chord conflicts
    for (all_bindings, 0..) |*binding_a, i| {
        for (all_bindings[i + 1 ..], i + 1..) |*binding_b, j| {
            _ = j;

            // Check if chords are identical
            if (binding_a.chord.matches(binding_b.chord.keys.items)) {
                const chord_str = try binding_a.chord.toString(allocator);
                defer allocator.free(chord_str);
                const conflict = try std.fmt.allocPrint(allocator, "Duplicate chord: '{s}' used by both '{s}' and '{s}'", .{ chord_str, binding_a.action.name, binding_b.action.name });
                try conflicts.append(allocator, conflict);
            }
        }
    }

    return conflicts.toOwnedSlice(allocator);
}

/// Print bindings in a human-readable format
pub fn printBindings(bindings: *const InputBindings, writer: anytype, allocator: std.mem.Allocator) !void {
    try writer.writeAll("Input Bindings:\n");
    try writer.writeAll("===============\n\n");

    const all_bindings = bindings.getAllBindings();
    if (all_bindings.len == 0) {
        try writer.writeAll("No bindings configured.\n");
        return;
    }

    for (all_bindings) |*binding| {
        const chord_str = try binding.chord.toString(allocator);
        defer allocator.free(chord_str);

        const status = if (binding.enabled) "Enabled" else "Disabled";

        try writer.print("{s:20} -> {s:30} ({s})\n", .{ chord_str, binding.action.name, status });

        if (binding.action.description.len > 0) {
            try writer.print("{s:20}    {s}\n", .{ "", binding.action.description });
        }
        try writer.writeAll("\n");
    }

    try writer.flush();
}
