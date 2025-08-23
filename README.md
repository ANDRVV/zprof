<br><br>

<div align="center">
  <img alt="Zprof" src="https://github.com/andrvv/zprof/blob/main/assets/zprof-logo.png">
</div>

<br><br>

## The Zprof cross-allocator profiler

Zprof is a cross-allocator wrapper for profiling memory data.

Developed for use in Debug or official modes, it guarantees nearly the same performance as the wrapped allocator.
Zprof's development is based on a primary priority: ease of use, improved efficiency, readability, clean, minimal, and well-documented code.

## 📖 Table of Contents

- [The Zprof cross-allocator profiler](#the-zprof-cross-allocator-profiler)
- [📖 Table of Contents](#-table-of-contents)
- [📥 Installation](#-installation)
  - [Using a package manager](#using-a-package-manager)
- [🚀 Quick Start](#-quick-start)
- [🔍 Usage](#-usage)
  - [Basic Usage](#basic-usage)
  - [Thread safe mode](#thread-safe-mode)
  - [Logging](#logging)
  - [Detecting Memory Leaks](#detecting-memory-leaks)
  - [Full Profiler API](#full-profiler-api)
    - [Fields](#fields)
    - [Methods](#methods)
- [📝 Examples](#-examples)
  - [Testing for Memory Leaks](#testing-for-memory-leaks)

## 📥 Installation

### Using a package manager

Add `Zprof` to your project's `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "1.3.0",
    .dependencies = .{
        .zprof = .{
            .url = "https://github.com/ANDRVV/zprof/archive/v1.3.0.zip",
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

Else you can put `zprof.zig` in your project's path and import it.

Zig version 0.15.1 or newer is required to compile Zprof

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
    var gpa_allocator = gpa.allocator();

    // 1. Create a profiler by wrapping your allocator
    var zprof = try Zprof(false).init(&gpa_allocator, stdout);
    // false disable thread-safe mode and passing in a writer enables logging

    defer zprof.deinit(); // deallocates Zprof instance

    // 2. Use the profiler's allocator instead of your original one
    const allocator = zprof.allocator;

    // 3. Use the allocator as normal
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    // Check for leaks
    stdout.print("Has leaks: {}\n", .{zprof.profiler.hasLeaks()}) catch {};
}
```

## 🔍 Usage

### Basic Usage

To start profiling memory usage, simply wrap your allocator with `Zprof`:

```zig
var zprof = try Zprof(false).init(&allocator, null); // on init, null disables automatic logging
const tracked_allocator = zprof.allocator;
```

### Thread safe mode

To use `Zprof` with mutex, you must enable thread-safe mode:

```zig
var zprof = try Zprof(true).init(&allocator, null); // true enables thread-safe mode
const tracked_allocator = zprof.allocator;
```

### Logging

If logging is enabled, logs allocated/deallocated bytes when allocator
allocates or deallocates.

```zig
var zprof = try Zprof(false).init(&allocator, arraylist_writer); // Passing in a writer enables automatic logging
const tracked_allocator = zprof.allocator;

const data = try allocator.alloc(u8, 1024); // prints: Zprof::ALLOC allocated=1024
allocator.free(data); // prints: Zprof::FREE deallocated=1024
```

### Detecting Memory Leaks

`Zprof` makes it easy to detect memory leaks in your application:

```zig
// At the end of your program or test
const has_leaks = zprof.profiler.hasLeaks();
if (has_leaks) {
    // Handle leaks (e.g., report, abort in tests)
    std.debug.print("Memory leak detected!\n", .{});
    return error.MemoryLeak;
}
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

## 📝 Examples

### Testing for Memory Leaks

```zig
test "no memory leaks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();
    
    var zprof = try Zprof(false).init(&arena_allocator, null);
    defer zprof.deinit();

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

Copyright (c) 2025 Andrea Vaccaro
