const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shimmer_dep = b.dependency("shimmer", .{
        .target = target,
        .optimize = optimize,
    });
    const shimmer_mod = shimmer_dep.module("shimmer");

    const glym_mod = b.addModule("glym", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    glym_mod.addImport("shimmer", shimmer_mod);

    const lib = b.addLibrary(.{
        .name = "glym",
        .linkage = .static,
        .root_module = glym_mod,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = glym_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_mod.addImport("glym", glym_mod);
    const integration_tests = b.addTest(.{
        .root_module = integration_mod,
    });
    const run_integration = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_integration.step);

    addExample(b, glym_mod, target, optimize, "counter", "examples/counter/main.zig");
    addExample(b, glym_mod, target, optimize, "async_fetch", "examples/async_fetch/main.zig");
    addExample(b, glym_mod, target, optimize, "showcase", "examples/showcase/main.zig");
}

fn addExample(
    b: *std.Build,
    glym_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    comptime root: []const u8,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path(root),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("glym", glym_mod);

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = mod,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const step = b.step("run-" ++ name, "Run the " ++ name ++ " example");
    step.dependOn(&run.step);
}
