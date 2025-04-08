const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const csa_mod = b.addModule("csa", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const csa_unit_tests = b.addTest(.{ .root_module = csa_mod });
    const run_csa_unit_tests = b.addRunArtifact(csa_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_csa_unit_tests.step);
}
