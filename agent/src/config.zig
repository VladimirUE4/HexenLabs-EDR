const std = @import("std");
const fs = std.fs;
const builtin = @import("builtin");

pub const Config = struct {
    agent_id: []const u8,
    agent_name: []const u8,
    agent_group: []const u8,
    server_ip: []const u8,
    server_port: u16,
    heartbeat_interval_ns: i128,
    polling_interval_ns: i128,
    config_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.agent_id);
        self.allocator.free(self.agent_name);
        self.allocator.free(self.agent_group);
        self.allocator.free(self.server_ip);
        self.allocator.free(self.config_path);
    }
};

// Load or create agent configuration
pub fn loadConfig(allocator: std.mem.Allocator, name: ?[]const u8, group: ?[]const u8, server_ip: ?[]const u8) !Config {
    const uid = std.os.linux.getuid();
    const config_dir = try std.fmt.allocPrint(allocator, "/tmp/hexen-{d}", .{uid});
    defer allocator.free(config_dir);

    // Ensure config directory exists
    fs.cwd().makeDir(config_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const config_file_path = try std.fmt.allocPrint(allocator, "{s}/agent.json", .{config_dir});
    errdefer allocator.free(config_file_path);

    // Try to load existing config
    const config_file = fs.cwd().openFile(config_file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // Create new config with UUID
            return try createNewConfig(allocator, config_file_path, name, group, server_ip);
        },
        else => return err,
    };
    defer config_file.close();

    // Read existing config
    const file_size = try config_file.getEndPos();
    const config_data = try allocator.alloc(u8, file_size);
    defer allocator.free(config_data);
    _ = try config_file.readAll(config_data);

    // Parse JSON (simplified - use std.json for production)
    var agent_id: ?[]const u8 = null;
    var agent_name: ?[]const u8 = null;
    var agent_group: ?[]const u8 = null;
    var stored_server_ip: ?[]const u8 = null;

    // Simple JSON parsing (look for "agent_id":"...")
    if (std.mem.indexOf(u8, config_data, "\"agent_id\"")) |_| {
        if (extractJsonString(config_data, "agent_id")) |id| {
            agent_id = try allocator.dupe(u8, id);
        }
    }
    if (std.mem.indexOf(u8, config_data, "\"agent_name\"")) |_| {
        if (extractJsonString(config_data, "agent_name")) |n| {
            agent_name = try allocator.dupe(u8, n);
        }
    }
    if (std.mem.indexOf(u8, config_data, "\"agent_group\"")) |_| {
        if (extractJsonString(config_data, "agent_group")) |g| {
            agent_group = try allocator.dupe(u8, g);
        }
    }
    if (std.mem.indexOf(u8, config_data, "\"server_ip\"")) |_| {
        if (extractJsonString(config_data, "server_ip")) |ip| {
            stored_server_ip = try allocator.dupe(u8, ip);
        }
    }

    // Use provided values or defaults
    const final_name = name orelse agent_name orelse "unnamed";
    const final_group = group orelse agent_group orelse "default";
    const final_server_ip = server_ip orelse stored_server_ip orelse "127.0.0.1";

    // Generate UUID if not exists
    const final_agent_id = agent_id orelse try generateUUID(allocator);

    // Update config file if parameters changed
    if (name != null or group != null or server_ip != null) {
        try saveConfig(allocator, config_file_path, final_agent_id, final_name, final_group, final_server_ip);
    }

    return Config{
        .agent_id = final_agent_id,
        .agent_name = try allocator.dupe(u8, final_name),
        .agent_group = try allocator.dupe(u8, final_group),
        .server_ip = try allocator.dupe(u8, final_server_ip),
        .server_port = 8443,
        .heartbeat_interval_ns = 10 * std.time.ns_per_s,
        .polling_interval_ns = 3 * std.time.ns_per_s,
        .config_path = config_file_path,
        .allocator = allocator,
    };
}

fn createNewConfig(allocator: std.mem.Allocator, config_path: []const u8, name: ?[]const u8, group: ?[]const u8, server_ip: ?[]const u8) !Config {
    const agent_id = try generateUUID(allocator);
    errdefer allocator.free(agent_id);

    const agent_name = name orelse "unnamed";
    const agent_group = group orelse "default";
    const final_server_ip = server_ip orelse "127.0.0.1";

    try saveConfig(allocator, config_path, agent_id, agent_name, agent_group, final_server_ip);

    return Config{
        .agent_id = agent_id,
        .agent_name = try allocator.dupe(u8, agent_name),
        .agent_group = try allocator.dupe(u8, agent_group),
        .server_ip = try allocator.dupe(u8, final_server_ip),
        .server_port = 8443,
        .heartbeat_interval_ns = 10 * std.time.ns_per_s,
        .polling_interval_ns = 3 * std.time.ns_per_s,
        .config_path = try allocator.dupe(u8, config_path),
        .allocator = allocator,
    };
}

fn saveConfig(allocator: std.mem.Allocator, config_path: []const u8, agent_id: []const u8, name: []const u8, group: []const u8, server_ip: []const u8) !void {
    const config_json = try std.fmt.allocPrint(
        allocator,
        "{{\"agent_id\":\"{s}\",\"agent_name\":\"{s}\",\"agent_group\":\"{s}\",\"server_ip\":\"{s}\",\"server_port\":8443}}",
        .{ agent_id, name, group, server_ip },
    );
    defer allocator.free(config_json);

    const file = try fs.cwd().createFile(config_path, .{});
    defer file.close();

    try file.writeAll(config_json);
    // Secure permissions
    _ = std.os.linux.fchmod(file.handle, 0o600);
}

fn generateUUID(allocator: std.mem.Allocator) ![]const u8 {
    var random_bytes: [16]u8 = undefined;
    const random_fd = try std.fs.cwd().openFile("/dev/urandom", .{});
    defer random_fd.close();
    _ = try random_fd.readAll(&random_bytes);

    // Format as UUID v4
    random_bytes[6] = (random_bytes[6] & 0x0f) | 0x40; // Version 4
    random_bytes[8] = (random_bytes[8] & 0x3f) | 0x80; // Variant

    const uuid_str = try std.fmt.allocPrint(
        allocator,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            random_bytes[0], random_bytes[1], random_bytes[2], random_bytes[3],
            random_bytes[4], random_bytes[5], random_bytes[6], random_bytes[7],
            random_bytes[8], random_bytes[9], random_bytes[10], random_bytes[11],
            random_bytes[12], random_bytes[13], random_bytes[14], random_bytes[15],
        },
    );

    return uuid_str;
}

fn extractJsonString(json: []const u8, field: []const u8) ?[]const u8 {
    const key_pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{field}) catch return null;
    defer std.heap.page_allocator.free(key_pattern);

    if (std.mem.indexOf(u8, json, key_pattern)) |start_idx| {
        const val_start = start_idx + key_pattern.len;
        if (std.mem.indexOfPos(u8, json, val_start, "\"")) |end_idx| {
            return json[val_start..end_idx];
        }
    }
    return null;
}

