const std = @import("std");
const Allocator = std.mem.Allocator;
const CRLF = @import("main.zig").CRLF;

pub fn Http(comptime ReaderType: type) type {
    return struct {
        pub const Request = @import("Request.zig").Request(ReaderType);
        pub const Response = @import("Response.zig");

        pub const HandlerFnType = *const fn (allocator: Allocator, req: Request) anyerror!*Response;

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
                self.allocator.free(item.value_ptr.*);
            }
            self.routes.deinit();
        }

        pub fn get(self: *Self, path: []const u8, handlerFn: HandlerFnType) !void {
            try self.routes.put(try self.allocator.dupe(u8, path), handlerFn);
        }

        pub fn start(self: *Self, listener: *std.net.Server) !void {
            while (true) {
                const conn = try listener.accept();
                defer conn.stream.close();
                try self.handleConnection(conn);
            }
        }

        pub fn handleConnection(self: *Self, conn: std.net.Server.Connection) !void {
            const reader = conn.stream.reader();
            var request = try Request.parse(self.allocator, reader);
            defer request.deinit();

            if (self.routes.get(request.path)) |handlerFn| {
                const resp = try handlerFn(self.allocator, request);
                defer resp.deinit();
                try Self.writeToConn(self.allocator, conn, &request, resp);
            } else {
                std.debug.print("No mapping found\n", .{});
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
            _ = try conn.stream.write(resp_bytes);

            return;
        }
    };
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
