const std = @import("std");

/// Build script for the zprof library.
/// This generates a static library that you can link into your projects.
pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Create the static library
    const lib = b.addStaticLibrary(.{
        .name = "zprof",
        .root_source_file = b.path("src/zprof.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Creates public dep
    _ = b.addModule("zprof", .{
        .root_source_file = b.path("src/zprof.zig"),
    });

    // This declares intent for the library to be installed into the standard location
    b.installArtifact(lib);
}
