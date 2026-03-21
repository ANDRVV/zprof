# The Zprof cross-allocator profiler

![Version](https://img.shields.io/badge/version-2.0.0-blue)
![Zig](https://img.shields.io/badge/zig-0.15.1-orange)
![License](https://img.shields.io/badge/license-MIT-green)

Zprof is a zero-overhead, zero-dependency memory profiler that wraps any allocator written in Zig.
Tracks allocations, detects memory leaks, and logs memory changes with optional thread-safe mode.

<br>

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
      - [Methods](#methods)
  - [📝 Examples](#-examples)
    - [Testing for Memory Leaks](#testing-for-memory-leaks)

## 📥 Installation

### Using a package manager

Add `Zprof` to your project's `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "2.0.0",
    .dependencies = .{
        .zprof = .{
            .url = "https://github.com/ANDRVV/zprof/archive/v2.0.0.zip",
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

    // 1. Create a profiler by wrapping your allocator
    var zprof: Zprof(false) = .init(gpa.allocator(), stdout);
    // false disables thread-safe mode, passing a writer enables logging

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
var zprof: Zprof(false) = .init(allocator, null); // null disables automatic logging
const tracked_allocator = zprof.allocator();
```

### Thread safe mode

To use `Zprof` with mutex protection on the child allocator, enable thread-safe mode:

```zig
var zprof: Zprof(true) = .init(allocator, null); // true enables thread-safe mode
const tracked_allocator = zprof.allocator();
```

### Logging

If logging is enabled, Zprof prints allocated/deallocated bytes on every allocation and deallocation.

```zig
var zprof: Zprof(false) = .init(allocator, writer); // passing a writer enables logging
const tracked_allocator = zprof.allocator();

const data = try tracked_allocator.alloc(u8, 1024); // prints: Zprof::ALLOC allocated=1024
tracked_allocator.free(data);                        // prints: Zprof::FREE deallocated=1024
```

### Detecting Memory Leaks

`Zprof` makes it easy to detect memory leaks in your application:

```zig
if (zprof.profiler.hasLeaks()) {
    std.debug.print("Memory leak detected!\n", .{});
    return error.MemoryLeak;
}
```

### Full Profiler API

#### Methods

| Method | Return type | Description |
|--------|-------------|-------------|
| `getAllocated()` | `usize` | Total bytes allocated since initialization |
| `getAllocCount()` | `usize` | Number of allocation operations |
| `getFreeCount()` | `usize` | Number of deallocation operations |
| `getLivePeak()` | `usize` | Maximum memory usage at any point |
| `getLiveBytes()` | `usize` | Current memory usage |
| `hasLeaks()` | `bool` | Returns `true` if there are active memory leaks |
| `reset()` | `void` | Resets all profiling statistics |

## 📝 Examples

### Testing for Memory Leaks

```zig
test "no memory leaks" {
    var zprof: Zprof(false) = .init(std.testing.allocator, null);
    const allocator = zprof.allocator();

    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    try std.testing.expect(!zprof.profiler.hasLeaks());
}
```

---

Made with ❤️ for the Zig community

Copyright (c) 2026 Andrea Vaccaro