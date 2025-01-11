const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "supabase-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Create module for tests to use
    const supabase_module = b.addModule("supabase", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    b.installArtifact(lib);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/main_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addModule("supabase", supabase_module);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/integration_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    integration_tests.addModule("supabase", supabase_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Test step
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // Create docs
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build documentation");
    docs_step.dependOn(&docs.step);
}
