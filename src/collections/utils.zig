//! Utility functions for collection management and error handling.
//!
//! This module provides essential utilities for the Roc compiler, including
//! out-of-memory error handling and fatal error reporting. These utilities
//! follow the "Inform Don't Block" philosophy by providing clean exit paths
//! for unrecoverable errors.

const std = @import("std");
const tracy = @import("../tracy.zig");
const builtin = @import("builtin");

const is_wasm = builtin.target.cpu.arch == .wasm32;

/// Exit the current process when we hit an out-of-memory error.
///
/// Since there's nothing we can do to recover from such an issue,
/// it's best to always exit the process with a nice message than to
/// propagate unrecoverable errors all over the compiler.
pub fn exitOnOom(err: std.mem.Allocator.Error) noreturn {
    switch (err) {
        error.OutOfMemory => {
            if (is_wasm) {
                @panic("Out of memory in WASM module");
            } else {
                const oom_message =
                    \\I ran out of memory! I can't do anything to recover, so I'm exiting.
                    \\Try reducing memory usage on your machine and then running again.
                    \\
                ;
                fatal(oom_message, .{});
            }
        },
    }
}

/// Log a fatal error and exit the process with a non-zero code.
pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    if (is_wasm) {
        // In WASM, we can't write to stderr or exit, so just panic with the message
        var buffer: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, format, args) catch "Fatal error (message too long)";
        @panic(message);
    } else {
        std.io.getStdErr().writer().print(format, args) catch unreachable;
        if (tracy.enable) {
            tracy.waitForShutdown() catch unreachable;
        }
        std.process.exit(1);
    }
}
