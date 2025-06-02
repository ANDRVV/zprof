//! Zprof
//!
//! Copyright (c) 2025 Andrea Vaccaro
//!
//! Zprof is a lightweight, easy-to-use memory profiler that helps
//! you track allocations, detect memory leaks, and logs memory changes.

const std = @import("std");

pub const VERSION = "0.2.6";
pub const SEMANTIC_VERSION = std.SemanticVersion.parse(VERSION) catch unreachable;

/// Profiler struct that tracks memory allocations and deallocations.
/// Perfect for debugging memory leaks in your applications.
pub const Profiler = struct {
    const Self = @This();

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

    /// Check if has memory leaks.
    /// Returns true if any allocations weren't properly freed.
    pub inline fn hasLeaks(self: *Self) bool {
        // if counts don't match or there's still memory around, we have leaks
        return (self.alloc_count != self.free_count) or (self.live_bytes > 0);
    }

    /// Resets all profiling statistics.
    /// Useful when you want to start tracking from a clean slate.
    pub inline fn reset(self: *Self) void {
        // create a Profiler instance
        self.* = Profiler{};
    }

    /// Logs a summary of all profiling statistics.
    /// Great for getting a complete overview of memory usage.
    pub fn sumLog(self: *Self) void {
        std.log.info(
            "Zprof [*]: allocated-bytes={d} alloc-times={d} free-times={d} live-bytes={d} live-peak-bytes={d}",
            .{
                self.allocated,
                self.alloc_count,
                self.free_count,
                self.live_bytes,
                self.live_peak,
            },
        );
    }

    /// Logs allocation and deallocation counts.
    /// Useful for tracking how many memory operations occurred.
    pub fn actionLog(self: *Self) void {
        std.log.info("Zprof [*]: allocated-bytes={d} alloc-times={d} free-times={d}", .{ self.allocated, self.alloc_count, self.free_count });
    }

    /// Logs current memory usage statistics.
    /// Shows how much memory is currently active and the highest it's been.
    pub inline fn liveLog(self: *Self) void {
        std.log.info("Zprof [*]: live-bytes={d} live-peak-bytes={d}", .{
            self.live_bytes,
            self.live_peak,
        });
    }

    /// Logs a single allocation event with the function name.
    /// Helps trace where allocations are happening in your code.
    pub inline fn allocLog(self: *Self, allocated_now: usize) void {
        _ = self;

        std.log.info("Zprof [+][{s}]: allocated-now={d}", .{
            @src().fn_name,
            allocated_now,
        });
    }

    /// Logs a single deallocation event with the function name.
    /// Helps trace where deallocations are happening in your code.
    pub inline fn freeLog(self: *Self, deallocated_now: usize) void {
        _ = self;

        std.log.info("Zprof [-][{s}]: deallocated-now={d}", .{
            @src().fn_name,
            deallocated_now,
        });
    }

    /// Updates profiler simulating allocation.
    /// Called internally whenever memory is allocated.
    fn updateAlloc(self: *Self, size: u64) void {
        // track the bytes and count
        self.allocated += size;
        self.live_bytes += size;
        self.alloc_count += 1;
        // update peak if needed
        self.live_peak = @max(self.live_bytes, self.live_peak);
    }

    /// Updates profiler simulating free.
    /// Called internally whenever memory is freed.
    fn updateFree(self: *Self, size: u64) void {
        // decrease live bytes and increment free counter
        self.live_bytes -= size;
        self.free_count += 1;
    }

    /// Updates profiler simulating deinit.
    /// Called when cleaning up all memory at once.
    fn updateDeinit(self: *Self) void {
        // consider everything freed
        self.live_bytes = 0;
        self.free_count += self.alloc_count;
    }
};

/// Zprof - a friendly memory profiler that wraps any allocator.
/// Use this to track memory usage in your Zig projects!
pub const Zprof = struct {
    const Self = @This();

    /// The original allocator we're wrapping.
    /// All actual memory operations will be delegated to this.
    wrapped_allocator: *std.mem.Allocator,

    /// The profiling allocator interface.
    /// Use this in your code instead of the original allocator.
    allocator: std.mem.Allocator = undefined,

    /// The embedded profiler that keeps track of memory stats.
    /// Access this to check memory usage and detect leaks.
    profiler: Profiler,

    /// Controls whether logging is enabled.
    /// When true, allocation events can be logged to stdout.
    log: bool,

    /// Initialize a new Zprof instance.
    /// Wraps an existing allocator with memory profiling capabilities.
    pub fn init(allocator: *std.mem.Allocator, log: bool) !*Self {
        // create our custom allocator with profiling hooks
        const zprof_ptr = try allocator.create(Zprof);

        zprof_ptr.* = .{
            .wrapped_allocator = allocator,
            .profiler = Profiler{},
            .log = log,
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
    fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Zprof = @ptrCast(@alignCast(ctx));

        // delegate actual allocation to wrapped allocator
        const ptr = self.wrapped_allocator.rawAlloc(n, alignment, ra);

        if (ptr != null) {
            // if allocation succeeded, update the profiler
            self.profiler.updateAlloc(n);

            // if enabled, logs allocated memory
            if (self.log) self.profiler.allocLog(n);

            return ptr;
        }

        return null;
    }

    /// Custom resize function that tracks changes in memory usage.
    /// This gets called when memory blocks are resized.
    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Zprof = @ptrCast(@alignCast(ctx));

        const old_len = buf.len;

        // delegate actual resize to wrapped allocator
        const resized = self.wrapped_allocator.rawResize(buf, alignment, new_len, ret_addr);

        if (resized) {
            const diff = if (new_len > old_len) new_len - old_len else old_len - new_len;

            if (new_len > old_len) {
                @branchHint(.likely);
                // growing memory - count as allocation
                self.profiler.updateAlloc(diff);

                // if enabled, logs allocated memory
                if (self.log) self.profiler.allocLog(diff);
            } else if (new_len < old_len) {
                // shrinking memory - count as free
                self.profiler.updateFree(@abs(diff));

                // if enabled, logs freed memory
                if (self.log) self.profiler.freeLog(diff);
            }

            // if diff is 0, no allocation or free has been made
        }

        return resized;
    }

    /// Custom remap function that tracks changes in memory usage.
    /// Used when memory needs to be potentially moved to a new location.
    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *Zprof = @ptrCast(@alignCast(context));

        const old_len = memory.len;

        // delegate actual remap to wrapped allocator
        const remapped = self.wrapped_allocator.rawRemap(memory, alignment, new_len, return_address);

        if (remapped != null) {
            const diff = if (new_len > old_len) new_len - old_len else old_len - new_len;

            if (new_len > old_len) {
                @branchHint(.likely);
                // growing memory - count as allocation
                self.profiler.updateAlloc(diff);

                // if enabled, logs allocated memory
                if (self.log) self.profiler.allocLog(diff);
            } else if (new_len < old_len) {
                // shrinking memory - count as free
                self.profiler.updateFree(@abs(diff));

                // if enabled, logs freed memory
                if (self.log) self.profiler.freeLog(diff);
            }

            // if diff is 0, no allocation or free has been made
        }

        return remapped;
    }

    /// Custom free function that tracks memory deallocation.
    /// Called whenever memory is explicitly freed.
    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *Zprof = @ptrCast(@alignCast(ctx));

        // update profiler stats first
        self.profiler.updateFree(buf.len);
        // if enabled, logs freed memory
        if (self.log) self.profiler.freeLog(buf.len);

        // then actually free the memory
        return self.wrapped_allocator.rawFree(buf, alignment, ret_addr);
    }
};
