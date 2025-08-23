//! Zprof
//!
//! Copyright (c) 2025 Andrea Vaccaro
//!
//! Zprof is a lightweight, easy-to-use
//! memory profiler that helps you track
//! allocations, detect memory leaks,
//! and logs memory changes.
//! Version 1.2.1
//!
//! Original repository: https://github.com/andrvv/zprof

const std = @import("std");

pub const VERSION = "1.2.1";
pub const SEMANTIC_VERSION = std.SemanticVersion.parse(VERSION) catch unreachable;

/// Profiler struct that tracks memory allocations and deallocations.
/// Perfect for debugging memory leaks in your applications.
pub const Profiler = struct {
    const Self = @This();

    /// Writer of output when allocation or deallocation is occurred.
    log_writer: ?*std.Io.Writer,

    /// Allocated bytes from initialization.
    /// Keeps track of total bytes requested during the program's lifetime.
    allocated: u64 = 0,

    /// Count of allocations from alloc/realloc.
    /// Every time memory is allocated, this counter increases.
    alloc_count: u64 = 0,
    /// Count of deallocations from free/realloc/deinit.
    /// Every time memory is freed, this counter increases.
    free_count: u64 = 0,

    /// Peak of live bytes.
    /// Tracks the maximum memory usage at any point during execution.
    live_peak: u64 = 0,

    /// Current live bytes.
    /// Shows how much memory is currently in use.
    live_bytes: u64 = 0,

    /// Updates profiler simulating allocation.
    /// Called internally whenever memory is allocated.
    inline fn updateAlloc(self: *Self, size: u64) void {
        // track the bytes and count
        self.allocated +|= size;
        self.live_bytes +|= size;
        self.alloc_count +|= 1;
        // update peak if needed
        self.live_peak = @max(self.live_bytes, self.live_peak);

        if (self.log_writer) |writer| writer.print("Zprof::ALLOC allocated={d}\n", .{size}) catch {};
    }

    /// Updates profiler simulating free.
    /// Called internally whenever memory is freed.
    inline fn updateFree(self: *Self, size: u64) void {
        // decrease live bytes and increment free counter
        self.live_bytes -|= size;
        self.free_count +|= 1;

        if (self.log_writer) |writer| writer.print("Zprof::FREE deallocated={d}\n", .{size}) catch {};
    }

    /// Check if has memory leaks.
    /// Returns true if any allocations weren't properly freed.
    pub inline fn hasLeaks(self: *Self) bool {
        return self.live_bytes > 0;
    }

    /// Resets all profiling statistics.
    /// Useful when you want to start tracking from a clean slate.
    pub fn reset(self: *Self) void {
        // create a empty Profiler instance
        self.* = Profiler{};
    }
};

