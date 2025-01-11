const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const JsonValue = @import("main.zig").JsonValue;

pub const Order = enum {
    asc,
    desc,
};

pub const QueryBuilder = struct {
    allocator: Allocator,
    table: []const u8,
    filters: std.ArrayList([]const u8),
    range_headers: ?struct {
        start: usize,
        end: usize,
    } = null,

    pub fn init(allocator: Allocator, table: []const u8) !*QueryBuilder {
        const builder = try allocator.create(QueryBuilder);
        builder.* = .{
            .allocator = allocator,
            .table = table,
            .filters = std.ArrayList([]const u8).init(allocator),
            .range_headers = null,
        };
        return builder;
    }

    pub fn deinit(self: *QueryBuilder) void {
        for (self.filters.items) |filter| {
            self.allocator.free(filter);
        }
        self.filters.deinit();
        self.allocator.destroy(self);
    }

    pub fn select(self: *QueryBuilder, columns: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "select={s}", .{columns}));
    }

    pub fn eq(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=eq.{s}", .{ column, value }));
    }

    pub fn neq(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=neq.{s}", .{ column, value }));
    }

    pub fn gt(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=gt.{s}", .{ column, value }));
    }

    pub fn lt(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=lt.{s}", .{ column, value }));
    }

    pub fn gte(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=gte.{s}", .{ column, value }));
    }

    pub fn lte(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=lte.{s}", .{ column, value }));
    }

    pub fn like(self: *QueryBuilder, column: []const u8, pattern: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=like.{s}", .{ column, pattern }));
    }

    pub fn ilike(self: *QueryBuilder, column: []const u8, pattern: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=ilike.{s}", .{ column, pattern }));
    }

    pub fn limit(self: *QueryBuilder, count: usize) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "limit={d}", .{count}));
    }

    pub fn offset(self: *QueryBuilder, count: usize) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "offset={d}", .{count}));
    }

    pub fn order(self: *QueryBuilder, column: []const u8, direction: Order) !void {
        const dir = switch (direction) {
            .asc => "asc",
            .desc => "desc",
        };
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "order={s}.{s}", .{ column, dir }));
    }

    pub fn range(self: *QueryBuilder, start: usize, end: usize) !void {
        self.range_headers = .{
            .start = start,
            .end = end,
        };
    }

    pub fn in(self: *QueryBuilder, column: []const u8, values: []const []const u8) !void {
        if (values.len == 0) return error.EmptyInList;

        var value_list = ArrayList(u8).init(self.allocator);
        defer value_list.deinit();

        try value_list.appendSlice("(");
        for (values, 0..) |value, i| {
            if (i > 0) try value_list.appendSlice(",");
            try value_list.appendSlice(value);
        }
        try value_list.appendSlice(")");

        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=in.{s}", .{ column, value_list.items }));
    }

    pub fn is(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=is.{s}", .{ column, value }));
    }

    pub fn not(self: *QueryBuilder, column: []const u8, operator: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=not.{s}.{s}", .{ column, operator, value }));
    }

    pub fn contains(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=cs.{{{s}}}", .{ column, value }));
    }

    pub fn containedBy(self: *QueryBuilder, column: []const u8, value: []const u8) !void {
        try self.filters.append(try std.fmt.allocPrint(self.allocator, "{s}=cd.{{{s}}}", .{ column, value }));
    }
};

pub const Page = struct {
    items: []JsonValue,
    total_count: usize,
    has_more: bool,

    pub fn deinit(self: *Page, allocator: Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }
};
