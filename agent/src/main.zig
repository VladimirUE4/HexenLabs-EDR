const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
});
const osquery = @import("osquery.zig");
const shell = @import("shell.zig");
const curl = @import("curl.zig");
const Ed25519 = std.crypto.sign.Ed25519;

// Configuration
const SERVER_URL_BASE = "https://127.0.0.1:8443"; // HTTPS Gateway Port
const AGENT_ID = "agent-linux-001";
const HEARTBEAT_INTERVAL_NS = 10 * std.time.ns_per_s;

// ADMIN PUBLIC KEY (Ed25519) - In prod, this would be baked in during build or read from a protected file
const ADMIN_PUB_KEY_HEX = "fe3012be0c173015cc27f25c8c52b7a62da031600bde3b062439bd25fb6df497";

// Cert Paths (Relative to CWD for dev, Absolute for prod)
const CA_PATH = "../pki/certs/ca.crt";
const CERT_PATH = "../pki/certs/agent.crt";
const KEY_PATH = "../pki/certs/agent.key";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("HexenLabs EDR Agent starting (mTLS + Ed25519 Security)...\n", .{});

    // Parse Admin Public Key
    var admin_pub_key_bytes: [Ed25519.PublicKey.encoded_length]u8 = undefined;
    _ = try std.fmt.hexToBytes(&admin_pub_key_bytes, ADMIN_PUB_KEY_HEX);
    const admin_pub_key = try Ed25519.PublicKey.fromBytes(admin_pub_key_bytes);

    std.debug.print("Admin Public Key Loaded: {s}...\n", .{ADMIN_PUB_KEY_HEX[0..12]});

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
                    // Check if it's 204 No Content (empty body usually, but curl wrapper might return empty string)
                    // If response is valid JSON
                    if (getJsonField(response, "payload") orelse getJsonField(response, "Payload")) |query| {
                        const task_id = getJsonField(response, "id") orelse getJsonField(response, "ID") orelse "unknown";
                        const task_type = getJsonField(response, "type") orelse getJsonField(response, "Type") orelse "OSQUERY";
                        const signature_hex = getJsonField(response, "signature") orelse getJsonField(response, "Signature");

                        std.debug.print("Received Task: {s} (Type: {s})\n", .{ task_id, task_type });

                        // --- SECURITY CHECK: VERIFY SIGNATURE ---
                        var verified = false;
                        if (signature_hex) |sig| {
                            var sig_bytes: [Ed25519.Signature.encoded_length]u8 = undefined;
                            if (sig.len == Ed25519.Signature.encoded_length * 2) {
                                _ = std.fmt.hexToBytes(&sig_bytes, sig) catch {
                                    std.debug.print("SECURITY ALERT: Invalid hex signature format.\n", .{});
                                };

                                const signature = Ed25519.Signature.fromBytes(sig_bytes);
                                if (signature.verify(query, admin_pub_key)) |_| {
                                    verified = true;
                                    std.debug.print("SECURITY SUCCESS: Payload signature verified by Admin Key.\n", .{});
                                } else |err| {
                                    std.debug.print("SECURITY ALERT: Signature Verification FAILED: {}\n", .{err});
                                }
                            } else {
                                std.debug.print("SECURITY ALERT: Invalid signature length.\n", .{});
                            }
                        } else {
                            std.debug.print("SECURITY ALERT: Task has NO SIGNATURE. Rejecting.\n", .{});
                        }

                        if (!verified) {
                            const err_msg = try std.fmt.allocPrint(allocator, "SECURITY ERROR: Payload not signed by authorized Admin Key. Execution refused.", .{});
                            goto_send_result(allocator, &client, SERVER_URL_BASE, AGENT_ID, task_id, err_msg);
                            allocator.free(err_msg);
                            continue; // Skip execution
                        }
                        // ----------------------------------------

                        var exec_output: []const u8 = undefined;
                        var exec_exit_code: u8 = 0;

                        if (std.mem.eql(u8, task_type, "SHELL")) {
                            // --- SHELL EXECUTION ---
                            const shell_res = shell.executeCommand(allocator, query) catch |err| {
                                std.debug.print("ERROR: Failed to execute shell: {}\n", .{err});
                                const err_msg = try std.fmt.allocPrint(allocator, "Agent Error: {}", .{err});
                                goto_send_result(allocator, &client, SERVER_URL_BASE, AGENT_ID, task_id, err_msg);
                                allocator.free(err_msg);
                                continue;
                            };
                            exec_output = shell_res.output;
                            exec_exit_code = shell_res.exit_code;
                        } else {
                            // --- OSQUERY EXECUTION (Default) ---
                            const exec_res = osquery.executeQuery(allocator, query) catch |err| {
                                std.debug.print("ERROR: Failed to execute osquery: {}\n", .{err});
                                const err_msg = try std.fmt.allocPrint(allocator, "Agent Error: {}", .{err});
                                goto_send_result(allocator, &client, SERVER_URL_BASE, AGENT_ID, task_id, err_msg);
                                allocator.free(err_msg);
                                continue;
                            };
                            exec_output = exec_res.output;
                            exec_exit_code = exec_res.exit_code;
                        }

                        defer allocator.free(exec_output);

                        // Encode & Send Result
                        goto_send_result(allocator, &client, SERVER_URL_BASE, AGENT_ID, task_id, exec_output);
                    }
                }
            } else |_| {}
        }

        // Sleep 5 seconds to avoid spamming the server
        _ = c.sleep(5);
    }
}

