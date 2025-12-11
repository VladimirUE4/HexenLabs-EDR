const std = @import("std");
const net = std.net;
const osquery = @import("osquery.zig");
const config = @import("config.zig");
const validation = @import("validation.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("HexenLabs EDR Agent starting...\n", .{});

    // Parse command line arguments
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var agent_name: ?[]const u8 = null;
    var agent_group: ?[]const u8 = null;
    var server_ip: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--name") and i + 1 < args.len) {
            agent_name = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--group") and i + 1 < args.len) {
            agent_group = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--server") and i + 1 < args.len) {
            server_ip = args[i + 1];
            i += 1;
        }
    }

    // Load configuration
    var cfg = try config.loadConfig(allocator, agent_name, agent_group, server_ip);
    defer cfg.deinit();

    std.debug.print("Agent Config:\n", .{});
    std.debug.print("  ID: {s}\n", .{cfg.agent_id});
    std.debug.print("  Name: {s}\n", .{cfg.agent_name});
    std.debug.print("  Group: {s}\n", .{cfg.agent_group});
    std.debug.print("  Server: {s}:{d}\n", .{ cfg.server_ip, cfg.server_port });

    // 1. Initialize Tools
    if (osquery.ensureInstalled(allocator)) |path| {
        allocator.free(path);
    } else |err| {
        std.debug.print("CRITICAL: Failed to install tools: {}\n", .{err});
        return;
    }

    std.debug.print("Agent Ready. ID: {s}\n", .{cfg.agent_id});

    var last_heartbeat: i128 = 0;

    while (true) {
        const now = std.time.nanoTimestamp();

        // --- Task A: Heartbeat ---
        if (now - last_heartbeat > cfg.heartbeat_interval_ns) {
            const hostname = std.os.getenv("HOSTNAME") orelse "unknown";
            const payload = try std.fmt.allocPrint(
                allocator,
                "{{\"ID\":\"{s}\",\"Hostname\":\"{s}\",\"OsType\":\"linux\",\"IpAddress\":\"127.0.0.1\",\"Name\":\"{s}\",\"Group\":\"{s}\"}}",
                .{ cfg.agent_id, hostname, cfg.agent_name, cfg.agent_group },
            );
            defer allocator.free(payload);

            // Raw HTTP POST
            if (sendHttp(allocator, cfg.server_ip, cfg.server_port, .POST, "/api/heartbeat", payload)) |response| {
                defer allocator.free(response);
                std.debug.print("Heartbeat OK.\n", .{});
                last_heartbeat = now;
            } else |err| {
                std.debug.print("Heartbeat failed: {}\n", .{err});
            }
        }

        // --- Task B: Poll for Tasks ---
        {
            const path = try std.fmt.allocPrint(allocator, "/api/agents/{s}/tasks/next", .{cfg.agent_id});
            defer allocator.free(path);

            if (sendHttp(allocator, cfg.server_ip, cfg.server_port, .GET, path, null)) |response| {
                defer allocator.free(response);

                // Parse Body (Find \r\n\r\n)
                if (std.mem.indexOf(u8, response, "\r\n\r\n")) |body_start| {
                    const body = response[body_start + 4 ..];
                    if (body.len > 0) {
                        std.debug.print("Received Task: {s}\n", .{body});

                        // Extract Payload
                        if (getJsonField(body, "Payload")) |query| {
                            // Extract ID
                            const task_id = getJsonField(body, "ID") orelse "unknown";

                            // VALIDATE QUERY BEFORE EXECUTION
                            validation.validateOsqueryQuery(query) catch |err| {
                                std.debug.print("Query validation failed: {}\n", .{err});
                                // Send error result
                                const res_path = try std.fmt.allocPrint(allocator, "/api/agents/{s}/tasks/{s}/result", .{ cfg.agent_id, task_id });
                                defer allocator.free(res_path);
                                const error_payload = try std.fmt.allocPrint(allocator, "{{\"output_b64\":\"\",\"error\":\"Query validation failed: {s}\"}}", .{@errorName(err)});
                                defer allocator.free(error_payload);
                                _ = sendHttp(allocator, cfg.server_ip, cfg.server_port, .POST, res_path, error_payload) catch {};
                                continue;
                            };

                            std.debug.print("Executing Osquery: {s}\n", .{query});

                            // Execute
                            const exec_res = osquery.executeQuery(allocator, query) catch {
                                // ignore error for loop
                                continue;
                            };
                            defer allocator.free(exec_res.output);

                            std.debug.print("Result: {s}\n", .{exec_res.output});

                            // Base64 Encode output to avoid JSON escaping hell manually
                            const b64_len = std.base64.standard.Encoder.calcSize(exec_res.output.len);
                            const b64_buf = try allocator.alloc(u8, b64_len);
                            defer allocator.free(b64_buf);
                            _ = std.base64.standard.Encoder.encode(b64_buf, exec_res.output);

                            // Send Result (POST)
                            const res_path = try std.fmt.allocPrint(allocator, "/api/agents/{s}/tasks/{s}/result", .{ cfg.agent_id, task_id });
                            defer allocator.free(res_path);

                            // Construct JSON with B64
                            const res_payload = try std.fmt.allocPrint(allocator, "{{\"output_b64\": \"{s}\", \"error\": \"\"}}", .{b64_buf});
                            defer allocator.free(res_payload);

                            if (sendHttp(allocator, cfg.server_ip, cfg.server_port, .POST, res_path, res_payload)) |res_ack| {
                                allocator.free(res_ack);
                            } else |_| {}
                        }
                    }
                }
            } else |err| {
                std.debug.print("Poll failed: {}\n", .{err});
            }
        }

        // Sleep instead of busy wait
        std.time.sleep(cfg.polling_interval_ns);
    }
}

