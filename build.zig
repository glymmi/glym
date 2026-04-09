const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glym_mod = b.addModule("glym", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

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

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const counter_mod = b.createModule(.{
        .root_source_file = b.path("examples/counter/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    counter_mod.addImport("glym", glym_mod);

    const counter = b.addExecutable(.{
        .name = "counter",
        .root_module = counter_mod,
    });
    b.installArtifact(counter);

    const run_counter = b.addRunArtifact(counter);
    const run_counter_step = b.step("run-counter", "Run the counter example");
    run_counter_step.dependOn(&run_counter.step);
}
