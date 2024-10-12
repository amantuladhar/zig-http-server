const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        var conn = try listener.accept();
        defer conn.stream.close();
        try stdout.print("client connected!", .{});

        var buf: [1028]u8 = undefined;
        const read_count = try conn.stream.read(&buf);
        try stdout.print("Read Count {}\nContent\n{s}\n", .{ read_count, buf[0..read_count] });
        _ = try conn.stream.write("HTTP/1.1 200 OK\r\n\r\n");
    }
}
