//! zprof.zig
//!
//! Copyright (c) Andrea Vaccaro
//!
//! Zprof is a zero-overhead, zero-dependency memory profiler
//! that wraps any allocator written in Zig.
//! Tracks allocations, detects memory leaks, and logs
//! memory changes with optional thread-safe mode.
//! Version 3.0.1
//!
//! Original repository: https://github.com/andrvv/zprof

const std = @import("std");

pub const VERSION = "3.0.1";

pub const Config = struct {
    thread_safe: bool = false,
    writerFn: ?*const fn (*std.Io.Writer, bool, usize) void = null,

    allocated: bool = true,
    alloc_count: bool = true,
    free_count: bool = true,
    live_peak: bool = true,
    live_bytes: bool = true,
};

pub fn Counter(comptime thread_safe: bool, comptime T: type, value: T) type {
    return if (thread_safe) struct {
        const Self = @This();

        value: std.atomic.Value(T) align(std.atomic.cache_line) = .init(value),

        pub fn add(self: *Self, operand: T) void {
            _ = self.value.fetchAdd(operand, .monotonic);
        }

        pub fn sub(self: *Self, operand: T) void {
            _ = self.value.fetchSub(operand, .monotonic);
        }

        pub fn set(self: *Self, operand: T) void {
            self.value.store(operand, .monotonic);
        }

        pub fn get(self: *const Self) T {
            return self.value.load(.monotonic);
        }

        pub fn max(self: *Self, operand: T) void {
            _ = self.value.fetchMax(operand, .monotonic);
        }
    } else struct {
        const Self = @This();

        value: T = value,

        pub fn add(self: *Self, operand: T) void {
            self.value +|= operand;
        }

        pub fn sub(self: *Self, operand: T) void {
            self.value -|= operand;
        }

        pub fn set(self: *Self, operand: T) void {
            self.value = operand;
        }

        pub fn get(self: *const Self) T {
            return self.value;
        }

        pub fn max(self: *Self, operand: T) void {
            if (operand > self.value) self.value = operand;
        }
    };
}

/// Collects allocation, deallocation, and live memory statistics.
pub fn Profiler(comptime config: Config) type {
    return struct {
        const Self = @This();

        const DefaultCounter = Counter(config.thread_safe, usize, 0);

        /// Allocated bytes from initialization.
        /// Keeps track of total bytes requested during the program's lifetime.
        allocated: if (config.allocated) DefaultCounter else struct {} = .{},

        /// Count of allocations from alloc/realloc.
        /// Every time memory is allocated, this counter increases.
        alloc_count: if (config.alloc_count) DefaultCounter else struct {} = .{},
        /// Count of deallocations from free/realloc/deinit.
        /// Every time memory is freed, this counter increases.
        free_count: if (config.free_count) DefaultCounter else struct {} = .{},

        /// Live bytes peak.
        /// Tracks the maximum memory usage at any point during execution.
        live_peak: if (config.live_peak) DefaultCounter else struct {} = .{},
        /// Current live bytes.
        /// Shows how much memory is currently in use.
        live_bytes: if (config.live_bytes) DefaultCounter else struct {} = .{},

        writer: WriterType,
        const WriterType = if (config.writerFn != null) *std.Io.Writer else void;

        pub fn init(writer: WriterType) Self {
            return .{ .writer = writer };
        }

        /// Updates profiler simulating allocation.
        /// Called internally whenever memory is allocated.
        fn updateAlloc(self: *Self, size: usize) void {
            if (config.allocated) self.allocated.add(size);
            if (config.live_bytes) self.live_bytes.add(size);
            if (config.alloc_count) self.alloc_count.add(1);
            if (config.live_peak) self.live_peak.max(self.live_bytes.get());
            if (config.writerFn) |writerFn| writerFn(self.writer, true, size);
        }

        fn updateFree(self: *Self, size: usize) void {
            if (config.live_bytes) self.live_bytes.sub(size);
            if (config.free_count) self.free_count.add(1);
            if (config.writerFn) |writerFn| writerFn(self.writer, false, size);
        }

        /// Check if has memory leaks.
        /// Returns true if any allocations weren't properly freed.
        pub fn hasLeaks(self: *const Self) bool {
            return self.live_bytes.get() > 0;
        }

        pub fn reset(self: *Self) void {
            self.* = .init(if (config.writerFn != null) self.writer else {});
        }
    };
}

/// Zprof - A memory profiler that wraps any allocator
/// with optional thread-safe mode.
/// Tracks allocations, deallocations, and live memory usage.
pub fn Zprof(comptime config: Config) type {
    return struct {
        const Self = @This();

        child_allocator: std.mem.Allocator,
        mutex: if (config.thread_safe) std.Thread.Mutex else struct {} = .{},

        profiler: Profiler(config),

        pub fn init(child_allocator: std.mem.Allocator, writer: *std.Io.Writer) Self {
            return .{
                .child_allocator = child_allocator,
                .profiler = .init(if (config.writerFn != null) writer else {}),
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
                if (config.thread_safe) self.mutex.lock();
                defer if (config.thread_safe) self.mutex.unlock();

                break :blk self.child_allocator.rawAlloc(n, alignment, ra);
            };

            if (ptr != null) {
                @branchHint(.likely);
                // this function is protected with atomics
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
                if (config.thread_safe) self.mutex.lock();
                defer if (config.thread_safe) self.mutex.unlock();

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
                // these functions are protected with atomics
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
                if (config.thread_safe) self.mutex.lock();
                defer if (config.thread_safe) self.mutex.unlock();

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
                // these functions are protected with atomics
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
                if (config.thread_safe) self.mutex.lock();
                defer if (config.thread_safe) self.mutex.unlock();

                self.child_allocator.rawFree(buf, alignment, ret_addr);
            }

            // this function is protected with atomics
            self.profiler.updateFree(buf.len);
        }
    };
}

