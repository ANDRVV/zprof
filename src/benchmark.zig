const std = @import("std");

const Config = @import("zprof.zig").Config;
const Zprof = @import("zprof.zig").Zprof;

const iterations: u64 = 10_000_000;
const alloc_size: u64 = 16;

fn benchmark(allocator: std.mem.Allocator) !f64 {
    var start = std.time.Timer.start() catch unreachable;

    for (0..iterations) |_| {
        const ptr = try allocator.alloc(u8, alloc_size);
        allocator.free(ptr);
    }

    return @floatFromInt(start.read());
}

fn stat(comptime config: Config) !struct { f64, f64, f64 } {
    const child_allocator = std.heap.c_allocator;
    var zprof: Zprof(config) = .init(child_allocator, undefined);
    const allocator = zprof.allocator();

    const tot_raw_allocator = try benchmark(child_allocator);
    const tot_wrapped_allocator = try benchmark(allocator);

    const overhead = (tot_wrapped_allocator - tot_raw_allocator) / tot_raw_allocator * 100;

    return .{ tot_raw_allocator, tot_wrapped_allocator, overhead };
}

pub fn main() !void {
    // disable all parameters to get the baseline overhead
    // of the wrapper itself, without any bookkeeping
    const config1: Config = .{
        .allocated = false,
        .freed = false,
        .alloc_count = false,
        .free_count = false,
        .live_requested = false,
        .peak_requested = false,
    };

    _, _, const baseline_overhead = try stat(config1);

    // all parameters are enabled by default
    const config2: Config = .{};

    const tot_raw_allocator, const tot_wrapped_allocator, const overhead = try stat(config2);

    std.debug.print("Alloc/free benchmark [bytes={d} ops={d}]\n\n", .{ alloc_size, iterations });
    std.debug.print("Raw allocator:   tot={}ns\n", .{tot_raw_allocator});
    std.debug.print("Zprof allocator: tot={}ns\n\n", .{tot_wrapped_allocator});

    std.debug.print("Baseline overhead (Wrapper): +{d:.02}%\n", .{baseline_overhead});
    std.debug.print("Bookkeeping overhead:        +{d:.02}%\n", .{overhead - baseline_overhead});
    std.debug.print("Total overhead:              +{d:.02}%\n", .{overhead});
}
