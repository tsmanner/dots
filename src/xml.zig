const std = @import("std");

pub fn LazyFormat(comptime in_format: []const u8, comptime Args: type) type {
    return struct {
        pub const fmt = in_format;
        args: Args,

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print(fmt, self.args);
        }
    };
}

pub fn lazy(comptime format: []const u8, args: anytype) LazyFormat(format, @TypeOf(args)) {
    return .{ .args = args };
}

fn isStr(comptime Type: type) bool {
    const info = @typeInfo(Type);
    if (info == .pointer) {
        const c_info = @typeInfo(info.pointer.child);
        // String literals are of type `*const [N:0]u8`
        return isStr(info.pointer.child) or (c_info == .int and c_info.int.signedness == .unsigned and c_info.int.bits == 8);
    } else if (info == .array) {
        const c_info = @typeInfo(info.array.child);
        return c_info == .int and c_info.int.signedness == .unsigned and c_info.int.bits == 8;
    } else {
        return false;
    }
}

pub const Document = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    tags: std.ArrayList([]const u8),
    format: Format,

    const Format = enum { pretty, compact };

    const preamble = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";

    pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer, format: Format) !Document {
        _ = try writer.write(Document.preamble);
        switch (format) {
            .pretty => try writer.writeByte('\n'),
            .compact => {},
        }
        return .{
            .allocator = allocator,
            .writer = writer,
            .tags = .empty,
            .format = format,
        };
    }

    fn printTagStart(self: *Document) !void {
        switch (self.format) {
            .pretty => {
                try self.printIndent();
            },
            .compact => {},
        }
        try self.writer.writeByte('<');
    }

    fn printTagAttrs(self: *Document, attrs: anytype) !void {
        const Attrs = @TypeOf(attrs);
        inline for (std.meta.fields(Attrs)) |field| {
            try self.writer.print(" {s}=\"", .{field.name});
            const attr = @field(attrs, field.name);
            // If it's a string, use {s}, otherwise use {}.
            if (comptime isStr(@TypeOf(attr))) {
                try self.writer.print("{s}", .{attr});
            } else if (comptime std.meta.hasMethod(@TypeOf(attr), "format")) {
                try self.writer.print("{f}", .{attr});
            } else {
                try self.writer.print("{}", .{attr});
            }
            try self.writer.writeByte('\"');
        }
    }

    fn printTagEnd(self: *Document) !void {
        try self.writer.writeByte('>');
        switch (self.format) {
            .pretty => try self.writer.writeByte('\n'),
            .compact => {},
        }
    }

    pub fn printIndent(self: *Document) !void {
        for (0..self.tags.items.len) |_| {
            _ = try self.writer.write("  ");
        }
    }

    pub fn open(self: *Document, tag: @TypeOf(.enum_literal), attrs: anytype) !void {
        try self.printTagStart();
        _ = try self.writer.write(@tagName(tag));
        try self.printTagAttrs(attrs);
        try self.printTagEnd();
        try self.tags.append(self.allocator, @tagName(tag));
    }

    pub fn close(self: *Document) !void {
        if (self.tags.pop()) |tag| {
            try self.printTagStart();
            try self.writer.print("/{s}", .{tag});
            try self.printTagEnd();
        } else {
            return error.NoTagsToClose;
        }
    }

    pub fn selfClose(self: *Document, tag: @TypeOf(.enum_literal), attrs: anytype) !void {
        try self.printTagStart();
        _ = try self.writer.write(@tagName(tag));
        try self.printTagAttrs(attrs);
        try self.writer.writeByte('/');
        try self.printTagEnd();
    }
};
