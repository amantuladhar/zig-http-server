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

    var args = try std.process.argsWithAllocator(alloc);
    _ = args.next(); // skip first param
    var directory: [256]u8 = [_]u8{0} ** 256;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directory")) {
            const value = args.next().?;
            @memcpy(directory[0..value.len], value);
        }
    }
    std.debug.print("{s}", .{directory});
    args.deinit();

    try http.get("/", root);
    try http.get("/echo/{slug}", echo);
    try http.get("/user-agent", userAgent);
    try http.get("/files/{path}", getFile);
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

fn getFile(allocator: Allocator, req: *const Http.Request) !*Http.Response {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip first param
    var directory: [256]u8 = [_]u8{0} ** 256;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directory")) {
            const value = args.next().?;
            @memcpy(directory[0..value.len], value);
        }
    }

    const path = req.path_params.?.get("path").?;
    var abs_path_buf: [1024]u8 = undefined;
    const abs_path = try std.fmt.bufPrint(&abs_path_buf, "/tmp/{s}/{s}", .{ directory, path });
    const ff = try std.fs.openFileAbsolute(abs_path, .{ .mode = .read_only });
    defer ff.close();
    const content = try ff.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    const resp = try Http.Response.initOnHeap(allocator, 200, content);
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
// TODO: Need to fix these problems
// Still doesn't handle when app panics
// When app is terminated - it hangs - but after cleanup is done
fn setupGracefulShutdown() !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = &sessionSignalHandler },
        .mask = std.posix.empty_sigset,
        .flags = (posix.SA.SIGINFO | posix.SA.RESTART | posix.SA.RESETHAND),
    };
    try std.posix.sigaction(std.posix.SIG.INT, &act, null);
    try std.posix.sigaction(std.posix.SIG.TERM, &act, null);
}
