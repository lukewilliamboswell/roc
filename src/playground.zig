//! Main WASM module for the Roc playground.
//! This module provides the interface between JavaScript and the Roc compiler.

const std = @import("std");
const parse = @import("check/parse.zig");
const base = @import("base.zig");
const WasmFilesystem = @import("playground/WasmFilesystem.zig");
const reporting = @import("reporting.zig");

const ModuleEnv = base.ModuleEnv;

// Use a fixed buffer allocator to avoid posix dependencies
var buffer: [1024 * 1024 * 16]u8 = undefined; // 16MB buffer
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();

// Minimal result structure for incremental testing
const PlaygroundResult = struct {
    module_env: *ModuleEnv,
    parse_ast: ?parse.AST = null,
    tokenize_reports: std.ArrayList(reporting.Report),
    parse_reports: std.ArrayList(reporting.Report),
    error_count: u32 = 0,
    warning_count: u32 = 0,

    pub fn deinit(self: *PlaygroundResult) void {
        if (self.parse_ast) |*ast| {
            ast.deinit(allocator);
        }

        for (self.tokenize_reports.items) |*report| {
            report.deinit();
        }
        self.tokenize_reports.deinit();

        for (self.parse_reports.items) |*report| {
            report.deinit();
        }
        self.parse_reports.deinit();

        self.module_env.deinit();
        allocator.destroy(self.module_env);
    }
};

var last_result: ?PlaygroundResult = null;

/// Initialize the WASM module
export fn init() void {
    // Nothing to initialize for now
}

/// Set the source code to be processed
export fn setSource(source_ptr: [*]const u8, source_len: usize) void {
    const source = source_ptr[0..source_len];
    WasmFilesystem.setSource(allocator, source);
}

/// Process the current source code and return status
/// Returns: 0 = success, 1 = error
export fn processSource() u32 {
    // Clean up previous result
    if (last_result) |*result| {
        result.deinit();
        last_result = null;
    }

    // Get source from WASM filesystem
    const source = WasmFilesystem.global_source orelse {
        return 1; // No source provided
    };

    // Initialize the ModuleEnv
    var module_env = allocator.create(ModuleEnv) catch return 1;
    const owned_source = allocator.dupe(u8, source) catch return 1;
    module_env.* = ModuleEnv.init(allocator, owned_source);
    module_env.calcLineStarts(source) catch return 1;

    // Initialize result structure
    var result = PlaygroundResult{
        .module_env = module_env,
        .tokenize_reports = std.ArrayList(reporting.Report).init(allocator),
        .parse_reports = std.ArrayList(reporting.Report).init(allocator),
    };

    // Step 1: Parse the source code only
    var parse_ast = parse.parse(module_env, source);
    result.parse_ast = parse_ast;

    // Collect tokenize diagnostic reports
    for (parse_ast.tokenize_diagnostics.items) |diagnostic| {
        const report = parse_ast.tokenizeDiagnosticToReport(diagnostic, allocator) catch continue;
        result.tokenize_reports.append(report) catch continue;
        result.error_count += 1;
    }

    // Collect parser diagnostic reports
    for (parse_ast.parse_diagnostics.items) |diagnostic| {
        const report = parse_ast.parseDiagnosticToReport(module_env, diagnostic, allocator, "main.roc") catch continue;
        result.parse_reports.append(report) catch continue;
        result.error_count += 1;
    }

    last_result = result;
    return 0;
}

/// Get the number of errors from the last processing
export fn getErrorCount() u32 {
    if (last_result) |result| {
        return result.error_count;
    }
    return 0;
}

/// Get the number of warnings from the last processing
export fn getWarningCount() u32 {
    if (last_result) |result| {
        return result.warning_count;
    }
    return 0;
}

/// Get the total number of reports (errors + warnings + info)
export fn getReportCount() u32 {
    if (last_result) |result| {
        return @intCast(result.tokenize_reports.items.len + result.parse_reports.items.len);
    }
    return 0;
}