/// Zprof - a friendly memory profiler that wraps any allocator.
/// Use this to track memory usage in your Zig projects!
pub fn Zprof(comptime thread_safe: bool) type {
    return struct {
        const Self = @This();

        /// The synchronization primitive ensuring
        /// only one thread is in the critical section.
        /// Used when thread_safe is enabled.
        mutex: std.Thread.Mutex = .{},

        /// The original allocator we're wrapping.
        /// All actual memory operations will be delegated to this.
        wrapped_allocator: *std.mem.Allocator,

        /// The profiling allocator interface.
        /// Use this in your code instead of the original allocator.
        allocator: std.mem.Allocator,

        /// The embedded profiler that keeps track of memory stats.
        /// Access this to check memory usage and detect leaks.
        profiler: Profiler,

        /// Allocates and initializes a new Zprof instance.
        /// Wraps an existing allocator with memory profiling capabilities.
        /// After, it must be freed with `deinit()` function.
        pub fn init(allocator: *std.mem.Allocator, log_writer: ?*std.Io.Writer) !*Self {
            // create our custom allocator with profiling hooks
            const zprof_ptr = try allocator.create(Self);

            zprof_ptr.* = .{
                .wrapped_allocator = allocator,
                .profiler = Profiler{ .log_writer = log_writer },
                .allocator = undefined,
            };

            zprof_ptr.allocator = std.mem.Allocator{
                .ptr = zprof_ptr,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };

            return zprof_ptr;
        }

        /// Custom allocation function that tracks memory usage.
        /// This gets called whenever memory is allocated through our allocator.
        fn alloc(
            ctx: *anyopaque,
            n: usize,
            alignment: std.mem.Alignment,
            ra: usize,
        ) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));

            if (thread_safe) self.mutex.lock();
            defer if (thread_safe) self.mutex.unlock();

            // delegate actual allocation to wrapped allocator
            const ptr = self.wrapped_allocator.rawAlloc(n, alignment, ra);

            if (ptr != null)
                // if allocation succeeded, update the profiler
                self.profiler.updateAlloc(n);

            return ptr;
        }

        /// Custom resize function that tracks changes in memory usage.
        /// This gets called when memory blocks are resized.
        fn resize(
            ctx: *anyopaque,
            buf: []u8,
            alignment: std.mem.Alignment,
            new_len: usize,
            ret_addr: usize,
        ) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const old_len = buf.len;

            if (thread_safe) self.mutex.lock();
            defer if (thread_safe) self.mutex.unlock();

            // delegate actual resize to wrapped allocator
            const resized = self.wrapped_allocator.rawResize(buf, alignment, new_len, ret_addr);

            if (resized) if (diff(new_len, old_len)) |d| {
                if (new_len > old_len) {
                    @branchHint(.likely);
                    // growing memory - count as allocation
                    self.profiler.updateAlloc(d);
                } else if (new_len < old_len)
                    // shrinking memory - count as free
                    self.profiler.updateFree(d);
            };

            return resized;
        }

        /// Custom remap function that tracks changes in memory usage.
        /// Used when memory needs to be potentially moved to a new location.
        fn remap(
            context: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            new_len: usize,
            return_address: usize,
        ) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(context));
            const old_len = memory.len;

            if (thread_safe) self.mutex.lock();
            defer if (thread_safe) self.mutex.unlock();

            // delegate actual remap to wrapped allocator
            const remapped = self.wrapped_allocator.rawRemap(memory, alignment, new_len, return_address);

            if (remapped != null) if (diff(new_len, old_len)) |d| {
                if (new_len > old_len) {
                    @branchHint(.likely);
                    // growing memory - count as allocation
                    self.profiler.updateAlloc(d);
                } else if (new_len < old_len)
                    // shrinking memory - count as free
                    self.profiler.updateFree(d);
            };

            return remapped;
        }

        /// Custom free function that tracks memory deallocation.
        /// Called whenever memory is explicitly freed.
        fn free(
            ctx: *anyopaque,
            buf: []u8,
            alignment: std.mem.Alignment,
            ret_addr: usize,
        ) void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            if (thread_safe) self.mutex.lock();
            defer if (thread_safe) self.mutex.unlock();

            // update profiler stats with old buf
            // length info after memory free
            defer self.profiler.updateFree(buf.len);

            // free the memory
            self.wrapped_allocator.rawFree(buf, alignment, ret_addr);
        }

        /// Deinitializes self.
        pub fn deinit(self: *Self) void {
            self.wrapped_allocator.destroy(self);
        }
    };
}

/// Returns the difference from 2 values.
/// Null can be returned if there is not difference.
inline fn diff(a: usize, b: usize) ?usize {
    if (a == b)
        // if a and b have the
        // same value, no diff
        return null;

    return if (a > b) a - b else b - a;
}

test "live bytes" {
    var test_allocator = std.testing.allocator;
    var zprof = try Zprof(false).init(&test_allocator, null);
    defer zprof.deinit();

    const allocator = zprof.allocator;
    try std.testing.expectEqual(0, zprof.profiler.live_bytes);

    const data_a = try allocator.alloc(u8, 1024);
    errdefer allocator.free(data_a);
    try std.testing.expectEqual(1024, zprof.profiler.live_bytes);

    const data_b = try allocator.create(struct { name: [8]u8 });
    errdefer allocator.destroy(data_b);
    try std.testing.expectEqual(1032, zprof.profiler.live_bytes);

    allocator.free(data_a);
    try std.testing.expectEqual(8, zprof.profiler.live_bytes);

    allocator.destroy(data_b);
    try std.testing.expectEqual(0, zprof.profiler.live_bytes);

    try std.testing.expect(!zprof.profiler.hasLeaks());
}

test "memory leak" {
    var test_allocator = std.testing.allocator;
    var zprof = try Zprof(false).init(&test_allocator, null);
    defer zprof.deinit();

    const allocator = zprof.allocator;

    // allocated bytes
    const data = try allocator.alloc(u8, 8);
    // expects leak because memory is not freed
    try std.testing.expect(zprof.profiler.hasLeaks());

    // expects no memory leak after free
    allocator.free(data);
    try std.testing.expect(!zprof.profiler.hasLeaks());
}
