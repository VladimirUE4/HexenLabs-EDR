const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;

// Embed the binary at compile time
const osquery_binary = @embedFile("assets/osqueryd");

pub const OsqueryResult = struct {
    output: []const u8,
    exit_code: u8,
};

// Ensure osquery is on disk and executable in a USER-WRITABLE location
pub fn ensureInstalled(allocator: std.mem.Allocator) ![]const u8 {
    // Strategy: Use XDG_RUNTIME_DIR or /tmp/hexen-<uid>/
    // This allows running without root.

    const uid = std.os.linux.getuid();
    const tmp_dir_name = try std.fmt.allocPrint(allocator, "/tmp/hexen-{d}", .{uid});
    defer allocator.free(tmp_dir_name);

    // Create base dir
    fs.cwd().makeDir(tmp_dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const bin_path_str = try std.fmt.allocPrint(allocator, "{s}/osqueryd", .{tmp_dir_name});
    // We keep the path allocated to return it

    const file = fs.cwd().createFile(bin_path_str, .{ .read = true }) catch |err| {
        // If file exists and is busy (running), we might fail.
        // Simple check: if exists, assume good? Or version check?
        // For MVP: Overwrite if possible, else skip.
        if (err == error.PathAlreadyExists) {
            // make executable just in case
            // return path
            return bin_path_str;
        }
        return err;
    };
    defer file.close();

    try file.writeAll(osquery_binary);

    // chmod +x
    const file_handle = file.handle;
    _ = std.os.linux.fchmod(file_handle, 0o700); // Only me

    return bin_path_str;
}

pub fn executeQuery(allocator: std.mem.Allocator, query: []const u8) !OsqueryResult {
    const binary_path = try ensureInstalled(allocator);
    defer allocator.free(binary_path);

    // Secure Paths for non-root execution
    const uid = std.os.linux.getuid();
    const pid_path = try std.fmt.allocPrint(allocator, "/tmp/hexen-{d}/osquery.pid", .{uid});
    const db_path = try std.fmt.allocPrint(allocator, "/tmp/hexen-{d}/osquery.db", .{uid});
    const sock_path = try std.fmt.allocPrint(allocator, "/tmp/hexen-{d}/osquery.sock", .{uid});
    defer allocator.free(pid_path);
    defer allocator.free(db_path);
    defer allocator.free(sock_path);

    // Flags to run as NON-ROOT user safely
    const argv = [_][]const u8{
        binary_path,
        "-S", // Shell mode
        "--json",
        "--pidfile",
        pid_path,
        "--database_path",
        db_path,
        "--extensions_socket",
        sock_path,
        "--config_path", "/dev/null", // No config file needed for ephemeral query
        "--logger_min_status", "1", // Reduce noise
        query,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const max_output_size = 50 * 1024 * 1024;

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
        return OsqueryResult{
            .output = try std.fmt.allocPrint(allocator, "Error (Exit {d}): {s}", .{ exit_code, stderr }),
            .exit_code = exit_code,
        };
    }

    return OsqueryResult{
        .output = stdout,
        .exit_code = exit_code,
    };
}
