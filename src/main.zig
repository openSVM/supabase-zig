const std = @import("std");
const json = std.json;
const http = std.http;
const Allocator = std.mem.Allocator;
const QueryBuilder = @import("query_builder.zig").QueryBuilder;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

pub const SupabaseError = error{
    InitError,
    AuthError,
    NetworkError,
    JsonError,
    InvalidResponse,
    UnexpectedError,
    QueryError,
    ParseError,
    StorageError,
    RealtimeError,
    RpcError,
    SessionExpiredError,
    InvalidCredentialsError,
    RateLimitError,
    PermissionError,
    MaxRetriesExceeded,
};

pub const SupabaseConfig = struct {
    url: []const u8,
    anon_key: []const u8,
    service_key: ?[]const u8 = null,
    timeout_ms: u32 = 10000,
    max_retries: u8 = 3,
    retry_interval_ms: u32 = 1000,
    headers: std.StringHashMap([]const u8),

    pub fn init(url: []const u8, anon_key: []const u8) SupabaseConfig {
        return .{
            .url = url,
            .anon_key = anon_key,
            .service_key = null,
            .headers = std.StringHashMap([]const u8).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *SupabaseConfig) void {
        self.headers.deinit();
    }
};

pub const JsonValue = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: ArrayList(JsonValue),
    object: StringHashMap(JsonValue),

    pub fn deinit(self: *JsonValue, allocator: Allocator) void {
        switch (self.*) {
            .array => |*array| {
                for (array.items) |*item| {
                    item.deinit(allocator);
                }
                array.deinit();
            },
            .object => |*map| {
                var it = map.iterator();
                while (it.next()) |entry| {
                    var value = entry.value_ptr;
                    value.deinit(allocator);
                }
                map.deinit();
            },
            else => {},
        }
    }
};

pub const ResponseMetadata = struct {
    count: ?usize = null,
    status: u16,
    status_text: []const u8,

    pub fn deinit(self: *ResponseMetadata, allocator: Allocator) void {
        allocator.free(self.status_text);
    }
};

pub const QueryResponse = struct {
    data: JsonValue,
    metadata: ResponseMetadata,
    allocator: Allocator,

    pub fn deinit(self: *QueryResponse) void {
        self.data.deinit(self.allocator);
        self.metadata.deinit(self.allocator);
    }
};

