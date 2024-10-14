const std = @import("std");
const Allocator = std.mem.Allocator;
const Self = @This();

status_code: u9,
headers: std.StringHashMap([]const u8),
body: []u8,
allocator: Allocator,

pub fn init(allocator: Allocator, status_code: u9, body: []u8) !Self {
    return Self{
        .allocator = allocator,
        .status_code = status_code,
        .body = try allocator.dupe(u8, body),
        .headers = std.StringHashMap([]const u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.body);
    var it = self.headers.iterator();
    while (it.next()) |item| {
        self.allocator.free(item.key_ptr.*);
        self.allocator.free(item.value_ptr.*);
    }
    self.headers.deinit();
    self.allocator.destroy(self);
}

pub fn addHeader(self: *Self, key: []const u8, value: []const u8) void {
    try self.headers.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
}
