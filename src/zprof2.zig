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

    allocated: bool = false,
    freed: bool = false,

    alloc_count: bool = false,
    free_count: bool = false,

    peak_requested: bool = false,
    live_requested: bool = true,

    last_peak_requested: bool = false,
};

pub fn UntrackedCounter(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn counter(self: *Self) Counter(T) {
            return .{
                .ptr = self,
                .vtable = &.{
                    .add = add,
                    .sub = sub,
                    .set = set,
                    .get = get,
                    .max = max,
                    .min = min,
                },
            };
        }

        fn add(_: *anyopaque, _: T) void {
            @panic("Zprof: untracked counter, enable this from Config.");
        }

        fn sub(_: *anyopaque, _: T) void {
            @panic("Zprof: untracked counter, enable this from Config.");
        }

        fn set(_: *anyopaque, _: T) void {
            @panic("Zprof: untracked counter, enable this from Config.");
        }

        fn get(_: *const anyopaque) T {
            @panic("Zprof: untracked counter, enable this from Config.");
        }

        fn max(_: *anyopaque, _: T) void {
            @panic("Zprof: untracked counter, enable this from Config.");
        }

        fn min(_: *anyopaque, _: T) void {
            @panic("Zprof: untracked counter, enable this from Config.");
        }
    };
}

pub fn ThreadUnsafeCounter(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn counter(self: *Self) Counter(T) {
            return .{
                .ptr = self,
                .vtable = &.{
                    .add = add,
                    .sub = sub,
                    .set = set,
                    .get = get,
                    .max = max,
                    .min = min,
                },
            };
        }

        fn add(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.value +|= operand;
        }

        fn sub(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.value -|= operand;
        }

        fn set(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.value = operand;
        }

        fn get(ctx: *const anyopaque) T {
            const self: *const Self = @ptrCast(@alignCast(ctx));
            return self.value;
        }

        fn max(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (operand > self.value) self.value = operand;
        }

        fn min(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (operand < self.value) self.value = operand;
        }
    };
}

pub fn ThreadSafeCounter(comptime T: type) type {
    return struct {
        const Self = @This();

        value: std.atomic.Value(T) align(std.atomic.cache_line),

        pub fn init(value: T) Self {
            return .{ .value = .init(value) };
        }

        pub fn counter(self: *Self) Counter(T) {
            return .{
                .ptr = self,
                .vtable = &.{
                    .add = add,
                    .sub = sub,
                    .set = set,
                    .get = get,
                    .max = max,
                    .min = min,
                },
            };
        }

        fn add(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = self.value.fetchAdd(operand, .monotonic);
        }

        fn sub(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = self.value.fetchSub(operand, .monotonic);
        }

        fn set(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.value.store(operand, .monotonic);
        }

        fn get(ctx: *const anyopaque) T {
            const self: *const Self = @ptrCast(@alignCast(ctx));
            return self.value.load(.monotonic);
        }

        fn max(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = self.value.fetchMax(operand, .monotonic);
        }

        fn min(ctx: *anyopaque, operand: T) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = self.value.fetchMin(operand, .monotonic);
        }
    };
}

pub fn Counter(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,

        const VTable = struct {
            add: *const fn (*anyopaque, operand: T) void,
            sub: *const fn (*anyopaque, operand: T) void,
            set: *const fn (*anyopaque, operand: T) void,
            get: *const fn (*const anyopaque) T,
            max: *const fn (*anyopaque, operand: T) void,
            min: *const fn (*anyopaque, operand: T) void,
        };

        pub inline fn add(self: *Self, operand: T) void {
            return self.vtable.add(self.ptr, operand);
        }

        pub inline fn sub(self: *Self, operand: T) void {
            return self.vtable.sub(self.ptr, operand);
        }

        pub inline fn set(self: *Self, operand: T) void {
            return self.vtable.set(self.ptr, operand);
        }

        pub inline fn get(self: *const Self) T {
            return self.vtable.get(self.ptr);
        }

        pub inline fn max(self: *Self, operand: T) void {
            return self.vtable.max(self.ptr, operand);
        }

        pub inline fn min(self: *Self, operand: T) void {
            return self.vtable.min(self.ptr, operand);
        }
    };
}

