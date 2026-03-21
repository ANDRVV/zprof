//! zprof.zig
//!
//! Copyright (c) Andrea Vaccaro
//!
//! Zprof is a zero-overhead, zero-dependency memory profiler
//! that wraps any allocator written in Zig.
//! Tracks allocations, detects memory leaks, and logs
//! memory changes with optional thread-safe mode.
//! Version 2.0.0
//!
//! Original repository: https://github.com/andrvv/zprof

const std = @import("std");

pub const VERSION = "2.0.0";

/// Collects allocation, deallocation, and live memory statistics.
pub fn Profiler(comptime thread_safe: bool) type {
    return struct {
        const Self = @This();

        writer: ?*std.Io.Writer,

        /// Allocated bytes from initialization.
        /// Keeps track of total bytes requested during the program's lifetime.
        allocated: std.atomic.Value(usize) = .init(0),

        /// Count of allocations from alloc/realloc.
        /// Every time memory is allocated, this counter increases.
        alloc_count: std.atomic.Value(usize) = .init(0),
        /// Count of deallocations from free/realloc/deinit.
        /// Every time memory is freed, this counter increases.
        free_count: std.atomic.Value(usize) = .init(0),

        /// Peak of live bytes.
        /// Tracks the maximum memory usage at any point during execution.
        live_peak: std.atomic.Value(usize) = .init(0),
        /// Current live bytes.
        /// Shows how much memory is currently in use.
        live_bytes: std.atomic.Value(usize) = .init(0),

        pub fn init(writer: ?*std.Io.Writer) Self {
            return .{ .writer = writer };
        }

        /// Updates profiler simulating allocation.
        /// Called internally whenever memory is allocated.
        fn updateAlloc(self: *Self, size: usize) void {
            if (thread_safe) {
                _ = self.allocated.fetchAdd(size, .monotonic);
                _ = self.live_bytes.fetchAdd(size, .monotonic);
                _ = self.alloc_count.fetchAdd(1, .monotonic);

                const live_bytes = self.live_bytes.load(.monotonic);
                _ = self.live_peak.fetchMax(live_bytes, .monotonic);
            } else {
                self.allocated.raw +|= size;
                self.live_bytes.raw +|= size;
                self.alloc_count.raw +|= 1;
                self.live_peak.raw = @max(self.live_bytes.raw, self.live_peak.raw);
            }

            if (self.writer) |writer|
                writer.print("Zprof::ALLOC allocated={d}\n", .{size}) catch {};
        }

        fn updateFree(self: *Self, size: usize) void {
            if (thread_safe) {
                _ = self.live_bytes.fetchSub(size, .monotonic);
                _ = self.free_count.fetchAdd(1, .monotonic);
            } else {
                self.live_bytes.raw -|= size;
                self.free_count.raw +|= 1;
            }

            if (self.writer) |writer|
                writer.print("Zprof::FREE deallocated={d}\n", .{size}) catch {};
        }

        /// Check if has memory leaks.
        /// Returns true if any allocations weren't properly freed.
        pub fn hasLeaks(self: *const Self) bool {
            return self.getLiveBytes() > 0;
        }

        pub fn reset(self: *Self) void {
            self.* = .init(self.writer);
        }

        pub fn getAllocated(self: *const Self) usize {
            return if (thread_safe) self.allocated.load(.monotonic) else self.allocated.raw;
        }

        pub fn getAllocCount(self: *const Self) usize {
            return if (thread_safe) self.alloc_count.load(.monotonic) else self.alloc_count.raw;
        }

        pub fn getFreeCount(self: *const Self) usize {
            return if (thread_safe) self.free_count.load(.monotonic) else self.free_count.raw;
        }

        pub fn getLivePeak(self: *const Self) usize {
            return if (thread_safe) self.live_peak.load(.monotonic) else self.live_peak.raw;
        }

        pub fn getLiveBytes(self: *const Self) usize {
            return if (thread_safe) self.live_bytes.load(.monotonic) else self.live_bytes.raw;
        }
    };
}

