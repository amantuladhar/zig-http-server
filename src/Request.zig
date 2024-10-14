const std = @import("std");
const Allocator = std.mem.Allocator;
const CRLF = @import("main.zig").CRLF;
const delimiter = '\n';

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
            const status_line = try Self.readStatusLine(allocator, reader);
            const headers = try Self.readHeader(allocator, reader);
            return Self{
                .method = status_line.method,
                .path = status_line.path,
                .headers = headers,
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

        fn readHeader(allocator: Allocator, reader: ReaderType) !std.StringHashMap([]const u8) {
            var headers = std.StringHashMap([]const u8).init(allocator);
            while (true) {
                const header_line = reader.readUntilDelimiterAlloc(allocator, delimiter, 512) catch |err| {
                    if (err == error.EndOfStream) {
                        break;
                    }
                    return err;
                };
                defer allocator.free(header_line);
                const line = std.mem.trimRight(u8, header_line, "\r");
                if (line.len == 0) {
                    break;
                }
                var it = std.mem.split(u8, line, ": ");
                const key = it.next() orelse @panic("Header key not present");
                const value = it.next() orelse @panic("Header value not present");
                // Duplicating this here because we remove key and value seperately when we deinit
                // Better way?
                try headers.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
            }
            return headers;
        }

        fn readStatusLine(allocator: Allocator, reader: ReaderType) !struct { method: []const u8, path: []const u8 } {
            const line = try reader.readUntilDelimiterAlloc(allocator, delimiter, 256);
            defer allocator.free(line);
            var iter = std.mem.split(u8, line, " ");
            // Duplicating here becuase freeing them separately makes more straight forward
            const method = try allocator.dupe(u8, iter.next() orelse @panic("Request method not found"));
            const path = try allocator.dupe(u8, iter.next() orelse @panic("Request path not found"));
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

    const input = "GET /path HTTP/1.1\r\nContent-Type: text/plain\r\nHost: test\r\n\r\n";
    var bf = std.io.fixedBufferStream(input);
    const reader = bf.reader();

    var request = try Request(@TypeOf(reader)).parse(allocator, reader);
    defer request.deinit();

    try testing.expect(std.mem.eql(u8, request.method, "GET"));
    try testing.expect(std.mem.eql(u8, request.path, "/path"));
}