/// Get a report by index and write it to the provided buffer
/// Returns the number of bytes written, or 0 if index is out of range
export fn getReport(index: u32, buffer_ptr: [*]u8, buffer_len: usize) usize {
    if (last_result) |result| {
        // Calculate total reports across both lists
        const tokenize_count = result.tokenize_reports.items.len;
        const total_count = tokenize_count + result.parse_reports.items.len;

        if (index >= total_count) {
            return 0;
        }

        // Determine which list and which report
        const report = if (index < tokenize_count)
            &result.tokenize_reports.items[index]
        else
            &result.parse_reports.items[index - tokenize_count];

        // Format the report as a simple string
        var buffer_stream = std.io.fixedBufferStream(buffer_ptr[0..buffer_len]);
        var writer = buffer_stream.writer();

        // Write severity
        const severity_str = switch (report.severity) {
            .info => "INFO",
            .warning => "WARNING",
            .runtime_error => "ERROR",
            .fatal => "FATAL",
        };

        writer.print("{s}: {s}", .{ severity_str, report.title }) catch return 0;

        return buffer_stream.getWritten().len;
    }
    return 0;
}

/// Get a report as JSON by index and write it to the provided buffer
/// Returns the number of bytes written, or 0 if index is out of range
export fn getReportJSON(index: u32, buffer_ptr: [*]u8, buffer_len: usize) usize {
    if (last_result) |result| {
        // Calculate total reports across both lists
        const tokenize_count = result.tokenize_reports.items.len;
        const total_count = tokenize_count + result.parse_reports.items.len;

        if (index >= total_count) {
            return 0;
        }

        // Determine which list and which report
        const report = if (index < tokenize_count)
            &result.tokenize_reports.items[index]
        else
            &result.parse_reports.items[index - tokenize_count];

        var buffer_stream = std.io.fixedBufferStream(buffer_ptr[0..buffer_len]);
        var writer = buffer_stream.writer();

        // Write as JSON
        writer.writeAll("{") catch return 0;

        // Severity
        const severity_str = switch (report.severity) {
            .info => "info",
            .warning => "warning",
            .runtime_error => "error",
            .fatal => "fatal",
        };
        writer.print("\"severity\":\"{s}\",", .{severity_str}) catch return 0;

        // Title (escape quotes)
        writer.writeAll("\"title\":\"") catch return 0;
        for (report.title) |char| {
            if (char == '"') {
                writer.writeAll("\\\"") catch return 0;
            } else if (char == '\\') {
                writer.writeAll("\\\\") catch return 0;
            } else if (char == '\n') {
                writer.writeAll("\\n") catch return 0;
            } else if (char == '\r') {
                writer.writeAll("\\r") catch return 0;
            } else if (char == '\t') {
                writer.writeAll("\\t") catch return 0;
            } else {
                writer.writeByte(char) catch return 0;
            }
        }
        writer.writeAll("\"") catch return 0;

        writer.writeAll("}") catch return 0;

        return buffer_stream.getWritten().len;
    }
    return 0;
}

/// Clean up resources
export fn cleanup() void {
    if (last_result) |*result| {
        result.deinit();
        last_result = null;
    }

    // Clean up global source
    if (WasmFilesystem.global_source) |source| {
        if (WasmFilesystem.global_allocator) |alloc| {
            alloc.free(source);
        }
        WasmFilesystem.global_source = null;
        WasmFilesystem.global_allocator = null;
    }
}

/// Allocate memory that can be accessed from JavaScript
export fn allocate(size: usize) ?[*]u8 {
    const memory = allocator.alloc(u8, size) catch return null;
    return memory.ptr;
}

/// Free memory that was allocated with allocate()
export fn deallocate(ptr: [*]u8, size: usize) void {
    const memory = ptr[0..size];
    allocator.free(memory);
}
