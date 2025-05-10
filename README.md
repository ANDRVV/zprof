# zprof - A cross-allocator profiler for Zig

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Zig](https://img.shields.io/badge/zig-0.14.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

`zprof` is a lightweight, easy-to-use memory profiler that helps you track allocations, detect memory leaks, and logs memory changes.

## 📖 Table of Contents

- [zprof - A cross-allocator profiler for Zig](#zprof---a-cross-allocator-profiler-for-zig)
  - [📖 Table of Contents](#-table-of-contents)
  - [📥 Installation](#-installation)
    - [Using a package manager (Recommended)](#using-a-package-manager-recommended)
  - [🚀 Quick Start](#-quick-start)
  - [🔍 Usage](#-usage)
    - [Basic Usage](#basic-usage)
    - [Detecting Memory Leaks](#detecting-memory-leaks)
    - [Logging Options](#logging-options)
    - [Full Profiler API](#full-profiler-api)
      - [Fields](#fields)
      - [Methods](#methods)
      - [Methods in logging:](#methods-in-logging)
  - [📝 Examples](#-examples)
    - [Testing for Memory Leaks](#testing-for-memory-leaks)
    - [Tracking Peak Memory Usage](#tracking-peak-memory-usage)

## 📥 Installation

### Using a package manager (Recommended)

Add `zprof` to your project's `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .zprof = .{
            .url = "https://github.com/ANDRVV/zprof/archive/v0.1.0.zip",
            .hash = "...",
        },
    },
}
```

Then in your `build.zig`, add:

```zig
// Add zprof as a dependency
const zprof_dep = b.dependency("zprof", .{
    .target = target,
    .optimize = optimize,
});

// Add the module to your executable
exe.addModule("zprof", zprof_dep.module("zprof"));
```

## 🚀 Quick Start

Here's how to use `zprof` in three easy steps:

```zig
const std = @import("std");
const zprof = @import("zprof");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    // 1. Create a profiler by wrapping your allocator
    var prof = zprof.Zprof.init(&gpa.allocator, true); // true enables logging
    
    // 2. Use the profiler's allocator instead of your original one
    const allocator = prof.allocator;
    
    // 3. Use the allocator as normal
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    
    // Get memory stats
    prof.profiler.sumLog(); // Logs a summary of memory usage
    
    // Check for leaks
    std.debug.print("Has leaks: {}\n", .{prof.profiler.hasLeaks()});
}
```

## 🔍 Usage

### Basic Usage

To start profiling memory usage, simply wrap your allocator with `Zprof`:

```zig
var prof = zprof.Zprof.init(&allocator, false); // false disables automatic logging
const tracked_allocator = prof.allocator;

// Use tracked_allocator wherever you would use your original allocator
```

### Detecting Memory Leaks

`zprof` makes it easy to detect memory leaks in your application:

```zig
// At the end of your program or test
const has_leaks = prof.profiler.hasLeaks();
if (has_leaks) {
    // Handle leaks (e.g., report, abort in tests)
    std.debug.print("Memory leak detected!\n", .{});
    prof.profiler.sumLog(); // Print detailed info about allocations
    return error.MemoryLeak;
}
```

### Logging Options

`zprof` provides several logging functions to help you understand your application's memory usage:

```zig
// Log a complete summary of memory usage
prof.profiler.sumLog();
// Sample output:
// Zperf [*]: 2048 allocated-bytes=2048 alloc-times=1 free-times=0 live-bytes=2048 live-peak-bytes=2048

// Log just allocation and deallocation counts
prof.profiler.actionLog();
// Sample output:
// Zperf [*]: allocated-bytes=2048 alloc-times=1 free-times=0

// Log current memory usage
prof.profiler.liveLog();
// Sample output:
// Zperf [*]: live-bytes=2048 live-peak-bytes=2048

// Log specific allocation events (useful in custom allocators)
prof.profiler.allocLog(1024);
// Sample output:
// Zperf [+][myFunction]: allocated-now=1024

// Log specific deallocation events
prof.profiler.freeLog(1024);
// Sample output:
// Zperf [-][myFunction]: deallocated-now=1024
```

### Full Profiler API

The `Profiler` struct contains several fields and methods:

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `allocated` | `u64` | Total bytes allocated since initialization |
| `alloc_count` | `u64` | Number of allocation operations |
| `free_count` | `u64` | Number of deallocation operations |
| `live_peak` | `u64` | Maximum memory usage at any point |
| `live_bytes` | `u64` | Current memory usage |

#### Methods

| Method | Description |
|--------|-------------|
| `hasLeaks()` | Returns `true` if there are memory leaks |
| `reset()` | Resets all profiling statistics |
| `sumLog()` | Logs a summary of all memory statistics |
| `actionLog()` | Logs allocation and deallocation counts |
| `liveLog()` | Logs current memory usage |

#### Methods in logging:

| Method | Description |
|--------|-------------|
| `allocLog(size)` | Logs allocation from allocator calls |
| `freeLog(size)` | Logs deallocation from allocator calls |

## 📝 Examples

### Testing for Memory Leaks

```zig
test "no memory leaks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    
    var prof = zprof.Zprof.init(&arena.allocator, false);
    const allocator = prof.allocator;
    
    // Perform allocations
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    
    // Verify no leaks
    try std.testing.expect(!prof.profiler.hasLeaks());
}
```

### Tracking Peak Memory Usage

```zig
fn processLargeData(allocator: std.mem.Allocator, data: []const u8) !void {
    var buffer = try allocator.alloc(u8, data.len * 2);
    defer allocator.free(buffer);
    
    // Process data...
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var prof = zprof.Zprof.init(&gpa.allocator, false);
    const allocator = prof.allocator;
    
    const data = try loadData(allocator);
    defer allocator.free(data);
    
    try processLargeData(allocator, data);
    
    // Log peak memory usage
    std.debug.print("Peak memory usage: {} bytes\n", .{prof.profiler.live_peak});
}
```

---

Made with ❤️ for the Zig community