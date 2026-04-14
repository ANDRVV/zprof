const std = @import("std");

/// Build script for the zprof library.
/// This generates a static library that you can link into your projects.
pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

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

    const exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    // for c_allocator
    exe.root_module.link_libc = true;

    const run_benchmark = b.addRunArtifact(exe);

    // add step for benchmarking
    const benchmark_step = b.step("benchmark", "Run benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);

    // Run tests for zprof
    const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = module }));
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
