const std = @import("std");

// Whitelist of allowed osquery tables (security)
const ALLOWED_TABLES = [_][]const u8{
    "processes",
    "users",
    "listening_ports",
    "startup_items",
    "system_info",
    "os_version",
    "uptime",
    "memory_info",
    "cpu_info",
    "disk_info",
    "network_interfaces",
    "routes",
    "arp_cache",
    "interface_addresses",
    "interface_details",
    "process_open_sockets",
    "process_open_files",
    "process_memory_map",
    "process_env",
    "logged_in_users",
    "last",
    "shell_history",
    "sudoers",
    "groups",
    "etc_hosts",
    "etc_protocols",
    "etc_services",
    "mounts",
    "file_events",
    "process_events",
};

// Allowed SQL keywords (whitelist approach)
const ALLOWED_KEYWORDS = [_][]const u8{
    "SELECT",
    "FROM",
    "WHERE",
    "LIMIT",
    "ORDER",
    "BY",
    "ASC",
    "DESC",
    "AND",
    "OR",
    "NOT",
    "IN",
    "LIKE",
    "IS",
    "NULL",
    "COUNT",
    "DISTINCT",
};

pub const ValidationError = error{
    InvalidQuery,
    TableNotAllowed,
    DangerousKeyword,
    QueryTooLong,
    InvalidSyntax,
};

// Validate osquery SQL query
pub fn validateOsqueryQuery(query: []const u8) ValidationError!void {
    // Check length (prevent DoS)
    if (query.len > 10000) {
        return ValidationError.QueryTooLong;
    }

    // Convert to uppercase for keyword checking
    var upper_query = std.ArrayList(u8).init(std.heap.page_allocator);
    defer upper_query.deinit();
    for (query) |c| {
        upper_query.append(if (c >= 'a' and c <= 'z') c - 32 else c) catch return ValidationError.InvalidQuery;
    }
    const upper = upper_query.items;

    // Must start with SELECT
    if (!std.mem.startsWith(u8, std.mem.trim(u8, upper, " \t\n\r"), "SELECT")) {
        return ValidationError.InvalidSyntax;
    }

    // Check for dangerous keywords
    const dangerous = [_][]const u8{ "INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER", "EXEC", "EXECUTE", "TRUNCATE" };
    for (dangerous) |keyword| {
        if (std.mem.indexOf(u8, upper, keyword)) |_| {
            return ValidationError.DangerousKeyword;
        }
    }

    // Extract table name from "FROM table_name"
    if (std.mem.indexOf(u8, upper, "FROM")) |from_idx| {
        const after_from = upper[from_idx + 4..];
        const trimmed = std.mem.trim(u8, after_from, " \t\n\r");
        
        // Find table name (until space, semicolon, or WHERE)
        var table_end: usize = trimmed.len;
        if (std.mem.indexOf(u8, trimmed, " ")) |space_idx| {
            table_end = @min(table_end, space_idx);
        }
        if (std.mem.indexOf(u8, trimmed, ";")) |semi_idx| {
            table_end = @min(table_end, semi_idx);
        }
        if (std.mem.indexOf(u8, trimmed, "WHERE")) |where_idx| {
            table_end = @min(table_end, where_idx);
        }

        const table_name = std.mem.trim(u8, trimmed[0..table_end], " \t\n\r");
        
        // Check if table is in whitelist
        var found = false;
        for (ALLOWED_TABLES) |allowed| {
            var upper_allowed = try upperString(std.heap.page_allocator, allowed);
            defer std.heap.page_allocator.free(upper_allowed);
            if (std.mem.eql(u8, table_name, upper_allowed)) {
                found = true;
                break;
            }
        }

        if (!found) {
            return ValidationError.TableNotAllowed;
        }
    } else {
        return ValidationError.InvalidSyntax;
    }

    // Basic syntax check: balanced parentheses
    var paren_count: i32 = 0;
    for (query) |c| {
        switch (c) {
            '(' => paren_count += 1,
            ')' => paren_count -= 1,
            else => {},
        }
        if (paren_count < 0) {
            return ValidationError.InvalidSyntax;
        }
    }
    if (paren_count != 0) {
        return ValidationError.InvalidSyntax;
    }
}

// Helper to uppercase string (simplified)
fn upperString(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = if (c >= 'a' and c <= 'z') c - 32 else c;
    }
    return result;
}

