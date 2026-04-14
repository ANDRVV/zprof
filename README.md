# Zprof - A cross-allocator profiler for Zig

![Version](https://img.shields.io/badge/version-4.0.0-blue)
![Zig](https://img.shields.io/badge/zig-0.15.1-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**Zprof** is a zero-dependency memory profiler that wraps any allocator written in Zig.
It minimizes overhead by compiling away any metric you don't enable — you pay only for what you measure.
Tracks allocations, detects memory leaks, and logs memory changes with optional thread-safe mode.

Developed for use in Debug or official modes, it guarantees nearly the same performance as the wrapped allocator.
Zprof's development is based on a primary priority: ease of use, improved efficiency, readability, clean, minimal, and well-documented code.

## 📖 Table of Contents

- [Zprof - A cross-allocator profiler for Zig](#zprof---a-cross-allocator-profiler-for-zig)
  - [📖 Table of Contents](#-table-of-contents)
  - [🧪 Benchmark \& Testing](#-benchmark--testing)
  - [📥 Installation](#-installation)
    - [Using a package manager](#using-a-package-manager)
  - [🚀 Quick Start](#-quick-start)
  - [🔍 Usage](#-usage)
    - [Basic Usage](#basic-usage)
    - [Thread safe mode](#thread-safe-mode)
    - [Logging](#logging)
    - [Detecting Memory Leaks](#detecting-memory-leaks)
    - [Configuration](#configuration)
    - [Full Profiler API](#full-profiler-api)
      - [Fields](#fields)
      - [Methods](#methods)
  - [📝 Examples](#-examples)
    - [Testing for Memory Leaks](#testing-for-memory-leaks)

## 🧪 Benchmark & Testing

Run the test suite with:

```sh
zig build test
```

Run the benchmark with:

```sh
zig build benchmark
```

Benchmarked with `cpu=i7-12700H` (all configs enabled)
```
Alloc/free benchmark [bytes=16 ops=10000000]
Raw allocator:   tot=80274902ns
Zprof allocator: tot=102280564ns
Baseline overhead (Wrapper): +7.87%
Bookkeeping overhead:        +19.54%
Total overhead:              +27.41%
```

## 📥 Installation

### Using a package manager

Add `Zprof` to your project's `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "4.0.0",
    .dependencies = .{
        .zprof = .{
            .url = "https://github.com/ANDRVV/zprof/archive/v4.0.0.zip",
            .hash = "...",
        },
    },
}
```

Then in your `build.zig`, add:

```zig
const zprof_dep = b.dependency("zprof", .{
        .target = target,
        .optimize = optimize,
});

exe.root_module.addImport("zprof", zprof_dep.module("zprof"));
```

Else you can put `zprof.zig` in your project's path and import it.

Zig version 0.15.1 or newer is required to compile Zprof.

## 🚀 Quick Start

Here's how to use `Zprof` in three easy steps:

```zig
const std = @import("std");
const Zprof = @import("zprof.zig").Zprof;

pub fn main() !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 1. Create a profiler by wrapping your allocator with a Config
    var zprof: Zprof(.{}) = .init(gpa.allocator(), stdout);
    // .{} uses the default config (thread_safe = false, all metrics enabled)

    // 2. Use the profiler's allocator instead of your original one
    const allocator = zprof.allocator();

    // 3. Use the allocator as normal
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    stdout.print("Has leaks: {}\n", .{zprof.profiler.hasLeaks()}) catch {};
}
```

## 🔍 Usage

### Basic Usage

To start profiling memory usage, simply wrap your allocator with `Zprof`:

```zig
var zprof: Zprof(.{}) = .init(allocator, undefined); // .{} uses default config
const tracked_allocator = zprof.allocator();
```

### Thread safe mode

To use `Zprof` with mutex protection on the child allocator, enable thread-safe mode via `Config`:

```zig
var zprof: Zprof(.{ .thread_safe = true }) = .init(allocator, undefined);
const tracked_allocator = zprof.allocator();
```

### Logging

Logging is configured by providing a `writerFn` in the `Config` struct. The function receives the writer, a boolean indicating allocation or deallocation, and the size in bytes.

```zig
fn myLogger(writer: *std.Io.Writer, is_alloc: bool, size: usize) void {
    writer.print("{s}={d};\n", .{ if (is_alloc) "alloc" else "free", size }) catch {};
}

var zprof: Zprof(.{ .writerFn = myLogger }) = .init(allocator, writer);
const tracked_allocator = zprof.allocator();

const data = try tracked_allocator.alloc(u8, 1024); // prints: alloc=1024;
tracked_allocator.free(data);                        // prints: free=1024;
```

### Detecting Memory Leaks

`Zprof` makes it easy to detect memory leaks in your application:

```zig
if (zprof.profiler.hasLeaks()) {
    std.debug.print("Memory leak detected!\n", .{});
    return error.MemoryLeak;
}
```

### Configuration

`Zprof` accepts a comptime `Config` struct that lets you enable or disable individual metrics and features, reducing overhead for metrics you don't need:

```zig
pub const Config = struct {
    thread_safe: bool = false,
    writerFn: ?*const fn (*std.Io.Writer, bool, usize) void = null,

    allocated: bool = true,      // tracks total bytes allocated
    freed: bool = true,          // tracks total bytes deallocated
    alloc_count: bool = true,    // tracks number of allocations
    free_count: bool = true,     // tracks number of deallocations
    peak_requested: bool = true, // tracks peak of requested bytes
    live_requested: bool = true, // tracks non-freed requested bytes
};
```

Example — only track live bytes and leaks, with thread safety:

```zig
var zprof: Zprof(.{
    .thread_safe = true,
    .allocated = false,
    .freed = .false,
    .alloc_count = false,
    .free_count = false,
    .peak_requested = false,
}) = .init(allocator, undefined);
```

### Full Profiler API

Access profiling data through `zprof.profiler`. Each metric is a `Counter` and exposes a `.get()` method.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `allocated` | `Counter` | Total bytes allocated since initialization |
| `freed` | `Counter` | Total bytes deallocated since initialization |
| `alloc_count` | `Counter` | Number of allocation operations |
| `free_count` | `Counter` | Number of deallocation operations |
| `peak_requested` | `Counter` | Maximum memory usage at any point |
| `live_requested` | `Counter` | Current memory usage |

```zig
std.debug.print("Allocated: {d}\n", .{zprof.profiler.allocated.get()});
std.debug.print("Freed: {d}\n", .{zprof.profiler.freed.get()});
std.debug.print("Live bytes: {d}\n", .{zprof.profiler.live_requested.get()});
std.debug.print("Peak: {d}\n",      .{zprof.profiler.peak_requested.get()});
std.debug.print("Allocs: {d}\n",    .{zprof.profiler.alloc_count.get()});
std.debug.print("Frees: {d}\n",     .{zprof.profiler.free_count.get()});
```

#### Methods

| Method | Return type | Description |
|--------|-------------|-------------|
| `hasLeaks()` | `bool` | Returns `true` if there are active memory leaks |
| `reset()` | `void` | Resets all profiling statistics |

## 📝 Examples

### Testing for Memory Leaks

```zig
test "no memory leaks" {
    var zprof: Zprof(.{}) = .init(std.testing.allocator, undefined);
    const allocator = zprof.allocator();

    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    try std.testing.expect(!zprof.profiler.hasLeaks());
}
```

---

Made with ❤️ for the Zig community

Copyright (c) 2026 Andrea Vaccaro