const Method = enum { GET, POST };

fn sendHttp(allocator: std.mem.Allocator, server_ip: []const u8, server_port: u16, method: Method, path: []const u8, body: ?[]const u8) ![]u8 {
    const peer = try net.Address.parseIp4(server_ip, server_port);
    const stream = try net.tcpConnectToAddress(peer);
    defer stream.close();

    const method_str = switch (method) {
        .GET => "GET",
        .POST => "POST",
    };

    const content_len = if (body) |b| b.len else 0;

    // Send Request (Manual write to avoid writer() API flux)
    // const writer_obj = stream.writer();

    const header = try std.fmt.allocPrint(allocator, "{s} {s} HTTP/1.0\r\nHost: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ method_str, path, server_ip, content_len });
    defer allocator.free(header);

    try stream.writeAll(header);

    if (body) |b| {
        try stream.writeAll(b);
    }

    // Read Response loop
    var read_buf: [4096]u8 = undefined;
    var list = std.ArrayList(u8).initCapacity(allocator, 1024) catch unreachable;
    // defer list.deinit(); // We return the slice, caller frees. But wait, we return []u8.
    // If we return list.toOwnedSlice(), we are good.

    // Create reader
    // var r = stream.reader(&read_buf); // This reader struct has .read()
    // Manual read loop using stream.read() directly is safer if reader() API is weird

    while (true) {
        const n = try stream.read(&read_buf);
        if (n == 0) break;
        try list.appendSlice(allocator, read_buf[0..n]);
    }

    return list.toOwnedSlice(allocator);
}

// Simple JSON string extractor (Fragile but works for known format)
fn getJsonField(json: []const u8, field: []const u8) ?[]const u8 {
    // Look for "field":"value"
    // "Payload":"SELECT..."
    // const search = "\"" ++ field ++ "\":\"";

    // var it = std.mem.window(u8, json, field.len + 3, 1);
    // var index: usize = 0;
    // while (it.next()) |_| {
    //    index += 1;
    // }

    // Better:
    const key_pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{field}) catch return null;
    defer std.heap.page_allocator.free(key_pattern);

    if (std.mem.indexOf(u8, json, key_pattern)) |start_idx| {
        const val_start = start_idx + key_pattern.len;
        // Find closing quote
        // Handle escaped quotes? No, simplified.
        if (std.mem.indexOfPos(u8, json, val_start, "\"")) |end_idx| {
            return json[val_start..end_idx];
        }
    }
    return null;
}
