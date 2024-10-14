const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.net.Stream.Reader;

const Request = @This();

method: []const u8,
path: []const u8,
headers: std.StringHashMap([]const u8),
body: []u8,
allocator: Allocator,

pub fn parse(allocator: Allocator, reader: Reader) !Request {
    const delimiter = '\n';

    var buf: [1024]u8 = undefined;
    const status_line = Request.readStatusLine((try reader.readUntilDelimiterOrEof(&buf, delimiter)).?);

    return Request{
        .method = try allocator.dupe(u8, status_line.method),
        .path = try allocator.dupe(u8, status_line.path),
        .headers = std.StringHashMap([]const u8).init(allocator),
        .body = try allocator.alloc(u8, 1),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Request) void {
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
