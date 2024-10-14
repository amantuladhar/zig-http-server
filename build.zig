const std = @import("std");

// Learn more about this file here: https://ziglang.org/learn/build-system
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // region Test Step
    const test_step = b.step("test", "Run all test");
    const src_dir = b.pathFromRoot("src");
    var dir = std.fs.openDirAbsolute(src_dir, .{ .iterate = true }) catch unreachable;
    defer dir.close();

    var walker = dir.walk(b.allocator) catch unreachable;
    defer walker.deinit();

    while (walker.next() catch unreachable) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".zig")) {
            const t = b.addTest(.{
                .root_source_file = b.path(b.pathJoin(&.{ "src", entry.path })),
                .target = target,
                .optimize = optimize,
            });
            const rt = b.addRunArtifact(t);
            test_step.dependOn(&rt.step);
        }
    }
    // endregion
}