fn absDiff(a: usize, b: usize) struct { std.math.Order, usize } {
    // in this branch integer underflow/overflow is impossible
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
    var zp: Zprof(.{}) = .init(test_allocator, undefined);

    try std.testing.expectEqual(0, zp.profiler.allocated.get());
    try std.testing.expectEqual(0, zp.profiler.alloc_count.get());
    try std.testing.expectEqual(0, zp.profiler.free_count.get());
    try std.testing.expectEqual(0, zp.profiler.live_bytes.get());
    try std.testing.expectEqual(0, zp.profiler.live_peak.get());
    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "reset" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const data = try allocator.alloc(u8, 64);
    allocator.free(data);

    zp.profiler.reset();

    try std.testing.expectEqual(0, zp.profiler.allocated.get());
    try std.testing.expectEqual(0, zp.profiler.alloc_count.get());
    try std.testing.expectEqual(0, zp.profiler.free_count.get());
    try std.testing.expectEqual(0, zp.profiler.live_bytes.get());
    try std.testing.expectEqual(0, zp.profiler.live_peak.get());
}

test "live bytes" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    try std.testing.expectEqual(0, zp.profiler.live_bytes.get());

    const data_a = try allocator.alloc(u8, 1024);
    errdefer allocator.free(data_a);
    try std.testing.expectEqual(1024, zp.profiler.live_bytes.get());

    const data_b = try allocator.create(struct { name: [8]u8 });
    errdefer allocator.destroy(data_b);
    try std.testing.expectEqual(1032, zp.profiler.live_bytes.get());

    allocator.free(data_a);
    try std.testing.expectEqual(8, zp.profiler.live_bytes.get());

    allocator.destroy(data_b);
    try std.testing.expectEqual(0, zp.profiler.live_bytes.get());

    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "partial free" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 100);
    const b = try allocator.alloc(u8, 200);
    defer allocator.free(b);

    try std.testing.expectEqual(300, zp.profiler.live_bytes.get());

    allocator.free(a);
    try std.testing.expectEqual(200, zp.profiler.live_bytes.get());
}

test "alloc count" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 32);
    const b = try allocator.alloc(u8, 32);
    const c = try allocator.alloc(u8, 32);

    try std.testing.expectEqual(3, zp.profiler.alloc_count.get());
    try std.testing.expectEqual(0, zp.profiler.free_count.get());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(2, zp.profiler.free_count.get());

    allocator.free(c);
    try std.testing.expectEqual(3, zp.profiler.free_count.get());
}

test "allocated is monotonic" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 128);
    try std.testing.expectEqual(128, zp.profiler.allocated.get());

    const b = try allocator.alloc(u8, 64);
    try std.testing.expectEqual(192, zp.profiler.allocated.get());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(192, zp.profiler.allocated.get());
}

test "live peak" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 256);
    try std.testing.expectEqual(256, zp.profiler.live_peak.get());

    const b = try allocator.alloc(u8, 256);
    try std.testing.expectEqual(512, zp.profiler.live_peak.get());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(512, zp.profiler.live_peak.get());
    try std.testing.expectEqual(0, zp.profiler.live_bytes.get());
}

test "live peak on resize" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    var data = try allocator.alloc(u8, 64);
    try std.testing.expectEqual(64, zp.profiler.live_peak.get());

    if (allocator.resize(data, 128)) {
        data = data.ptr[0..128];
        try std.testing.expect(zp.profiler.live_peak.get() >= 128);
    }

    allocator.free(data);
}

test "memory leak" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const data = try allocator.alloc(u8, 8);
    try std.testing.expect(zp.profiler.hasLeaks());

    allocator.free(data);
    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "partial leak" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 16);
    const b = try allocator.alloc(u8, 16);
    defer allocator.free(b);

    allocator.free(a);
    try std.testing.expect(zp.profiler.hasLeaks());
}

test "thread safe" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{ .thread_safe = true }) = .init(test_allocator, undefined);
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
        zp.profiler.alloc_count.get(),
        zp.profiler.free_count.get(),
    );
}

test "writer" {
    const test_allocator = std.testing.allocator;

    var allocating: std.Io.Writer.Allocating = .init(test_allocator);
    defer allocating.deinit();
    const writer = &allocating.writer;

    const print = struct {
        fn print(writer_arg: *std.Io.Writer, is_alloc: bool, size: usize) void {
            writer_arg.print(
                "{s}={d};",
                .{ if (is_alloc) "alloc" else "free", size },
            ) catch unreachable;
        }
    }.print;

    var zp: Zprof(.{ .writerFn = print }) = .init(test_allocator, writer);
    const allocator = zp.allocator();

    const ptr = try allocator.alloc(u8, 32);
    allocator.free(ptr);

    try std.testing.expectEqualStrings("alloc=32;free=32;", writer.buffered());
    allocating.clearRetainingCapacity();

    const ptr1 = try allocator.alloc(u8, 128);
    const ptr2 = try allocator.alloc(u8, 16);
    const ptr3 = try allocator.alloc(u8, 64);
    allocator.free(ptr2);
    const ptr4 = try allocator.alloc(u8, 32);
    allocator.free(ptr3);
    allocator.free(ptr4);
    allocator.free(ptr1);

    try std.testing.expectEqualStrings(
        "alloc=128;alloc=16;alloc=64;free=16;alloc=32;free=64;free=32;free=128;",
        writer.buffered(),
    );
}
