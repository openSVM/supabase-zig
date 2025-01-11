const std = @import("std");
const testing = std.testing;
const supabase = @import("supabase");
const ArrayList = std.ArrayList;

test "SupabaseConfig initialization and deinit" {
    const config = supabase.SupabaseConfig.init("https://example.supabase.co", "your-anon-key");
    defer config.deinit();

    try testing.expectEqualStrings("https://example.supabase.co", config.url);
    try testing.expectEqualStrings("your-anon-key", config.anon_key);
    try testing.expect(config.service_key == null);
    try testing.expectEqual(@as(u32, 10000), config.timeout_ms);
    try testing.expectEqual(@as(u8, 3), config.max_retries);
    try testing.expectEqual(@as(u32, 1000), config.retry_interval_ms);
}

test "JsonValue operations" {
    const allocator = testing.allocator;

    var array = ArrayList(supabase.JsonValue).init(allocator);
    defer array.deinit();

    try array.append(.{ .string = "test" });
    try array.append(.{ .integer = 42 });

    var map = std.StringHashMap(supabase.JsonValue).init(allocator);
    defer map.deinit();

    try map.put("key", .{ .string = "value" });

    var json_value = supabase.JsonValue{ .object = map };
    defer json_value.deinit(allocator);

    if (json_value == .object) {
        const value = json_value.object.get("key").?;
        try testing.expectEqualStrings("value", value.string);
    }
}

test "QueryBuilder all operations" {
    const allocator = testing.allocator;
    const config = supabase.SupabaseConfig.init("https://example.supabase.co", "your-anon-key");
    defer config.deinit();

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    const query = try client.from("users");
    defer query.deinit();

    // Test all query builder methods
    try query.select("id,name,email");
    try query.eq("id", "123");
    try query.neq("status", "inactive");
    try query.gt("age", "18");
    try query.lt("age", "65");
    try query.gte("points", "100");
    try query.lte("points", "1000");
    try query.like("name", "%John%");
    try query.ilike("email", "%@example.com");
    try query.limit(10);
    try query.offset(20);
    try query.order("created_at", .desc);
    try query.range(0, 9);
    try query.in("id", &[_][]const u8{ "1", "2", "3" });
    try query.is("deleted", "null");
    try query.not("role", "eq", "admin");
    try query.contains("tags", "important");
    try query.containedBy("permissions", "admin,user");

    try testing.expectEqualStrings("users", query.table);
    try testing.expectEqual(@as(usize, 18), query.filters.items.len);
}

test "Error response handling" {
    const error_response = supabase.ErrorResponse{
        .code = "23505",
        .message = "duplicate key value violates unique constraint",
        .details = "Key (email)=(test@example.com) already exists.",
    };

    try testing.expectEqualStrings("23505", error_response.code);
    try testing.expectEqualStrings("duplicate key value violates unique constraint", error_response.message);
    try testing.expectEqualStrings("Key (email)=(test@example.com) already exists.", error_response.details.?);
}

test "Query response metadata" {
    const allocator = testing.allocator;

    var metadata = supabase.ResponseMetadata{
        .count = 42,
        .status = 200,
        .status_text = try allocator.dupe(u8, "OK"),
    };
    defer metadata.deinit(allocator);

    try testing.expectEqual(@as(?usize, 42), metadata.count);
    try testing.expectEqual(@as(u16, 200), metadata.status);
    try testing.expectEqualStrings("OK", metadata.status_text);
}

test "Generic query result" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        id: []const u8,
        name: []const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.free(self.id);
            alloc.free(self.name);
        }
    };

    var result = supabase.QueryResult(TestStruct){
        .data = &[_]TestStruct{.{
            .id = try allocator.dupe(u8, "1"),
            .name = try allocator.dupe(u8, "Test"),
        }},
        .count = 1,
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("1", result.data[0].id);
    try testing.expectEqualStrings("Test", result.data[0].name);
    try testing.expectEqual(@as(?usize, 1), result.count);
}

