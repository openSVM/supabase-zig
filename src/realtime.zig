const std = @import("std");
const Allocator = std.mem.Allocator;
const WebSocket = std.http.WebSocket;

pub const RealtimeSubscription = struct {
    allocator: Allocator,
    channel: []const u8,
    socket: *WebSocket,
    callback: *const fn ([]const u8) void,

    pub fn init(allocator: Allocator, url: []const u8, channel: []const u8, callback: *const fn ([]const u8) void) !*RealtimeSubscription {
        const socket = try WebSocket.connect(allocator, try std.Uri.parse(url), .{});
        const sub = try allocator.create(RealtimeSubscription);

        sub.* = .{
            .allocator = allocator,
            .channel = try allocator.dupe(u8, channel),
            .socket = socket,
            .callback = callback,
        };

        return sub;
    }

    pub fn deinit(self: *RealtimeSubscription) void {
        self.allocator.free(self.channel);
        self.socket.close();
        self.socket.deinit();
        self.allocator.destroy(self);
    }
};
