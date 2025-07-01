# Zprof - A cross-allocator profiler for Zig

![Version](https://img.shields.io/badge/version-0.2.6-blue)
![Zig](https://img.shields.io/badge/zig-0.14.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**Zprof** is a lightweight, easy-to-use memory profiler that helps you track allocations, detect memory leaks, and logs memory changes.

## 📖 Table of Contents

- [Zprof - A cross-allocator profiler for Zig](#zprof---a-cross-allocator-profiler-for-zig)
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
      - [Methods in logging](#methods-in-logging)
  - [📝 Examples](#-examples)
    - [Testing for Memory Leaks](#testing-for-memory-leaks)

## 📥 Installation

### Using a package manager (Recommended)

Add `Zprof` to your project's `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.2.6",
    .dependencies = .{
        .zprof = .{
            .url = "https://github.com/ANDRVV/zprof/archive/v0.2.6.zip",
            .hash = "...",
        },
    },
}
```

Then in your `build.zig`, add:

```zig
// Add Zprof as a dependency
const zprof_dep = b.dependency("zprof", .{
        .target = target,
        .optimize = optimize,
});

// Add the module to your executable
exe.root_module.addImport("zprof", zprof_dep.module("zprof"));
```

## 🚀 Quick Start

Here's how to use `Zprof` in three easy steps:

```zig
const std = @import("std");
const zprof = @import("zprof");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var gpa_allocator = gpa.allocator();
    
    // 1. Create a profiler by wrapping your allocator
    var zprof = try zprof.Zprof.init(&gpa_allocator, true); // true enables logging
    defer gpa_allocator.destroy(zprof);
    
    // 2. Use the profiler's allocator instead of your original one
    const allocator = zprof.allocator;
    
    // 3. Use the allocator as normal
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    
    // Get memory stats
    zprof.profiler.sumLog(); // Logs a summary of memory usage
    
    // Check for leaks
    std.debug.print("Has leaks: {}\n", .{zprof.profiler.hasLeaks()});
}
```

## 🔍 Usage

### Basic Usage

To start profiling memory usage, simply wrap your allocator with `Zprof`:

```zig
var zprof = try zprof.Zprof.init(&allocator, false); // false disables automatic logging
const tracked_allocator = zprof.allocator;

// Use tracked_allocator wherever you would use your original allocator
```

### Detecting Memory Leaks

`Zprof` makes it easy to detect memory leaks in your application:

```zig
// At the end of your program or test
const has_leaks = zprof.profiler.hasLeaks();
if (has_leaks) {
    // Handle leaks (e.g., report, abort in tests)
    std.debug.print("Memory leak detected!\n", .{});
    zprof.profiler.sumLog(); // Print detailed info about allocations
    return error.MemoryLeak;
}
```

### Logging Options

`Zprof` provides several logging functions to help you understand your application's memory usage:

```zig
// Log a complete summary of memory usage
zprof.profiler.sumLog();
// Sample output:
// Zperf [*]: 2048 allocated-bytes=2048 alloc-times=1 free-times=0 live-bytes=2048 live-peak-bytes=2048

// Log just allocation and deallocation counts
zprof.profiler.actionLog();
// Sample output:
// Zperf [*]: allocated-bytes=2048 alloc-times=1 free-times=0

// Log current memory usage
zprof.profiler.liveLog();
// Sample output:
// Zperf [*]: live-bytes=2048 live-peak-bytes=2048

// Log specific allocation events (useful in custom allocators)
// Is called when logging from init is enabled
zprof.profiler.allocLog(1024);
// Sample output:
// Zperf [+][myFunction]: allocated-now=1024

// Log specific deallocation events
// Is called when logging from init is enabled
zprof.profiler.freeLog(1024);
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

#### Methods in logging

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
    var arena_allocator = arena.allocator();
    
    var zprof = try zprof.Zprof.init(&arena_allocator, false);
    const allocator = zprof.allocator;
    
    // Perform allocations
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    
    // Verify no leaks
    try std.testing.expect(!zprof.profiler.hasLeaks());
}
```

---

Made with ❤️ for the Zig community
