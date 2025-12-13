const std = @import("std");

pub fn ensureInstalled(allocator: std.mem.Allocator) ![]const u8 {
    // For now, assume osqueryi is in PATH or current dir
    // Real implementation would check/download it
    const path = try allocator.dupe(u8, "osqueryi");
    return path;
}

pub const OsqueryResult = struct {
    output: []const u8,
    exit_code: u8,
};

pub fn executeQuery(allocator: std.mem.Allocator, query: []const u8) !OsqueryResult {
    // Try to find osqueryd binary: first in bin/, then in PATH
    const osquery_path = blk: {
        const cwd = std.fs.cwd();
        if (cwd.openFile("bin/osqueryd", .{})) |file| {
            file.close();
            break :blk "bin/osqueryd";
        } else |_| {
            if (cwd.openFile("../bin/osqueryd", .{})) |file| {
                file.close();
                break :blk "../bin/osqueryd";
            } else |_| {
                // Fallback to PATH
                break :blk "osqueryd";
            }
        }
    };

    // Use osqueryd --S (shell mode) with --json, and pass query via stdin
    const argv = [_][]const u8{
        osquery_path,
        "--S",
        "--json",
    };

    std.debug.print("[Osquery] Executing: {s} --S --json (query via stdin)\n", .{osquery_path});

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.stdin_behavior = .Pipe;

    try child.spawn();

    // Write query to stdin with newline, then close to signal EOF
    if (child.stdin) |stdin| {
        // Add newline if not present
        const query_with_newline = if (query.len > 0 and query[query.len - 1] == '\n') query else blk: {
            const with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{query});
            break :blk with_newline;
        };
        defer if (query_with_newline.ptr != query.ptr) allocator.free(query_with_newline);

        _ = try stdin.write(query_with_newline);
        stdin.close();
    }
    // IMPORTANT: Set stdin to null so child.wait() doesn't try to close it again
    child.stdin = null;

    // Limit output size to avoid memory exhaustion on massive queries
    const max_output_size = 10 * 1024 * 1024; // 10 MB

    const stdout = try child.stdout.?.readToEndAlloc(allocator, max_output_size);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, max_output_size);
    defer allocator.free(stderr);

    const term = try child.wait();

    var exit_code: u8 = 0;
    switch (term) {
        .Exited => |code| exit_code = code,
        else => exit_code = 255,
    }

    if (exit_code != 0) {
        // If it failed, return stderr as output for debugging
        std.debug.print("[Osquery] Error (exit_code: {}): {s}\n", .{ exit_code, stderr });
        return OsqueryResult{
            .output = try std.fmt.allocPrint(allocator, "Error executing osquery (exit_code: {}): {s}", .{ exit_code, stderr }),
            .exit_code = exit_code,
        };
    }

    std.debug.print("[Osquery] Success: {} bytes output\n", .{stdout.len});

    return OsqueryResult{
        .output = stdout,
        .exit_code = exit_code,
    };
}