fn goto_send_result(allocator: std.mem.Allocator, client: *curl.CurlClient, base_url: []const u8, agent_id: []const u8, task_id: []const u8, output: []const u8) void {
    const b64_len = std.base64.standard.Encoder.calcSize(output.len);
    const b64_buf = allocator.alloc(u8, b64_len) catch return;
    defer allocator.free(b64_buf);
    _ = std.base64.standard.Encoder.encode(b64_buf, output);

    const res_url_raw = std.fmt.allocPrint(allocator, "{s}/api/agents/{s}/tasks/{s}/result", .{ base_url, agent_id, task_id }) catch return;
    defer allocator.free(res_url_raw);
    const res_url = allocator.dupeZ(u8, res_url_raw) catch return;
    defer allocator.free(res_url);

    const res_payload = std.fmt.allocPrint(allocator, "{{\"output_b64\": \"{s}\", \"error\": \"\"}}", .{b64_buf}) catch return;
    defer allocator.free(res_payload);

    std.debug.print("Sending result to: {s}\n", .{res_url});
    if (client.request("POST", res_url, res_payload)) |_| {
        std.debug.print("Task result sent successfully (Task ID: {s})\n", .{task_id});
    } else |err| {
        std.debug.print("ERROR: Failed to send task result: {}\n", .{err});
    }
}

fn getJsonField(json: []const u8, field: []const u8) ?[]const u8 {
    // Try to find: "field":"value"
    const key_pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{field}) catch return null;
    defer std.heap.page_allocator.free(key_pattern);

    if (std.mem.indexOf(u8, json, key_pattern)) |start_idx| {
        const val_start = start_idx + key_pattern.len;
        // Find closing quote
        if (std.mem.indexOfPos(u8, json, val_start, "\"")) |end_idx| {
            return json[val_start..end_idx];
        }
    }

    // Try to find: "field":value (without quotes, for numbers/booleans)
    const key_pattern2 = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{field}) catch return null;
    defer std.heap.page_allocator.free(key_pattern2);

    if (std.mem.indexOf(u8, json, key_pattern2)) |start_idx| {
        const val_start = start_idx + key_pattern2.len;
        // Find next comma or closing brace
        var end_idx = val_start;
        while (end_idx < json.len) : (end_idx += 1) {
            if (json[end_idx] == ',' or json[end_idx] == '}' or json[end_idx] == ']') {
                // Trim whitespace
                while (end_idx > val_start and (json[end_idx - 1] == ' ' or json[end_idx - 1] == '\t' or json[end_idx - 1] == '\n')) {
                    end_idx -= 1;
                }
                if (end_idx > val_start) {
                    return json[val_start..end_idx];
                }
                break;
            }
        }
    }

    return null;
}
