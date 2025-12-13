const std = @import("std");
const c = @cImport({
    @cInclude("curl/curl.h");
});

pub const CurlError = error{
    InitFailed,
    PerformFailed,
};

pub const CurlClient = struct {
    handle: ?*c.CURL,
    allocator: std.mem.Allocator,
    response_buffer: std.ArrayList(u8),

    // Paths to certificates
    ca_path: [:0]const u8,
    cert_path: [:0]const u8,
    key_path: [:0]const u8,

    pub fn init(allocator: std.mem.Allocator, ca_path: [:0]const u8, cert_path: [:0]const u8, key_path: [:0]const u8) !CurlClient {
        if (c.curl_global_init(c.CURL_GLOBAL_ALL) != c.CURLE_OK) {
            return CurlError.InitFailed;
        }

        const handle = c.curl_easy_init() orelse return CurlError.InitFailed;
        const buffer = std.ArrayList(u8).initCapacity(allocator, 4096) catch return CurlError.InitFailed;

        return CurlClient{
            .handle = handle,
            .allocator = allocator,
            .response_buffer = buffer,
            .ca_path = ca_path,
            .cert_path = cert_path,
            .key_path = key_path,
        };
    }

    pub fn deinit(self: *CurlClient) void {
        if (self.handle) |h| {
            c.curl_easy_cleanup(h);
        }
        self.response_buffer.deinit(self.allocator);
        c.curl_global_cleanup();
    }

    // Write callback for Curl - using C calling convention
    fn writeCallback(ptr: *anyopaque, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
        const real_size = size * nmemb;
        const self: *CurlClient = @ptrCast(@alignCast(userdata));

        const bytes: [*]u8 = @ptrCast(ptr);
        self.response_buffer.appendSlice(self.allocator, bytes[0..real_size]) catch return 0;

        return real_size;
    }

    pub fn request(self: *CurlClient, method: []const u8, url: [:0]const u8, body: ?[]const u8) ![]u8 {
        const h = self.handle orelse return CurlError.InitFailed;

        self.response_buffer.clearRetainingCapacity();

        _ = c.curl_easy_setopt(h, c.CURLOPT_URL, url.ptr);
        _ = c.curl_easy_setopt(h, c.CURLOPT_WRITEFUNCTION, writeCallback);
        _ = c.curl_easy_setopt(h, c.CURLOPT_WRITEDATA, self);

        // mTLS Configuration
        _ = c.curl_easy_setopt(h, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
        _ = c.curl_easy_setopt(h, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));
        _ = c.curl_easy_setopt(h, c.CURLOPT_CAINFO, self.ca_path.ptr);

        _ = c.curl_easy_setopt(h, c.CURLOPT_SSLCERT, self.cert_path.ptr);
        _ = c.curl_easy_setopt(h, c.CURLOPT_SSLKEY, self.key_path.ptr);

        // Method & Body
        if (std.mem.eql(u8, method, "POST")) {
            _ = c.curl_easy_setopt(h, c.CURLOPT_POST, @as(c_long, 1));
            if (body) |b| {
                _ = c.curl_easy_setopt(h, c.CURLOPT_POSTFIELDS, b.ptr);
                _ = c.curl_easy_setopt(h, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(b.len)));
            }
        } else {
            _ = c.curl_easy_setopt(h, c.CURLOPT_HTTPGET, @as(c_long, 1));
        }

        // Perform
        const res = c.curl_easy_perform(h);
        if (res != c.CURLE_OK) {
            std.debug.print("Curl Error: {s}\n", .{c.curl_easy_strerror(res)});
            return CurlError.PerformFailed;
        }

        return self.response_buffer.items;
    }
};
