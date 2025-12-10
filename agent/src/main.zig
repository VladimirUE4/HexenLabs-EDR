const std = @import("std");
const net = std.net;
const osquery = @import("osquery.zig");

// Configuration
const SERVER_IP = "127.0.0.1";
const SERVER_PORT = 8080;
const AGENT_ID = "agent-linux-001";
const HEARTBEAT_INTERVAL_NS = 10 * std.time.ns_per_s;
const POLLING_INTERVAL_NS = 3 * std.time.ns_per_s;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("HexenLabs EDR Agent starting...\n", .{});

    // 1. Initialize Tools
    if (osquery.ensureInstalled(allocator)) |path| {
        allocator.free(path);
    } else |err| {
        std.debug.print("CRITICAL: Failed to install tools: {}\n", .{err});
        return;
    }

    std.debug.print("Agent Ready. ID: {s}\n", .{AGENT_ID});

    var last_heartbeat: i128 = 0;

    while (true) {
        const now = std.time.nanoTimestamp();

        // --- Task A: Heartbeat ---
        if (now - last_heartbeat > HEARTBEAT_INTERVAL_NS) {
            const payload = "{\"ID\": \"" ++ AGENT_ID ++ "\", \"Hostname\": \"linux-dev\", \"OsType\": \"linux\", \"IpAddress\": \"127.0.0.1\"}";

            // Raw HTTP POST
            if (sendHttp(allocator, .POST, "/api/heartbeat", payload)) |response| {
                defer allocator.free(response);
                std.debug.print("Heartbeat OK.\n", .{});
                last_heartbeat = now;
            } else |err| {
                std.debug.print("Heartbeat failed: {}\n", .{err});
            }
        }

        // --- Task B: Poll for Tasks ---
        {
            const path = "/api/agents/" ++ AGENT_ID ++ "/tasks/next";
            if (sendHttp(allocator, .GET, path, null)) |response| {
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
                            const res_path = try std.fmt.allocPrint(allocator, "/api/agents/{s}/tasks/{s}/result", .{ AGENT_ID, task_id });
                            defer allocator.free(res_path);

                            // Construct JSON with B64
                            const res_payload = try std.fmt.allocPrint(allocator, "{{\"output_b64\": \"{s}\", \"error\": \"\"}}", .{b64_buf});
                            defer allocator.free(res_payload);

                            if (sendHttp(allocator, .POST, res_path, res_payload)) |res_ack| {
                                allocator.free(res_ack);
                            } else |_| {}
                        }
                    }
                }
            } else |err| {
                std.debug.print("Poll failed: {}\n", .{err});
            }
        }

        // Busy Wait Loop
        var i: u64 = 0;
        while (i < 50000000) : (i += 1) {
            std.mem.doNotOptimizeAway(i);
        }
    }
}

const Method = enum { GET, POST };

fn sendHttp(allocator: std.mem.Allocator, method: Method, path: []const u8, body: ?[]const u8) ![]u8 {
    const peer = try net.Address.parseIp4(SERVER_IP, SERVER_PORT);
    const stream = try net.tcpConnectToAddress(peer);
    defer stream.close();

    const method_str = switch (method) {
        .GET => "GET",
        .POST => "POST",
    };

    const content_len = if (body) |b| b.len else 0;

    // Send Request (Manual write to avoid writer() API flux)
    // const writer_obj = stream.writer();

    const header = try std.fmt.allocPrint(allocator, "{s} {s} HTTP/1.0\r\nHost: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ method_str, path, SERVER_IP, content_len });
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
