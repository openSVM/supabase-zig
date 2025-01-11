const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const SupabaseClient = @import("main.zig").SupabaseClient;

pub const StorageObject = struct {
    name: []const u8,
    size: usize,
    last_modified: i64,
    content_type: []const u8,

    pub fn deinit(self: *StorageObject, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.content_type);
    }
};

pub const StorageClient = struct {
    allocator: Allocator,
    bucket: []const u8,
    client: *SupabaseClient,

    pub fn init(allocator: Allocator, client: *SupabaseClient, bucket: []const u8) !*StorageClient {
        const storage = try allocator.create(StorageClient);
        storage.* = .{
            .allocator = allocator,
            .bucket = try allocator.dupe(u8, bucket),
            .client = client,
        };
        return storage;
    }

    pub fn deinit(self: *StorageClient) void {
        self.allocator.free(self.bucket);
        self.allocator.destroy(self);
    }

    pub fn upload(self: *StorageClient, path: []const u8, data: []const u8) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Content-Type", "application/octet-stream");
        try headers.append("Authorization", "Bearer " ++ self.client.config.anon_key);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/storage/v1/object/{s}/{s}", .{ self.client.config.url, self.bucket, path });
        defer self.allocator.free(url);

        var request = try self.client.http_client.request(.POST, try std.Uri.parse(url), headers, .{});
        defer request.deinit();

        try request.start();
        try request.writeAll(data);
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.StorageError;
    }

    pub fn download(self: *StorageClient, path: []const u8) ![]const u8 {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Authorization", "Bearer " ++ self.client.config.anon_key);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/storage/v1/object/{s}/{s}", .{ self.client.config.url, self.bucket, path });
        defer self.allocator.free(url);

        var request = try self.client.http_client.request(.GET, try std.Uri.parse(url), headers, .{});
        defer request.deinit();

        try request.start();
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.StorageError;

        var data = std.ArrayList(u8).init(self.allocator);
        try response.body.?.reader().readAllArrayList(&data, 1024 * 1024);

        return data.toOwnedSlice();
    }

    pub fn remove(self: *StorageClient, path: []const u8) !void {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Authorization", "Bearer " ++ self.client.config.anon_key);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/storage/v1/object/{s}/{s}", .{ self.client.config.url, self.bucket, path });
        defer self.allocator.free(url);

        var request = try self.client.http_client.request(.DELETE, try std.Uri.parse(url), headers, .{});
        defer request.deinit();

        try request.start();
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.StorageError;
    }

    pub fn list(self: *StorageClient, prefix: ?[]const u8) ![]StorageObject {
        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Authorization", "Bearer " ++ self.client.config.anon_key);

        const url = if (prefix) |p|
            try std.fmt.allocPrint(self.allocator, "{s}/storage/v1/object/list/{s}?prefix={s}", .{ self.client.config.url, self.bucket, p })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/storage/v1/object/list/{s}", .{ self.client.config.url, self.bucket });
        defer self.allocator.free(url);

        var request = try self.client.http_client.request(.GET, try std.Uri.parse(url), headers, .{});
        defer request.deinit();

        try request.start();
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) return error.StorageError;

        // Read response body
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        try response.body.?.reader().readAllArrayList(&body, 1024 * 1024);

        // Parse JSON response
        var parser = json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(body.items);
        defer tree.deinit();

        const root = tree.root.array;
        var objects = try self.allocator.alloc(StorageObject, root.items.len);

        for (root.items, 0..) |item, i| {
            const obj = item.object;
            objects[i] = .{
                .name = try self.allocator.dupe(u8, obj.get("name").?.string),
                .size = @intCast(obj.get("metadata").?.object.get("size").?.integer),
                .last_modified = obj.get("metadata").?.object.get("lastModified").?.integer,
                .content_type = try self.allocator.dupe(u8, obj.get("metadata").?.object.get("mimetype").?.string),
            };
        }

        return objects;
    }
};
