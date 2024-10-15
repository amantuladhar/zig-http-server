const std = @import("std");
const Http = @import("Http.zig").Http(std.net.Stream.Reader);
const net = std.net;
const posix = std.posix;
const os = std.os;
const Allocator = std.mem.Allocator;
const Connection = std.net.Server.Connection;

pub const CRLF = "\r\n";
// This is definitely not a right approach, but can't find alternative at the moment?
// Don't like global variable, but how do call deinit
// when we do graceful shutdown
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();
var http = Http.init(alloc);

pub fn main() !void {
    try setupGracefulShutdown();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Logs from your program will appear here!\n", .{});

    try http.get("/", root);
    try http.get("/echo/{slug}", echo);
    try http.get("/user-agent", userAgent);
    try http.start();
}

fn root(allocator: Allocator, req: *const Http.Request) !*Http.Response {
    _ = req;
    const resp = try Http.Response.initOnHeap(allocator, 200, &[_]u8{});
    return resp;
}

fn echo(allocator: Allocator, req: *const Http.Request) !*Http.Response {
    const body = req.path_params.?.get("slug").?;
    const resp = try Http.Response.initOnHeap(allocator, 200, body);
    return resp;
}
fn userAgent(allocator: Allocator, req: *const Http.Request) !*Http.Response {
    const body = req.headers.get("User-Agent").?;
    const resp = try Http.Response.initOnHeap(allocator, 200, body);
    return resp;
}

pub fn sessionSignalHandler(i: c_int) callconv(.C) void {
    _ = i;
    http.deinit();
    const check = gpa.deinit();
    std.debug.print("\n🙏 Process exited. Stauts of leak = {any}\n", .{check});
    if (check == .leak) {
        @panic("🔴 Memory leak found!!!!!!!");
    }
}

// Still doesn't handle when app panics
fn setupGracefulShutdown() !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = &sessionSignalHandler },
        .mask = std.posix.empty_sigset,
        .flags = (posix.SA.SIGINFO | posix.SA.RESTART | posix.SA.RESETHAND),
    };
    try std.posix.sigaction(std.posix.SIG.INT, &act, null);
    try std.posix.sigaction(std.posix.SIG.TERM, &act, null);
}
