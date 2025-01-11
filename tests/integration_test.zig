const std = @import("std");
const testing = std.testing;
const supabase = @import("supabase");

test "Database query integration" {
    const allocator = testing.allocator;

    const url = try testing.allocator.dupe(u8, std.os.getenv("SUPABASE_URL") orelse return error.MissingEnvVar);
    defer allocator.free(url);

    const key = try testing.allocator.dupe(u8, std.os.getenv("SUPABASE_ANON_KEY") orelse return error.MissingEnvVar);
    defer allocator.free(key);

    const config = supabase.SupabaseConfig.init(url, key);
    defer config.deinit();

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    // Test query builder
    const query = try client.from("users");
    defer query.deinit();

    try query.select("id,email");
    try query.eq("id", "1");
    try query.limit(1);

    const response = try client.executeQuery(query);
    defer response.deinit();

    try testing.expect(response.metadata.status == 200);
}

test "Authentication integration" {
    const allocator = testing.allocator;

    const url = try testing.allocator.dupe(u8, std.os.getenv("SUPABASE_URL") orelse return error.MissingEnvVar);
    defer allocator.free(url);

    const key = try testing.allocator.dupe(u8, std.os.getenv("SUPABASE_ANON_KEY") orelse return error.MissingEnvVar);
    defer allocator.free(key);

    const config = supabase.SupabaseConfig.init(url, key);
    defer config.deinit();

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    // Test auth operations
    const test_email = std.os.getenv("TEST_USER_EMAIL") orelse return error.MissingEnvVar;
    const test_password = std.os.getenv("TEST_USER_PASSWORD") orelse return error.MissingEnvVar;

    try client.signIn(test_email, test_password);
}

test "RPC integration" {
    const allocator = testing.allocator;

    const url = try testing.allocator.dupe(u8, std.os.getenv("SUPABASE_URL") orelse return error.MissingEnvVar);
    defer allocator.free(url);

    const key = try testing.allocator.dupe(u8, std.os.getenv("SUPABASE_ANON_KEY") orelse return error.MissingEnvVar);
    defer allocator.free(key);

    const config = supabase.SupabaseConfig.init(url, key);
    defer config.deinit();

    const client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    // Test RPC call
    var params = std.StringHashMap(supabase.JsonValue).init(allocator);
    defer params.deinit();
    try params.put("param1", .{ .string = "test" });

    const result = try client.rpc("test_function", .{ .object = params });
    defer result.deinit(allocator);
}