pub const SupabaseClient = struct {
    config: SupabaseConfig,
    allocator: Allocator,
    http_client: std.http.Client,

    pub fn init(allocator: Allocator, config: SupabaseConfig) !*SupabaseClient {
        const client = try allocator.create(SupabaseClient);
        client.* = .{
            .config = config,
            .allocator = allocator,
            .http_client = .{ .allocator = allocator },
        };
        return client;
    }

    pub fn deinit(self: *SupabaseClient) void {
        self.http_client.deinit();
        self.allocator.destroy(self);
    }

    // Query builder interface
    pub fn from(self: *SupabaseClient, table: []const u8) !*QueryBuilder {
        return QueryBuilder.init(self.allocator, table);
    }

    // Authentication methods
    pub fn signUp(self: *SupabaseClient, email: []const u8, password: []const u8) !Session {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");

        // Create a JSON object for safe serialization
        var json_obj = std.StringHashMap(JsonValue).init(self.allocator);
        defer json_obj.deinit();

        try json_obj.put("email", .{ .string = email });
        try json_obj.put("password", .{ .string = password });

        var writer = std.ArrayList(u8).init(self.allocator);
        defer writer.deinit();
        try std.json.stringify(json_obj, .{}, writer.writer());

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/auth/v1/signup", .{self.config.url});
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();
        try request.writeAll(writer.items);
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.AuthError;

        var response_body = ArrayList(u8).init(self.allocator);
        defer response_body.deinit();

        try response.body.?.reader().readAllArrayList(&response_body, 1024 * 1024);
        var parsed = try std.json.parseFromSlice(JsonValue, self.allocator, response_body.items, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        return Session{
            .access_token = try self.allocator.dupe(u8, obj.get("access_token").?.string),
            .refresh_token = try self.allocator.dupe(u8, obj.get("refresh_token").?.string),
            .expires_in = obj.get("expires_in").?.integer,
            .user = try self.parseUser(obj.get("user").?.object),
        };
    }

    pub fn signIn(self: *SupabaseClient, email: []const u8, password: []const u8) !Session {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");

        // Create a JSON object for safe serialization
        var json_obj = std.StringHashMap(JsonValue).init(self.allocator);
        defer json_obj.deinit();

        try json_obj.put("email", .{ .string = email });
        try json_obj.put("password", .{ .string = password });

        var writer = std.ArrayList(u8).init(self.allocator);
        defer writer.deinit();
        try std.json.stringify(json_obj, .{}, writer.writer());

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/auth/v1/token?grant_type=password", .{self.config.url});
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();
        try request.writeAll(writer.items);
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.AuthError;

        var response_body = ArrayList(u8).init(self.allocator);
        defer response_body.deinit();

        try response.body.?.reader().readAllArrayList(&response_body, 1024 * 1024);
        var parsed = try std.json.parseFromSlice(JsonValue, self.allocator, response_body.items, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        return Session{
            .access_token = try self.allocator.dupe(u8, obj.get("access_token").?.string),
            .refresh_token = try self.allocator.dupe(u8, obj.get("refresh_token").?.string),
            .expires_in = obj.get("expires_in").?.integer,
            .user = try self.parseUser(obj.get("user").?.object),
        };
    }

    // Database operations
    pub fn executeQuery(self: *SupabaseClient, builder: *QueryBuilder) !QueryResponse {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");

        // Add range headers if present
        if (builder.range_headers) |range| {
            try headers.append("Range-Unit", "items");
            try headers.append("Range", try std.fmt.allocPrint(self.allocator, "{d}-{d}", .{ range.start, range.end }));
        }

        var uri_builder = ArrayList(u8).init(self.allocator);
        defer uri_builder.deinit();

        try uri_builder.appendSlice(self.config.url);
        try uri_builder.appendSlice("/rest/v1/");
        try uri_builder.appendSlice(builder.table);

        if (builder.filters.items.len > 0) {
            try uri_builder.append('?');
            for (builder.filters.items, 0..) |filter, i| {
                if (i > 0) try uri_builder.append('&');
                // URL encode the filter
                const encoded_filter = try std.Uri.escapeString(self.allocator, filter);
                defer self.allocator.free(encoded_filter);
                try uri_builder.appendSlice(encoded_filter);
            }
        }

        var request = try self.http_client.request(.GET, try std.Uri.parse(uri_builder.items), headers, .{});
        defer request.deinit();
        try request.start();
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.QueryError;

        var response_body = ArrayList(u8).init(self.allocator);
        defer response_body.deinit();

        try response.body.?.reader().readAllArrayList(&response_body, 1024 * 1024);

        var parsed = try std.json.parseFromSlice(JsonValue, self.allocator, response_body.items, .{});

        // Parse Content-Range header correctly (format: "items start-end/total")
        var count: ?usize = null;
        if (response.headers.getFirstValue("Content-Range")) |range| {
            const last_slash = std.mem.lastIndexOf(u8, range, "/") orelse return error.InvalidResponse;
            count = try std.fmt.parseInt(usize, range[last_slash + 1 ..], 10);
        }

        return QueryResponse{
            .data = parsed.value,
            .metadata = .{
                .count = count,
                .status = @intFromEnum(response.status),
                .status_text = try self.allocator.dupe(u8, @tagName(response.status)),
            },
            .allocator = self.allocator,
        };
    }

    pub const Session = struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
        user: User,

        pub fn deinit(self: *Session, allocator: Allocator) void {
            allocator.free(self.access_token);
            allocator.free(self.refresh_token);
            self.user.deinit(allocator);
        }
    };

    pub const User = struct {
        id: []const u8,
        email: []const u8,
        role: ?[]const u8 = null,

        pub fn deinit(self: *User, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.email);
            if (self.role) |role| allocator.free(role);
        }
    };

    pub fn signOut(self: *SupabaseClient, access_token: []const u8) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");
        try headers.append("Authorization", try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{access_token}));

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/auth/v1/logout", .{self.config.url});
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.AuthError;
    }

    pub fn refreshSession(self: *SupabaseClient, refresh_token: []const u8) !Session {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");

        const body = try std.fmt.allocPrint(self.allocator, "{{\"refresh_token\":\"{s}\"}}", .{refresh_token});
        defer self.allocator.free(body);

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/auth/v1/token?grant_type=refresh_token", .{self.config.url});
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();
        try request.writeAll(body);
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.AuthError;

        var response_body = ArrayList(u8).init(self.allocator);
        defer response_body.deinit();

        try response.body.?.reader().readAllArrayList(&response_body, 1024 * 1024);
        var parsed = try std.json.parseFromSlice(JsonValue, self.allocator, response_body.items, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        return Session{
            .access_token = try self.allocator.dupe(u8, obj.get("access_token").?.string),
            .refresh_token = try self.allocator.dupe(u8, obj.get("refresh_token").?.string),
            .expires_in = obj.get("expires_in").?.integer,
            .user = try self.parseUser(obj.get("user").?.object),
        };
    }

    fn parseUser(self: *SupabaseClient, user_obj: StringHashMap(JsonValue)) !User {
        return User{
            .id = try self.allocator.dupe(u8, user_obj.get("id").?.string),
            .email = try self.allocator.dupe(u8, user_obj.get("email").?.string),
            .role = if (user_obj.get("role")) |role| try self.allocator.dupe(u8, role.string) else null,
        };
    }

    pub fn resetPasswordForEmail(self: *SupabaseClient, email: []const u8) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");

        // Create a JSON object for safe serialization
        var json_obj = std.StringHashMap(JsonValue).init(self.allocator);
        defer json_obj.deinit();

        try json_obj.put("email", .{ .string = email });

        var writer = std.ArrayList(u8).init(self.allocator);
        defer writer.deinit();
        try std.json.stringify(json_obj, .{}, writer.writer());

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/auth/v1/recover", .{self.config.url});
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();
        try request.writeAll(writer.items);
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.AuthError;
    }

    pub fn rpc(self: *SupabaseClient, function: []const u8, params: ?JsonValue) !JsonValue {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/rest/v1/rpc/{s}", .{ self.config.url, function });
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();

        if (params) |p| {
            var writer = std.json.writeArena(self.allocator, p, .{});
            defer writer.deinit();
            try request.writeAll(writer.bytes);
        }

        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.RpcError;

        var response_body = ArrayList(u8).init(self.allocator);
        defer response_body.deinit();

        try response.body.?.reader().readAllArrayList(&response_body, 1024 * 1024);
        var parsed = try std.json.parseFromSlice(JsonValue, self.allocator, response_body.items, .{});
        // Create a copy of the value to return while we still own the parsed result
        var result = try parsed.value.deepClone(self.allocator);
        // Clean up the parsed result
        parsed.deinit();
        return result;
    }

    pub fn batchInsert(self: *SupabaseClient, table: []const u8, items: []const JsonValue) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");
        try headers.append("Prefer", "return=minimal");

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/rest/v1/{s}", .{ self.config.url, table });
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.POST, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();

        // Write array of items
        try request.writeAll("[");
        for (items, 0..) |item, i| {
            if (i > 0) try request.writeAll(",");
            var writer = std.json.writeArena(self.allocator, item, .{});
            defer writer.deinit();
            try request.writeAll(writer.bytes);
        }
        try request.writeAll("]");
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.QueryError;
    }

    pub fn batchUpdate(self: *SupabaseClient, table: []const u8, items: []const JsonValue) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");
        try headers.append("Prefer", "return=minimal");

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/rest/v1/{s}", .{ self.config.url, table });
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.PATCH, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();

        // Write array of items
        try request.writeAll("[");
        for (items, 0..) |item, i| {
            if (i > 0) try request.writeAll(",");
            var writer = std.json.writeArena(self.allocator, item, .{});
            defer writer.deinit();
            try request.writeAll(writer.bytes);
        }
        try request.writeAll("]");
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.QueryError;
    }

    pub fn batchDelete(self: *SupabaseClient, table: []const u8, ids: []const []const u8) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("apikey", self.config.anon_key);
        try headers.append("Content-Type", "application/json");
        try headers.append("Prefer", "return=minimal");

        // Build id list for query with URL encoding
        var id_list = ArrayList(u8).init(self.allocator);
        defer id_list.deinit();

        try id_list.appendSlice("id=in.(");
        for (ids, 0..) |id, i| {
            if (i > 0) try id_list.appendSlice(",");
            // URL encode each ID
            const encoded_id = try std.Uri.escapeString(self.allocator, id);
            defer self.allocator.free(encoded_id);
            try id_list.appendSlice(encoded_id);
        }
        try id_list.appendSlice(")");

        var uri = try std.fmt.allocPrint(self.allocator, "{s}/rest/v1/{s}?{s}", .{ self.config.url, table, id_list.items });
        defer self.allocator.free(uri);

        var request = try self.http_client.request(.DELETE, try std.Uri.parse(uri), headers, .{});
        defer request.deinit();
        try request.start();
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.QueryError;
    }

    fn executeWithRetry(self: *SupabaseClient, comptime method: std.http.Method, uri: []const u8, headers: *std.http.Headers, body: ?[]const u8) !std.http.Client.Response {
        var attempts: u8 = 0;
        while (attempts < self.config.max_retries) : (attempts += 1) {
            var request = try self.http_client.request(method, try std.Uri.parse(uri), headers.*, .{});
            defer request.deinit();

            try request.start();
            if (body) |b| try request.writeAll(b);
            try request.finish();

            const response = try request.wait();
            switch (response.status) {
                .too_many_requests, .service_unavailable, .gateway_timeout => {
                    std.time.sleep(self.config.retry_interval_ms * std.time.ns_per_ms);
                    continue;
                },
                else => return response,
            }
        }
        return error.MaxRetriesExceeded;
    }
};

pub const ErrorResponse = struct {
    code: []const u8,
    message: []const u8,
    details: ?[]const u8,
};

pub fn QueryResult(comptime T: type) type {
    return struct {
        data: []T,
        count: ?usize,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            for (self.data) |*item| {
                item.deinit(allocator);
            }
            allocator.free(self.data);
        }
    };
}
