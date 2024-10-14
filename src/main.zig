const std = @import("std");
const Http = @import("Http.zig").Http(std.net.Stream.Reader);
const net = std.net;
const Allocator = std.mem.Allocator;
const Connection = std.net.Server.Connection;

pub const CRLF = "\r\n";

fn root(allocator: Allocator, req: Http.Request) !*Http.Response {
    _ = req;
    const resp = try allocator.create(Http.Response);
    resp.* = try Http.Response.init(allocator, 200, &[_]u8{});
    return resp;
}

fn echo(allocator: Allocator, req: Http.Request) !*Http.Response {
    const body = try allocator.dupe(u8, std.mem.trimLeft(u8, req.path, "/echo/"));
    const resp = try allocator.create(Http.Response);
    resp.* = try Http.Response.init(allocator, 200, body);
    return resp;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            @panic("Memory leak found!!!!!!!");
        }
    }
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try std.net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var http = Http.init(allocator);
    try http.get("/", root);
    try http.get("/echo/{slug}", echo);
    try http.start(&listener);

    // const address = try net.Address.resolveIp("127.0.0.1", 4221);
    // var listener = try address.listen(.{
    //     .reuse_address = true,
    // });
    // defer listener.deinit();

    // while (true) {
    //     const conn = try listener.accept();
    //     defer conn.stream.close();
    //     try stdout.print("client connected!\n", .{});
    //     try handleConnection(allocator, conn);
    // }
}

// fn handleConnection(allocator: Allocator, conn: Connection) !void {
//     const reader = conn.stream.reader();
//     var request = try Request(@TypeOf(reader)).parse(allocator, reader);
//     defer request.deinit();

//     if (std.mem.eql(u8, request.path, "/")) {
//         _ = try conn.stream.write("HTTP/1.1 200 OK\r\n\r\n");
//         return;
//     }

//     if (std.mem.startsWith(u8, request.path, "/echo/")) {
//         const slug = std.mem.trimLeft(u8, request.path, "/echo/");

//         var resp_lines = std.ArrayList([]const u8).init(allocator);
//         defer {
//             for (resp_lines.items) |line| {
//                 allocator.free(line);
//             }
//             resp_lines.deinit();
//         }

//         // Status Line
//         // creating this on allocator so we can free them
//         // Is there better way to do this?
//         // Maybe this can be on stack, as these are not needed outside of this frame
//         try resp_lines.append(try std.fmt.allocPrint(allocator, "{s}{s}", .{ "HTTP/1.1 200 OK", CRLF }));
//         try resp_lines.append(try std.fmt.allocPrint(allocator, "Content-Length: {d}{s}", .{ slug.len, CRLF }));
//         try resp_lines.append(try std.fmt.allocPrint(allocator, "Content-Type: {s}{s}", .{ "text/plain", CRLF }));

//         // Body
//         try resp_lines.append(try std.fmt.allocPrint(allocator, "{s}{s}", .{ CRLF, slug }));

//         const resp_bytes = try std.mem.join(allocator, "", resp_lines.items);
//         _ = try conn.stream.write(resp_bytes);

//         return;
//     }

//     _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
// }
