const std = @import("std");
const Allocator = std.mem.Allocator;
const CRLF = @import("main.zig").CRLF;

pub fn Http(comptime ReaderType: type) type {
    return struct {
        pub const Request = @import("Request.zig").Request(ReaderType);
        pub const Response = @import("Response.zig");

        pub const HandlerFnType = *const fn (allocator: Allocator, req: *const Request) anyerror!*Response;

        const Self = @This();
        routes: std.StringHashMap(HandlerFnType),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .routes = std.StringHashMap(HandlerFnType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.routes.iterator();
            while (it.next()) |item| {
                self.allocator.free(item.key_ptr.*);
                // no need to free value, as it is fn pointer
                // self.allocator.free(item.value_ptr.*);
            }
            self.routes.deinit();
        }

        pub fn get(self: *Self, path: []const u8, handlerFn: HandlerFnType) !void {
            try self.routes.put(try self.allocator.dupe(u8, path), handlerFn);
        }

        pub fn start(self: *Self) !void {
            const address = try std.net.Address.resolveIp("127.0.0.1", 4221);
            var listener = try address.listen(.{
                .reuse_address = true,
            });
            defer listener.deinit();

            while (true) {
                const conn = try listener.accept();
                defer conn.stream.close();
                try self.handleConnection(conn);
                break;
            }
        }

        pub fn handleConnection(self: *Self, conn: std.net.Server.Connection) !void {
            const reader = conn.stream.reader();
            var request = try Request.init(self.allocator, reader);
            defer request.deinit();

            var it = self.routes.iterator();
            var found = false;
            while (it.next()) |route| {
                const path_params = try findMatch(self.allocator, route.key_ptr.*, request.path) orelse continue;

                found = true;
                request.path_params = path_params;

                const resp = try route.value_ptr.*(self.allocator, &request);
                defer resp.deinit();
                try Self.writeToConn(self.allocator, conn, &request, resp);
            }
            if (!found) {
                _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
            }
        }

        pub fn writeToConn(
            allocator: Allocator,
            conn: std.net.Server.Connection,
            req: *const Request,
            res: *const Response,
        ) !void {
            _ = req;
            var resp_lines = std.ArrayList([]const u8).init(allocator);
            defer {
                for (resp_lines.items) |line| {
                    allocator.free(line);
                }
                resp_lines.deinit();
            }

            // Status Line
            // creating this on allocator so we can free them
            // Is there better way to do this?
            // Maybe this can be on stack, as these are not needed outside of this frame
            try resp_lines.append(try std.fmt.allocPrint(allocator, "HTTP/1.1 {d} {s}{s}", .{
                res.status_code,
                statusCode(res.status_code),
                CRLF,
            }));
            try resp_lines.append(try std.fmt.allocPrint(allocator, "Content-Length: {d}{s}", .{ res.body.len, CRLF }));
            try resp_lines.append(try std.fmt.allocPrint(allocator, "Content-Type: {s}{s}", .{
                res.headers.get("Content-Type") orelse "text/plain",
                CRLF,
            }));

            // Body
            try resp_lines.append(try std.fmt.allocPrint(allocator, "{s}{s}", .{
                CRLF,
                if (res.body.len > 0) res.body else "",
            }));

            const resp_bytes = try std.mem.join(allocator, "", resp_lines.items);
            defer allocator.free(resp_bytes);
            _ = try conn.stream.write(resp_bytes);

            return;
        }
    };
}

