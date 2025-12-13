const std = @import("std");

pub const OsqueryResult = struct {
    output: []const u8,
    exit_code: u8,
};

pub fn executeQuery(allocator: std.mem.Allocator, query: []const u8) !OsqueryResult {
    // We assume 'osqueryi' is in the PATH or bundled with the agent
    // command: osqueryi --json "SELECT * FROM ..."

    const argv = [_][]const u8{
        "osqueryi",
        "--json",
        query,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Limit output size to avoid memory exhaustion on massive queries
    const max_output_size = 10 * 1024 * 1024; // 10 MB

    const stdout = try child.stdout.?.readToEndAlloc(allocator, max_output_size);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, max_output_size);
    defer allocator.free(stderr); // We might want to log stderr if it fails

    const term = try child.wait();

    var exit_code: u8 = 0;
    switch (term) {
        .Exited => |code| exit_code = code,
        else => exit_code = 255,
    }

    if (exit_code != 0) {
        // If it failed, maybe return stderr as output for debugging
        return OsqueryResult{
            .output = try std.fmt.allocPrint(allocator, "Error executing osquery: {s}", .{stderr}),
            .exit_code = exit_code,
        };
    }

    return OsqueryResult{
        .output = stdout,
        .exit_code = exit_code,
    };
}
