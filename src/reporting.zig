//! Main reporting module for the Roc compiler.
//!
//! This module provides a comprehensive error and warning reporting system that can
//! format diagnostics for multiple output targets including terminals, HTML, and
//! language servers.
//!
//! # Usage
//!
//! ```zig
//! var reporting = try ReportingSystem.init(allocator);
//! defer reporting.deinit();
//!
//! // Add problems from compilation
//! try reporting.addProblem(problem);
//!
//! // Render to terminal with colors
//! try reporting.renderToWriter(stdout.writer(), .color_terminal);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const base = @import("base.zig");
const Problem = @import("problem.zig").Problem;

// Re-export core types
pub const Severity = @import("reporting/severity.zig").Severity;
pub const Document = @import("reporting/document.zig").Document;
pub const Annotation = @import("reporting/document.zig").Annotation;
pub const RenderTarget = @import("reporting/renderer.zig").RenderTarget;
pub const ColorPalette = @import("reporting/style.zig").ColorPalette;
pub const Report = @import("reporting/report.zig").Report;
pub const ProblemProcessor = @import("reporting/processor.zig").ProblemProcessor;

// Re-export renderers
pub const TerminalRenderer = @import("reporting/renderer.zig").TerminalRenderer;
pub const PlainTextRenderer = @import("reporting/renderer.zig").PlainTextRenderer;
pub const HtmlRenderer = @import("reporting/renderer.zig").HtmlRenderer;

