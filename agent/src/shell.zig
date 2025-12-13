const std = @import("std");

pub const ShellResult = struct {
    output: []const u8,
    exit_code: u8,
};

pub fn executeCommand(allocator: std.mem.Allocator, command: []const u8) !ShellResult {
    // Security: In a real EDR, we would be extremely careful here.
    // We execute via /bin/sh -c to allow piping and basic shell features.

    const argv = [_][]const u8{
        "/bin/sh",
        "-c",
        command,
    };

    std.debug.print("[Shell] Executing: /bin/sh -c \"{s}\"\n", .{command});

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const max_output_size = 5 * 1024 * 1024; // 5 MB limit

    const stdout = try child.stdout.?.readToEndAlloc(allocator, max_output_size);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, max_output_size);
    defer allocator.free(stderr);

    const term = try child.wait();

    var exit_code: u8 = 0;
    switch (term) {
        .Exited => |code| exit_code = code,
        else => exit_code = 255,
    }

    // Combine stdout and stderr if there was an error, or just return stdout
    if (exit_code != 0 and stderr.len > 0) {
        const combined = try std.fmt.allocPrint(allocator, "{s}\nSTDERR:\n{s}", .{ stdout, stderr });
        return ShellResult{
            .output = combined,
            .exit_code = exit_code,
        };
    }

    return ShellResult{
        .output = stdout,
        .exit_code = exit_code,
    };
}
