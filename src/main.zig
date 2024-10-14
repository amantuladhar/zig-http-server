const std = @import("std");
const Request = @import("Request.zig");
const net = std.net;
const Allocator = std.mem.Allocator;
const Connection = std.net.Server.Connection;

const CRLF = "\r\n";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const conn = try listener.accept();
        defer conn.stream.close();
        try stdout.print("client connected!\n", .{});
        try handleConnection(allocator, conn);
    }
}

fn handleConnection(allocator: Allocator, conn: Connection) !void {
    var request = try Request.parse(allocator, conn.stream.reader());
    defer request.deinit();

    if (std.mem.eql(u8, request.path, "/")) {
        _ = try conn.stream.write("HTTP/1.1 200 OK\r\n\r\n");
        return;
    }

    if (std.mem.startsWith(u8, request.path, "/echo/")) {
        const slug = std.mem.trimLeft(u8, request.path, "/echo/");

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
        try resp_lines.append(try allocator.dupe(u8, "HTTP/1.1 200 OK"));
        try resp_lines.append(try allocator.dupe(u8, CRLF));

        const buf = try allocator.alloc(u8, 1024);

        const cl_header = try std.fmt.bufPrint(buf, "Content-Length: {d}{s}", .{ slug.len, CRLF });
        try resp_lines.append(try allocator.dupe(u8, cl_header));

        const ct_header = try std.fmt.bufPrint(buf, "Content-Type: {s}{s}", .{ "text/plain", CRLF });
        try resp_lines.append(try allocator.dupe(u8, ct_header));

        // Body
        try resp_lines.append(try allocator.dupe(u8, CRLF));
        try resp_lines.append(try allocator.dupe(u8, slug));

        const final_reqponse = try std.mem.join(allocator, "", resp_lines.items);
        _ = try conn.stream.write(final_reqponse);

        return;
    }

    _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
}