/// Main reporting system that coordinates problem collection and rendering.
pub const ReportingSystem = struct {
    allocator: Allocator,
    processor: ProblemProcessor,
    problems: std.ArrayList(Problem),
    source_files: std.StringHashMap(SourceFile),

    const SourceFile = struct {
        path: []const u8,
        content: []const u8,
        lines: [][]const u8,

        pub fn deinit(self: *SourceFile, allocator: Allocator) void {
            allocator.free(self.lines);
        }
    };

    pub fn init(allocator: Allocator) ReportingSystem {
        return ReportingSystem{
            .allocator = allocator,
            .processor = ProblemProcessor.init(allocator),
            .problems = std.ArrayList(Problem).init(allocator),
            .source_files = std.StringHashMap(SourceFile).init(allocator),
        };
    }

    pub fn deinit(self: *ReportingSystem) void {
        self.processor.deinit();
        self.problems.deinit();

        var iterator = self.source_files.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.source_files.deinit();
    }

    /// Add a problem to be reported.
    pub fn addProblem(self: *ReportingSystem, problem: Problem) !void {
        try self.problems.append(problem);
    }

    /// Add a source file for context in error reporting.
    pub fn addSourceFile(self: *ReportingSystem, path: []const u8, content: []const u8) !void {
        // Split content into lines
        var lines = std.ArrayList([]const u8).init(self.allocator);
        defer lines.deinit();

        var line_start: usize = 0;
        for (content, 0..) |char, i| {
            if (char == '\n') {
                try lines.append(content[line_start..i]);
                line_start = i + 1;
            }
        }

        // Add final line if it doesn't end with newline
        if (line_start < content.len) {
            try lines.append(content[line_start..]);
        }

        const source_file = SourceFile{
            .path = try self.allocator.dupe(u8, path),
            .content = try self.allocator.dupe(u8, content),
            .lines = try lines.toOwnedSlice(),
        };

        try self.source_files.put(source_file.path, source_file);
    }

    /// Generate reports from collected problems.
    pub fn generateReports(self: *ReportingSystem) !std.ArrayList(Report) {
        var reports = std.ArrayList(Report).init(self.allocator);

        // Sort problems by severity (fatal first, then errors, then warnings)
        const SortContext = struct {
            pub fn lessThan(_: @This(), a: Problem, b: Problem) bool {
                const a_severity = getSeverity(a);
                const b_severity = getSeverity(b);

                // Fatal < Error < Warning (reverse order for sorting)
                return @intFromEnum(a_severity) < @intFromEnum(b_severity);
            }
        };

        std.mem.sort(Problem, self.problems.items, SortContext{}, SortContext.lessThan);

        // Process each problem into a report
        for (self.problems.items) |problem| {
            const report = try self.processor.problemToReport(problem, &self.source_files);
            try reports.append(report);
        }

        return reports;
    }

    /// Render all reports to a writer with the specified target format.
    pub fn renderToWriter(self: *ReportingSystem, writer: std.io.AnyWriter, target: RenderTarget) !void {
        const reports = try self.generateReports();
        defer {
            for (reports.items) |*report| {
                report.deinit();
            }
            reports.deinit();
        }

        // Count problems by severity
        var error_count: u32 = 0;
        var warning_count: u32 = 0;
        var fatal_count: u32 = 0;

        for (self.problems.items) |problem| {
            switch (getSeverity(problem)) {
                .fatal => fatal_count += 1,
                .runtime_error => error_count += 1,
                .warning => warning_count += 1,
            }
        }

        // Only show warnings if there are no errors or fatal problems
        const show_warnings = error_count == 0 and fatal_count == 0;

        // Create appropriate renderer
        switch (target) {
            .color_terminal => {
                var terminal_renderer = TerminalRenderer.init(self.allocator, writer, ColorPalette.ANSI);
                defer terminal_renderer.deinit();
                var renderer = terminal_renderer.renderer();

                try self.renderReports(reports.items, &renderer, show_warnings);
                try self.printSummary(&renderer, error_count, warning_count, fatal_count);
            },
            .plain_text => {
                var plain_renderer = PlainTextRenderer.init(self.allocator, writer);
                defer plain_renderer.deinit();
                var renderer = plain_renderer.renderer();

                try self.renderReports(reports.items, &renderer, show_warnings);
                try self.printSummary(&renderer, error_count, warning_count, fatal_count);
            },
            .html => {
                var html_renderer = HtmlRenderer.init(self.allocator, writer);
                defer html_renderer.deinit();
                var renderer = html_renderer.renderer();

                try self.renderReports(reports.items, &renderer, show_warnings);
                try self.printSummary(&renderer, error_count, warning_count, fatal_count);
            },
            .language_server => {
                // LSP format would be implemented here
                // For now, fall back to plain text
                var plain_renderer = PlainTextRenderer.init(self.allocator, writer);
                defer plain_renderer.deinit();
                var renderer = plain_renderer.renderer();

                try self.renderReports(reports.items, &renderer, show_warnings);
            },
        }
    }

    /// Check if there are any fatal errors that should stop compilation.
    pub fn hasFatalErrors(self: *const ReportingSystem) bool {
        for (self.problems.items) |problem| {
            if (getSeverity(problem) == .fatal) {
                return true;
            }
        }
        return false;
    }

    /// Check if there are any errors (fatal or runtime).
    pub fn hasErrors(self: *const ReportingSystem) bool {
        for (self.problems.items) |problem| {
            const severity = getSeverity(problem);
            if (severity == .fatal or severity == .runtime_error) {
                return true;
            }
        }
        return false;
    }

    /// Get the appropriate exit code based on problems.
    pub fn getExitCode(self: *const ReportingSystem) u8 {
        if (self.hasFatalErrors()) return 2;
        if (self.hasErrors()) return 1;

        // Return non-zero for warnings to block CI commits
        for (self.problems.items) |problem| {
            if (getSeverity(problem) == .warning) {
                return 1;
            }
        }

        return 0;
    }

    fn renderReports(
        self: *ReportingSystem,
        reports: []const Report,
        renderer: anytype,
        show_warnings: bool,
    ) !void {
        for (reports) |*report| {
            // Skip warnings if we have errors
            if (report.severity == .warning and !show_warnings) {
                continue;
            }

            try report.render(renderer);
            try renderer.writeLineBreak();

            // Add separator between reports
            try renderer.writeText("────────────────────────────────────────────────");
            try renderer.writeLineBreak();
            try renderer.writeLineBreak();
        }
    }

    fn printSummary(
        self: *ReportingSystem,
        renderer: anytype,
        error_count: u32,
        warning_count: u32,
        fatal_count: u32,
    ) !void {
        _ = self;

        if (fatal_count > 0) {
            try renderer.pushAnnotation(.error_highlight);
            try renderer.writeText("FATAL: ");
            try renderer.popAnnotation();
            try renderer.writeText("Compilation failed with ");
            if (fatal_count == 1) {
                try renderer.writeText("1 fatal error");
            } else {
                var buf: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&buf, "{d} fatal errors", .{fatal_count});
                try renderer.writeText(text);
            }
            try renderer.writeLineBreak();
        } else if (error_count > 0) {
            try renderer.pushAnnotation(.error_highlight);
            try renderer.writeText("ERROR: ");
            try renderer.popAnnotation();
            try renderer.writeText("Found ");
            if (error_count == 1) {
                try renderer.writeText("1 error");
            } else {
                var buf: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&buf, "{d} errors", .{error_count});
                try renderer.writeText(text);
            }
            try renderer.writeLineBreak();
        } else if (warning_count > 0) {
            try renderer.pushAnnotation(.warning_highlight);
            try renderer.writeText("WARNING: ");
            try renderer.popAnnotation();
            try renderer.writeText("Found ");
            if (warning_count == 1) {
                try renderer.writeText("1 warning");
            } else {
                var buf: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&buf, "{d} warnings", .{warning_count});
                try renderer.writeText(text);
            }
            try renderer.writeLineBreak();
        }
    }
};

/// Get the severity level for a problem.
fn getSeverity(problem: Problem) Severity {
    return switch (problem) {
        .tokenize => .runtime_error,
        .parser => .runtime_error,
        .canonicalize => .runtime_error,
        .compiler => |compiler_error| switch (compiler_error) {
            .canonicalize => .fatal,
            else => .fatal,
        },
    };
}

// Tests
const testing = std.testing;

test "ReportingSystem basic functionality" {
    var reporting = ReportingSystem.init(testing.allocator);
    defer reporting.deinit();

    // Test that we can create and destroy without issues
    try testing.expect(!reporting.hasErrors());
    try testing.expect(!reporting.hasFatalErrors());
    try testing.expectEqual(@as(u8, 0), reporting.getExitCode());
}

test "ReportingSystem with source files" {
    var reporting = ReportingSystem.init(testing.allocator);
    defer reporting.deinit();

    try reporting.addSourceFile("test.roc", "app [main] {}\n\nmain = 42\n");

    // Verify source file was added
    try testing.expect(reporting.source_files.contains("test.roc"));
}