/// Zprof - A memory profiler that wraps any allocator
/// with optional thread-safe mode.
/// Tracks allocations, deallocations, and live memory usage.
pub fn Zprof(comptime thread_safe: bool) type {
    return struct {
        const Self = @This();

        child_allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex = .{},

        profiler: Profiler(thread_safe),

        pub fn init(child_allocator: std.mem.Allocator, writer: ?*std.Io.Writer) Self {
            return .{
                .child_allocator = child_allocator,
                .profiler = .init(writer),
            };
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(
            ctx: *anyopaque,
            n: usize,
            alignment: std.mem.Alignment,
            ra: usize,
        ) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));

            const ptr = blk: {
                if (thread_safe) self.mutex.lock();
                defer if (thread_safe) self.mutex.unlock();

                break :blk self.child_allocator.rawAlloc(n, alignment, ra);
            };

            if (ptr != null) {
                @branchHint(.likely);
                self.profiler.updateAlloc(n);
            }

            return ptr;
        }

        fn resize(
            ctx: *anyopaque,
            buf: []u8,
            alignment: std.mem.Alignment,
            new_len: usize,
            ret_addr: usize,
        ) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const old_len = buf.len;

            const success = blk: {
                if (thread_safe) self.mutex.lock();
                defer if (thread_safe) self.mutex.unlock();

                break :blk self.child_allocator.rawResize(
                    buf,
                    alignment,
                    new_len,
                    ret_addr,
                );
            };

            if (success) {
                @branchHint(.likely);
                const order, const diff = absDiff(new_len, old_len);
                switch (order) {
                    .gt => self.profiler.updateAlloc(diff),
                    .lt => self.profiler.updateFree(diff),
                    .eq => {},
                }
            }

            return success;
        }

        fn remap(
            context: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            new_len: usize,
            return_address: usize,
        ) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(context));
            const old_len = memory.len;

            const new_buf = blk: {
                if (thread_safe) self.mutex.lock();
                defer if (thread_safe) self.mutex.unlock();

                break :blk self.child_allocator.rawRemap(
                    memory,
                    alignment,
                    new_len,
                    return_address,
                );
            };

            if (new_buf != null) {
                @branchHint(.likely);
                const order, const diff = absDiff(new_len, old_len);
                switch (order) {
                    .gt => self.profiler.updateAlloc(diff),
                    .lt => self.profiler.updateFree(diff),
                    .eq => {},
                }
            }

            return new_buf;
        }

        fn free(
            ctx: *anyopaque,
            buf: []u8,
            alignment: std.mem.Alignment,
            ret_addr: usize,
        ) void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            {
                if (thread_safe) self.mutex.lock();
                defer if (thread_safe) self.mutex.unlock();

                self.child_allocator.rawFree(buf, alignment, ret_addr);
            }

            self.profiler.updateFree(buf.len);
        }
    };
}

inline fn absDiff(a: usize, b: usize) struct { std.math.Order, usize } {
    // in this branch integer underflow/overflow
    // is impossible
    @setRuntimeSafety(false);

    const order = std.math.order(a, b);
    const diff = switch (order) {
        .eq => 0,
        .gt => a - b,
        .lt => b - a,
    };

    return .{ order, diff };
}

test "initial state" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);

    try std.testing.expectEqual(0, zp.profiler.getAllocated());
    try std.testing.expectEqual(0, zp.profiler.getAllocCount());
    try std.testing.expectEqual(0, zp.profiler.getFreeCount());
    try std.testing.expectEqual(0, zp.profiler.getLiveBytes());
    try std.testing.expectEqual(0, zp.profiler.getLivePeak());
    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "reset" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const data = try allocator.alloc(u8, 64);
    allocator.free(data);

    zp.profiler.reset();

    try std.testing.expectEqual(0, zp.profiler.getAllocated());
    try std.testing.expectEqual(0, zp.profiler.getAllocCount());
    try std.testing.expectEqual(0, zp.profiler.getFreeCount());
    try std.testing.expectEqual(0, zp.profiler.getLiveBytes());
    try std.testing.expectEqual(0, zp.profiler.getLivePeak());
}

