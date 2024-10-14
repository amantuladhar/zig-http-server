const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Request(comptime ReaderType: type) type {
    comptime {
        validateComptime(ReaderType);
    }
    return struct {
        const Self = @This();
        const Reader = ReaderType;

        method: []const u8,
        path: []const u8,
        headers: std.StringHashMap([]const u8),
        body: []u8,
        allocator: Allocator,

        pub fn parse(allocator: Allocator, reader: Reader) !Self {
            const delimiter = '\n';

            var buf: [1024]u8 = undefined;
            const status_line = Self.readStatusLine((try reader.readUntilDelimiterOrEof(&buf, delimiter)).?);

            return Self{
                .method = try allocator.dupe(u8, status_line.method),
                .path = try allocator.dupe(u8, status_line.path),
                .headers = std.StringHashMap([]const u8).init(allocator),
                .body = try allocator.alloc(u8, 1),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.method);
            self.allocator.free(self.path);
            self.allocator.free(self.body);
            var header_it = self.headers.iterator();
            while (header_it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.headers.deinit();
        }

        fn readStatusLine(line: []const u8) struct { method: []const u8, path: []const u8 } {
            var iter = std.mem.split(u8, line, " ");
            const method = iter.next() orelse @panic("Request method not found");
            const path = iter.next() orelse @panic("Request path not found");
            return .{
                .method = method,
                .path = path,
            };
        }
    };
}

fn validateComptime(comptime ReaderType: type) void {
    comptime {
        if (!@hasDecl(ReaderType, "readUntilDelimiter")) {
            @compileError("Request reader type must have readUntilDelimiter method");
        }
        if (!@hasDecl(ReaderType, "readUntilDelimiterAlloc")) {
            @compileError("Request reader type must have readUntilDelimiterAlloc method");
        }
        if (!@hasDecl(ReaderType, "readUntilDelimiterOrEof")) {
            @compileError("Request reader type must have readUntilDelimiterOrEof method");
        }
        if (!@hasDecl(ReaderType, "readUntilDelimiterOrEofAlloc")) {
            @compileError("Request reader type must have readUntilDelimiterOrEofAlloc method");
        }
    }
}

test "Request allocations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "GET /path HTTP/1.1\n";
    var bf = std.io.fixedBufferStream(input);
    const reader = bf.reader();

    var request = try Request(@TypeOf(reader)).parse(allocator, reader);
    defer request.deinit();

    try testing.expect(std.mem.eql(u8, request.method, "GET"));
    try testing.expect(std.mem.eql(u8, request.path, "/path"));
}
