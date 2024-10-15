const std = @import("std");
const Http = @import("Http.zig").Http(std.net.Stream.Reader);
const net = std.net;
const Allocator = std.mem.Allocator;
const Connection = std.net.Server.Connection;

pub const CRLF = "\r\n";

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        std.debug.print("Leaked Value {any}", .{check});
        if (check == .leak) {
            @panic("Memory leak found!!!!!!!");
        }
    }
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Logs from your program will appear here!\n", .{});

    var http = Http.init(allocator);
    try http.get("/", root);
    try http.get("/echo/{slug}", echo);
    try http.start();
}

fn root(allocator: Allocator, req: *const Http.Request) !*Http.Response {
    _ = req;
    const resp = try Http.Response.initOnHeap(allocator, 200, &[_]u8{});
    return resp;
}

fn echo(allocator: Allocator, req: *const Http.Request) !*Http.Response {
    const body = try allocator.dupe(u8, req.path_params.?.get("slug").?);
    const resp = try Http.Response.initOnHeap(allocator, 200, body);
    return resp;
}
