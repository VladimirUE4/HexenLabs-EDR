const std = @import("std");
const net = std.net;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator;

    std.debug.print("HexenLabs EDR Agent starting...\n", .{});

    const server_addr = "127.0.0.1";
    const server_port = 50051;

    std.debug.print("Connecting to {s}:{d}...\n", .{server_addr, server_port});

    const peer = try net.Address.parseIp4(server_addr, server_port);
    const stream = net.tcpConnectToAddress(peer) catch |err| {
        std.debug.print("Failed to connect: {}\n", .{err});
        return;
    };
    defer stream.close();

    std.debug.print("Connected! Handshaking (Simulated)...\n", .{});
    
    // Just hold for a tiny bit of work
    var i: u64 = 0;
    while (i < 10000000) : (i += 1) {
        std.mem.doNotOptimizeAway(i);
    }
    
    std.debug.print("Disconnecting.\n", .{});
}