test "live bytes" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    try std.testing.expectEqual(0, zp.profiler.getLiveBytes());

    const data_a = try allocator.alloc(u8, 1024);
    errdefer allocator.free(data_a);
    try std.testing.expectEqual(1024, zp.profiler.getLiveBytes());

    const data_b = try allocator.create(struct { name: [8]u8 });
    errdefer allocator.destroy(data_b);
    try std.testing.expectEqual(1032, zp.profiler.getLiveBytes());

    allocator.free(data_a);
    try std.testing.expectEqual(8, zp.profiler.getLiveBytes());

    allocator.destroy(data_b);
    try std.testing.expectEqual(0, zp.profiler.getLiveBytes());

    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "partial free" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 100);
    const b = try allocator.alloc(u8, 200);
    defer allocator.free(b);

    try std.testing.expectEqual(300, zp.profiler.getLiveBytes());

    allocator.free(a);
    try std.testing.expectEqual(200, zp.profiler.getLiveBytes());
}

test "alloc count" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 32);
    const b = try allocator.alloc(u8, 32);
    const c = try allocator.alloc(u8, 32);

    try std.testing.expectEqual(3, zp.profiler.getAllocCount());
    try std.testing.expectEqual(0, zp.profiler.getFreeCount());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(2, zp.profiler.getFreeCount());

    allocator.free(c);
    try std.testing.expectEqual(3, zp.profiler.getFreeCount());
}

test "allocated is monotonic" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 128);
    try std.testing.expectEqual(128, zp.profiler.getAllocated());

    const b = try allocator.alloc(u8, 64);
    try std.testing.expectEqual(192, zp.profiler.getAllocated());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(192, zp.profiler.getAllocated());
}

test "live peak" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 256);
    try std.testing.expectEqual(256, zp.profiler.getLivePeak());

    const b = try allocator.alloc(u8, 256);
    try std.testing.expectEqual(512, zp.profiler.getLivePeak());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(512, zp.profiler.getLivePeak());
    try std.testing.expectEqual(0, zp.profiler.getLiveBytes());
}

test "live peak on resize" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    var data = try allocator.alloc(u8, 64);
    try std.testing.expectEqual(64, zp.profiler.getLivePeak());

    if (allocator.resize(data, 128)) {
        data = data.ptr[0..128];
        try std.testing.expect(zp.profiler.getLivePeak() >= 128);
    }

    allocator.free(data);
}

test "memory leak" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const data = try allocator.alloc(u8, 8);
    try std.testing.expect(zp.profiler.hasLeaks());

    allocator.free(data);
    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "partial leak" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(false) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 16);
    const b = try allocator.alloc(u8, 16);
    defer allocator.free(b);

    allocator.free(a);
    try std.testing.expect(zp.profiler.hasLeaks());
}

test "thread safe" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(true) = .init(test_allocator, null);
    const allocator = zp.allocator();

    const Context = struct {
        ctx_allocator: std.mem.Allocator,
        fn run(ctx: @This()) void {
            const buf = ctx.ctx_allocator.alloc(u8, 64) catch return;
            std.Thread.sleep(1000 * std.time.ns_per_us);
            ctx.ctx_allocator.free(buf);
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads) |*t|
        t.* = try std.Thread.spawn(
            .{},
            Context.run,
            .{Context{ .ctx_allocator = allocator }},
        );
    for (&threads) |*t| t.join();

    try std.testing.expect(!zp.profiler.hasLeaks());
    try std.testing.expectEqual(
        zp.profiler.getAllocCount(),
        zp.profiler.getFreeCount(),
    );
}