/// Collects allocation, deallocation, and live memory statistics.
pub fn Profiler(comptime config: Config) type {
    return struct {
        const Self = @This();

        const CounterInterface = Counter(usize);
        const CounterImpl = if (config.thread_safe)
            ThreadSafeCounter(usize)
        else
            ThreadUnsafeCounter(usize);

        allocated: CounterInterface,
        freed: CounterInterface,
        alloc_count: CounterInterface,
        free_count: CounterInterface,
        peak_requested: CounterInterface,
        live_requested: CounterInterface,
        last_peak_requested: CounterInterface,

        writer: WriterType,
        const WriterType = if (config.writerFn != null) *std.Io.Writer else void;

        pub fn init(writer: WriterType) Self {
            var self: Self = undefined;
            self.writer = writer;

            inline for (std.meta.fields(Self)) |field| {
                if (field.type == CounterInterface) {
                    var k = CounterImpl.init(0);
                    @field(self, field.name) = k.counter();
                }
            }

            return self;
        }

        /// Updates profiler simulating allocation.
        /// Called internally whenever memory is allocated.
        fn updateAlloc(self: *Self, size: usize) void {
            if (config.allocated) self.allocated.add(size);
            if (config.live_requested) self.live_requested.add(size);
            if (config.alloc_count) self.alloc_count.add(1);
            if (config.peak_requested) self.peak_requested.max(self.peak_requested.get());
            if (config.writerFn) |writerFn| writerFn(self.writer, true, size);
        }

        fn updateFree(self: *Self, size: usize) void {
            if (config.live_requested) self.live_requested.sub(size);
            if (config.free_count) self.free_count.add(1);
            if (config.writerFn) |writerFn| writerFn(self.writer, false, size);
        }

        /// Check if has memory leaks.
        /// Returns true if any allocations weren't properly freed.
        pub fn hasLeaks(self: *const Self) bool {
            if (!config.live_requested)
                @panic("Zprof: to know this information, enable live_requested on Config.");
            return self.live_requested.get() != 0;
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
    try std.testing.expectEqual(0, zp.profiler.live_requested.get());
    try std.testing.expectEqual(0, zp.profiler.peak_requested.get());
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
    try std.testing.expectEqual(0, zp.profiler.live_requested.get());
    try std.testing.expectEqual(0, zp.profiler.peak_requested.get());
}

test "live bytes" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    try std.testing.expectEqual(0, zp.profiler.live_requested.get());

    const data_a = try allocator.alloc(u8, 1024);
    errdefer allocator.free(data_a);
    try std.testing.expectEqual(1024, zp.profiler.live_requested.get());

    const data_b = try allocator.create(struct { name: [8]u8 });
    errdefer allocator.destroy(data_b);
    try std.testing.expectEqual(1032, zp.profiler.live_requested.get());

    allocator.free(data_a);
    try std.testing.expectEqual(8, zp.profiler.live_requested.get());

    allocator.destroy(data_b);
    try std.testing.expectEqual(0, zp.profiler.live_requested.get());

    try std.testing.expect(!zp.profiler.hasLeaks());
}

test "partial free" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    const a = try allocator.alloc(u8, 100);
    const b = try allocator.alloc(u8, 200);
    defer allocator.free(b);

    try std.testing.expectEqual(300, zp.profiler.live_requested.get());

    allocator.free(a);
    try std.testing.expectEqual(200, zp.profiler.live_requested.get());
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
    try std.testing.expectEqual(256, zp.profiler.peak_requested.get());

    const b = try allocator.alloc(u8, 256);
    try std.testing.expectEqual(512, zp.profiler.peak_requested.get());

    allocator.free(a);
    allocator.free(b);
    try std.testing.expectEqual(512, zp.profiler.peak_requested.get());
    try std.testing.expectEqual(0, zp.profiler.live_requested.get());
}

test "live peak on resize" {
    const test_allocator = std.testing.allocator;
    var zp: Zprof(.{}) = .init(test_allocator, undefined);
    const allocator = zp.allocator();

    var data = try allocator.alloc(u8, 64);
    try std.testing.expectEqual(64, zp.profiler.peak_requested.get());

    if (allocator.resize(data, 128)) {
        data = data.ptr[0..128];
        try std.testing.expect(zp.profiler.peak_requested.get() >= 128);
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
