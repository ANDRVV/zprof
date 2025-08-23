const std = @import("std");

/// Build script for the zprof library.
/// This generates a static library that you can link into your projects.
pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Creates public dep
    const module = b.addModule("zprof", .{
        .root_source_file = b.path("src/zprof.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the static library
    const lib = b.addLibrary(.{
        .name = "zprof",
        .root_module = module,
        .linkage = .static,
    });

    // This declares intent for the library to be installed into the standard location
    b.installArtifact(lib);

    // Run tests for zprof
    const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = module }));
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
