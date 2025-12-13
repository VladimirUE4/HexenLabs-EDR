const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
});
const osquery = @import("osquery.zig");
const curl = @import("curl.zig");

// Configuration
const SERVER_URL_BASE = "https://127.0.0.1:8443"; // HTTPS Gateway Port
const AGENT_ID = "agent-linux-001";
const HEARTBEAT_INTERVAL_NS = 10 * std.time.ns_per_s;

// Cert Paths (Relative to CWD for dev, Absolute for prod)
const CA_PATH = "../pki/certs/ca.crt";
const CERT_PATH = "../pki/certs/agent.crt";
const KEY_PATH = "../pki/certs/agent.key";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("HexenLabs EDR Agent starting (mTLS with Libcurl)...\n", .{});

    // 1. Initialize Osquery
    if (osquery.ensureInstalled(allocator)) |path| {
        allocator.free(path);
    } else |err| {
        std.debug.print("CRITICAL: Failed to install tools: {}\n", .{err});
        return;
    }

    // 2. Initialize Curl with mTLS
    var client = curl.CurlClient.init(allocator, CA_PATH, CERT_PATH, KEY_PATH) catch |err| {
        std.debug.print("CRITICAL: Failed to init Curl: {}\n", .{err});
        return;
    };
    defer client.deinit();

    std.debug.print("Agent Ready & Secure. ID: {s}\n", .{AGENT_ID});

    var last_heartbeat: i128 = 0;

    while (true) {
        const now = std.time.nanoTimestamp();

        // --- Task A: Heartbeat ---
        if (now - last_heartbeat > HEARTBEAT_INTERVAL_NS) {
            const payload = "{\"ID\": \"" ++ AGENT_ID ++ "\", \"Hostname\": \"linux-dev\", \"OsType\": \"linux\", \"IpAddress\": \"127.0.0.1\"}";
            const url = SERVER_URL_BASE ++ "/api/heartbeat";

            // Null-terminate URL for C
            const url_c = try allocator.dupeZ(u8, url);
            defer allocator.free(url_c);

            if (client.request("POST", url_c, payload)) |_| {
                std.debug.print("Heartbeat OK (Secure).\n", .{});
                last_heartbeat = now;
            } else |err| {
                std.debug.print("Heartbeat failed: {}\n", .{err});
            }
        }

        // --- Task B: Poll for Tasks ---
        {
            const url_raw = try std.fmt.allocPrint(allocator, "{s}/api/agents/{s}/tasks/next", .{ SERVER_URL_BASE, AGENT_ID });
            defer allocator.free(url_raw);
            const url = try allocator.dupeZ(u8, url_raw);
            defer allocator.free(url);

            if (client.request("GET", url, null)) |response| {
                if (response.len > 0) {
                    std.debug.print("Received Task: {s}\n", .{response});

                    if (getJsonField(response, "Payload")) |query| {
                        const task_id = getJsonField(response, "ID") orelse "unknown";
                        std.debug.print("Executing Osquery: {s}\n", .{query});

                        const exec_res = osquery.executeQuery(allocator, query) catch {
                            continue;
                        };
                        defer allocator.free(exec_res.output);

                        // Encode & Send Result
                        const b64_len = std.base64.standard.Encoder.calcSize(exec_res.output.len);
                        const b64_buf = try allocator.alloc(u8, b64_len);
                        defer allocator.free(b64_buf);
                        _ = std.base64.standard.Encoder.encode(b64_buf, exec_res.output);

                        const res_url_raw = try std.fmt.allocPrint(allocator, "{s}/api/agents/{s}/tasks/{s}/result", .{ SERVER_URL_BASE, AGENT_ID, task_id });
                        defer allocator.free(res_url_raw);
                        const res_url = try allocator.dupeZ(u8, res_url_raw);
                        defer allocator.free(res_url);

                        const res_payload = try std.fmt.allocPrint(allocator, "{{\"output_b64\": \"{s}\", \"error\": \"\"}}", .{b64_buf});
                        defer allocator.free(res_payload);

                        _ = client.request("POST", res_url, res_payload) catch {};
                    }
                }
            } else |_| {}
        }

        // Sleep 5 seconds to avoid spamming the server
        _ = c.sleep(5);
    }
}

fn getJsonField(json: []const u8, field: []const u8) ?[]const u8 {
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