pub fn findMatch(
    allocator: Allocator,
    pattern_path: []const u8,
    actual_path: []const u8,
) !?std.StringHashMap([]const u8) {
    var pattern_path_slice = std.mem.splitSequence(u8, pattern_path, "/");
    var actual_path_slice = std.mem.splitSequence(u8, actual_path, "/");

    var path_params = std.StringHashMap([]const u8).init(allocator);
    var found: bool = true;
    while (true) {
        const p_value_opt = pattern_path_slice.next();
        const a_value_opt = actual_path_slice.next();

        if (p_value_opt == null and a_value_opt == null) {
            break;
        }
        if (p_value_opt == null or a_value_opt == null) {
            // One of the iterator terminated early
            found = false;
            break;
        }
        const p_value = p_value_opt.?;
        const a_value = a_value_opt.?;

        if (std.mem.startsWith(u8, p_value, "{") and std.mem.endsWith(u8, p_value, "}")) {
            if (a_value.len <= 0) {
                // If actual path doesn't have any content, then pattern doesn't match
                // This is when path ends with /
                found = false;
                break;
            }
            try path_params.put(
                try allocator.dupe(u8, p_value[1..(p_value.len - 1)]),
                try allocator.dupe(u8, a_value),
            );
            continue;
        }
        if (!std.mem.eql(u8, p_value, a_value)) {
            found = false;
            break;
        }
    }
    if (!found) {
        // freeing hashmap here because we are not returning this state outside
        var it = path_params.iterator();
        while (it.next()) |item| {
            allocator.free(item.key_ptr.*);
            allocator.free(item.value_ptr.*);
        }
        path_params.deinit();
        return null;
    }

    return path_params;
}

fn statusCode(code: u9) []const u8 {
    return switch (code) {
        200 => "OK",
        201 => "Created",
        400 => "Bad Request",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => unreachable,
    };
}

test "find match" {
    const testing = std.testing;
    const allocator = std.testing.allocator;

    try testing.expect((try findMatch(allocator, "", "")) != null);
    try testing.expect((try findMatch(allocator, "/", "/")) != null);
    try testing.expect((try findMatch(allocator, "", "/")) == null);

    try testing.expect((try findMatch(allocator, "/hello", "/hello")) != null);
    try testing.expect((try findMatch(allocator, "/hello", "/hello/notmatch")) == null);

    var p1 = try findMatch(allocator, "/hello/{slug}", "/hello/value1");
    defer deinit(allocator, &(p1.?));

    try testing.expect(p1 != null);
    try testing.expect(p1.?.get("slug") != null);
    try testing.expectEqualSlices(u8, p1.?.get("slug").?, "value1");

    var p2 = try findMatch(allocator, "/hello/{slug}/test", "/hello/value1/test");
    defer deinit(allocator, &(p2.?));

    try testing.expect(p2 != null);
    try testing.expect(p2.?.get("slug") != null);
    try testing.expectEqualSlices(u8, p2.?.get("slug").?, "value1");

    var p3 = try findMatch(allocator, "/hello/{slug}/test/{slug2}", "/hello/value1/test/value2");
    defer deinit(allocator, &(p3.?));

    try testing.expect(p3 != null);
    try testing.expect(p3.?.get("slug") != null);
    try testing.expectEqualSlices(u8, p3.?.get("slug").?, "value1");
    try testing.expect(p3.?.get("slug2") != null);
    try testing.expectEqualSlices(u8, p3.?.get("slug2").?, "value2");

    const p4 = try findMatch(allocator, "/hello/{slug}/test/{slug2}", "/hello/value1/test/");
    try testing.expect(p4 == null);

    var p5 = try findMatch(allocator, "/hello/{slug}/{slug2}", "/hello/value1/value2");
    defer deinit(allocator, &(p5.?));

    try testing.expect(p5 != null);
    try testing.expect(p5.?.get("slug") != null);
    try testing.expectEqualSlices(u8, p5.?.get("slug").?, "value1");
    try testing.expect(p5.?.get("slug2") != null);
    try testing.expectEqualSlices(u8, p5.?.get("slug2").?, "value2");
}

fn deinit(allocator: Allocator, p1: *std.StringHashMap([]const u8)) void {
    var it = p1.iterator();
    while (it.next()) |item| {
        allocator.free(item.key_ptr.*);
        allocator.free(item.value_ptr.*);
    }
    p1.deinit();
}