test "Page struct operations" {
    const allocator = testing.allocator;

    var items = try allocator.alloc(supabase.JsonValue, 2);
    items[0] = .{ .string = "item1" };
    items[1] = .{ .string = "item2" };

    var page = supabase.Page{
        .items = items,
        .total_count = 2,
        .has_more = false,
    };
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), page.items.len);
    try testing.expectEqual(@as(usize, 2), page.total_count);
    try testing.expect(!page.has_more);
}

test "Retry mechanism" {
    const allocator = testing.allocator;
    var config = supabase.SupabaseConfig.init("https://example.supabase.co", "your-anon-key");
    defer config.deinit();

    config.max_retries = 1;
    config.retry_interval_ms = 100;

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    // This test will fail due to invalid credentials, but it tests the retry mechanism
    try testing.expectError(error.AuthError, client.signIn("test@example.com", "password"));
}

test "Storage operations" {
    const allocator = testing.allocator;
    var config = supabase.SupabaseConfig.init("https://example.supabase.co", "your-anon-key");
    defer config.deinit();

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    const storage = try supabase.StorageClient.init(allocator, client, "test-bucket");
    defer storage.deinit();

    try testing.expectEqualStrings("test-bucket", storage.bucket);
}

test "JsonValue error cases" {
    const allocator = testing.allocator;

    // Test invalid JSON parsing
    const invalid_json = "{ invalid json }";
    try testing.expectError(error.ParseError, std.json.parseFromSlice(supabase.JsonValue, allocator, invalid_json, .{}));

    // Test null value
    const json_null = supabase.JsonValue{ .null = {} };
    try testing.expect(json_null == .null);

    // Test boolean value
    const json_bool = supabase.JsonValue{ .bool = true };
    try testing.expect(json_bool.bool);
}

test "Query builder edge cases" {
    const allocator = testing.allocator;
    const config = supabase.SupabaseConfig.init("https://example.supabase.co", "your-anon-key");
    defer config.deinit();

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    const query = try client.from("users");
    defer query.deinit();

    // Empty select
    try query.select("");

    // Empty array for 'in' operator
    try query.in("id", &[_][]const u8{});

    // Special characters in values
    try query.eq("name", "O'Connor");
    try query.like("email", "%+_@%.com");

    // Unicode characters
    try query.eq("name", "测试");

    try testing.expectEqual(@as(usize, 5), query.filters.items.len);
}

test "Error response with null details" {
    const error_response = supabase.ErrorResponse{
        .code = "404",
        .message = "Not Found",
        .details = null,
    };

    try testing.expectEqualStrings("404", error_response.code);
    try testing.expectEqualStrings("Not Found", error_response.message);
    try testing.expect(error_response.details == null);
}

test "Response metadata edge cases" {
    const allocator = testing.allocator;

    var metadata = supabase.ResponseMetadata{
        .count = null,
        .status = 404,
        .status_text = try allocator.dupe(u8, "Not Found"),
    };
    defer metadata.deinit(allocator);

    try testing.expect(metadata.count == null);
    try testing.expectEqual(@as(u16, 404), metadata.status);
    try testing.expectEqualStrings("Not Found", metadata.status_text);
}

test "Query result with empty data" {
    const allocator = testing.allocator;

    const EmptyStruct = struct {
        pub fn deinit(self: *@This(), _: std.mem.Allocator) void {
            _ = self;
        }
    };

    var result = supabase.QueryResult(EmptyStruct){
        .data = &[_]EmptyStruct{},
        .count = 0,
    };
    defer result.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), result.data.len);
    try testing.expectEqual(@as(?usize, 0), result.count);
}

test "Page with empty items" {
    const allocator = testing.allocator;

    var items = try allocator.alloc(supabase.JsonValue, 0);

    var page = supabase.Page{
        .items = items,
        .total_count = 0,
        .has_more = false,
    };
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), page.items.len);
    try testing.expectEqual(@as(usize, 0), page.total_count);
    try testing.expect(!page.has_more);
}

test "Maximum retries exceeded" {
    const allocator = testing.allocator;
    var config = supabase.SupabaseConfig.init("https://example.supabase.co", "your-anon-key");
    defer config.deinit();

    config.max_retries = 0;
    config.retry_interval_ms = 0;

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    try testing.expectError(error.AuthError, client.signIn("test@example.com", "password"));
}
