# supabase-zig

A Zig client library for [Supabase](https://supabase.com), providing a type-safe and memory-efficient way to interact with your Supabase backend.

## Features

- 🔐 **Authentication**: Full support for email/password authentication
- 📊 **Database Operations**: Powerful query builder for database interactions
- 🗄️ **Storage**: File upload, download, and management capabilities
- 🔄 **Realtime**: Subscribe to database changes in real-time
- 🛠️ **RPC**: Call Postgres functions directly
- ⚡ **Performance**: Zero-allocation where possible, with careful memory management
- 🔒 **Type Safety**: Leverage Zig's compile-time features for type-safe operations

## Installation

Add this library to your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .supabase = .{
            .url = "https://github.com/your-username/supabase-zig/archive/refs/tags/v0.1.0.tar.gz",
            // Add the appropriate hash here
        },
    },
}
```

## Quick Start

```zig
const std = @import("std");
const supabase = @import("supabase");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create Supabase client
    const config = supabase.SupabaseConfig.init(
        "YOUR_SUPABASE_URL",
        "YOUR_SUPABASE_ANON_KEY",
    );
    var client = try supabase.SupabaseClient.init(allocator, config);
    defer client.deinit();

    // Example: Query data
    var query = try client.from("todos")
        .select("*")
        .limit(10);
    defer query.deinit();

    const result = try client.executeQuery(query);
    defer result.deinit();
}
```

## Authentication

```zig
// Sign up
const session = try client.signUp("user@example.com", "password123");
defer session.deinit(allocator);

// Sign in
const session = try client.signIn("user@example.com", "password123");
defer session.deinit(allocator);

// Sign out
try client.signOut(session.access_token);
```

## Database Operations

The query builder provides a fluent interface for database operations:

```zig
// Select with filters
var query = try client.from("users")
    .select("id, name, email")
    .eq("active", "true")
    .limit(20);

// Insert data
const user = JsonValue{ .object = .{
    .name = "John Doe",
    .email = "john@example.com",
}};
try client.batchInsert("users", &[_]JsonValue{user});

// Update data
try client.batchUpdate("users", &[_]JsonValue{updated_user});

// Delete data
try client.batchDelete("users", &[_][]const u8{"user_id_1", "user_id_2"});
```

## Storage Operations

```zig
// Initialize storage client
var storage = try StorageClient.init(allocator, client, "bucket_name");
defer storage.deinit();

// Upload file
try storage.upload("path/to/file.txt", file_data);

// Download file
const data = try storage.download("path/to/file.txt");
defer allocator.free(data);

// List files
const files = try storage.list(null);
defer {
    for (files) |*file| file.deinit(allocator);
    allocator.free(files);
}
```

## Error Handling

The library uses Zig's error union type for robust error handling:

```zig
const result = client.signIn("user@example.com", "password123") catch |err| switch (err) {
    error.AuthError => handle_auth_error(),
    error.NetworkError => handle_network_error(),
    error.InvalidCredentialsError => handle_invalid_credentials(),
    else => handle_other_error(),
};
```

## Memory Management

This library follows Zig's memory management principles:

- All resources must be explicitly freed using `deinit()`
- Memory is allocated using the provided allocator
- No global state or hidden allocations

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[Add your chosen license here]