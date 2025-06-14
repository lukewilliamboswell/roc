//! Report system for formatted error messages.
//!
//! This module provides the Report struct and related functionality for creating
//! structured error reports that can be rendered to different output formats.
//! Reports combine a title, severity level, and formatted document content.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Severity = @import("severity.zig").Severity;
const Document = @import("document.zig").Document;
const Annotation = @import("document.zig").Annotation;
const renderer = @import("renderer.zig");
const RenderTarget = renderer.RenderTarget;

/// A structured report containing error information and formatted content.
pub const Report = struct {
    title: []const u8,
    severity: Severity,
    document: Document,
    allocator: Allocator,

    pub fn init(allocator: Allocator, title: []const u8, severity: Severity) Report {
        return Report{
            .title = title,
            .severity = severity,
            .document = Document.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Report) void {
        self.document.deinit();
    }

    /// Render the report to the specified writer and target format.
    pub fn render(self: *const Report, writer: anytype, target: RenderTarget) !void {
        try renderer.renderReport(self, writer, target);
    }

    /// Add a section header to the report.
    pub fn addHeader(self: *Report, header: []const u8) !void {
        try self.document.addLineBreak();
        try self.document.addAnnotated(header, .emphasized);
        try self.document.addLineBreak();
    }

    /// Add a code snippet with proper formatting.
    pub fn addCodeSnippet(self: *Report, code: []const u8, line_number: ?u32) !void {
        if (line_number) |line_num| {
            try self.document.addFormattedText("{d} | ", .{line_num});
        } else {
            try self.document.addText("   | ");
        }
        try self.document.addCodeBlock(code);
        try self.document.addLineBreak();
    }

    /// Add source context with line numbers and highlighting.
    pub fn addSourceContext(
        self: *Report,
        lines: []const []const u8,
        start_line: u32,
        highlight_line: ?u32,
        highlight_column_start: ?u32,
        highlight_column_end: ?u32,
    ) !void {
        const line_number_width = blk: {
            const max_line = start_line + @as(u32, @intCast(lines.len));
            var width: u32 = 1;
            var num = max_line;
            while (num >= 10) {
                width += 1;
                num /= 10;
            }
            break :blk width;
        };

        for (lines, 0..) |line, i| {
            const current_line = start_line + @as(u32, @intCast(i));
            const is_highlight = if (highlight_line) |hl| current_line == hl else false;

            // Line number with proper padding
            const line_str = try std.fmt.allocPrint(self.document.allocator, "{d}", .{current_line});
            defer self.document.allocator.free(line_str);
            const padding = if (line_str.len < line_number_width) line_number_width - line_str.len else 0;

            // Add padding spaces
            var j: usize = 0;
            while (j < padding) : (j += 1) {
                try self.document.addText(" ");
            }
            try self.document.addFormattedText("{d} | ", .{current_line});

            // Line content
            if (is_highlight) {
                try self.document.startAnnotation(.error_highlight);
            }
            try self.document.addText(line);
            if (is_highlight) {
                try self.document.endAnnotation();
            }
            try self.document.addLineBreak();

            // Add underline for highlighted sections
            if (is_highlight and highlight_column_start != null and highlight_column_end != null) {
                // Add padding for line number
                var underline_padding: u32 = 0;
                while (underline_padding < line_number_width + 3) : (underline_padding += 1) {
                    try self.document.addSpace(1);
                }

                // Add spaces up to highlight start
                if (highlight_column_start.? > 0) {
                    try self.document.addSpace(highlight_column_start.?);
                }

                // Add underline
                try self.document.startAnnotation(.error_highlight);
                const underline_length = if (highlight_column_end.? > highlight_column_start.?)
                    highlight_column_end.? - highlight_column_start.?
                else
                    1;
                var k: u32 = 0;
                while (k < underline_length) : (k += 1) {
                    try self.document.addText("^");
                }
                try self.document.endAnnotation();
                try self.document.addLineBreak();
            }
        }
    }

    /// Add a suggestion with proper formatting.
    pub fn addSuggestion(self: *Report, suggestion: []const u8) !void {
        try self.document.addLineBreak();
        try self.document.addAnnotated("Hint: ", .suggestion);
        try self.document.addText(suggestion);
        try self.document.addLineBreak();
    }

    /// Add multiple suggestions as a list.
    pub fn addSuggestions(self: *Report, suggestions: []const []const u8) !void {
        if (suggestions.len == 0) return;

        try self.document.addLineBreak();
        if (suggestions.len == 1) {
            try self.document.addAnnotated("Hint: ", .suggestion);
            try self.document.addText(suggestions[0]);
        } else {
            try self.document.addAnnotated("Hints:", .suggestion);
            try self.document.addLineBreak();
            for (suggestions) |suggestion| {
                try self.document.addIndent(1);
                try self.document.addText("• ");
                try self.document.addText(suggestion);
                try self.document.addLineBreak();
            }
        }
        try self.document.addLineBreak();
    }

    /// Add a type comparison showing expected vs actual.
    pub fn addTypeComparison(self: *Report, expected: []const u8, actual: []const u8) !void {
        try self.document.addLineBreak();
        try self.document.addText("Expected type:");
        try self.document.addLineBreak();
        try self.document.addIndent(1);
        try self.document.addType(expected);
        try self.document.addLineBreak();
        try self.document.addLineBreak();
        try self.document.addText("But found type:");
        try self.document.addLineBreak();
        try self.document.addIndent(1);
        try self.document.addError(actual);
        try self.document.addLineBreak();
    }

    /// Add a note with dimmed styling.
    pub fn addNote(self: *Report, note: []const u8) !void {
        try self.document.addLineBreak();
        try self.document.addAnnotated("Note: ", .dimmed);
        try self.document.addText(note);
        try self.document.addLineBreak();
    }

    /// Add an error message with proper styling.
    pub fn addErrorMessage(self: *Report, message: []const u8) !void {
        try self.document.addError(message);
        try self.document.addLineBreak();
    }

    /// Add a warning message with proper styling.
    pub fn addWarningMessage(self: *Report, message: []const u8) !void {
        try self.document.addWarning(message);
        try self.document.addLineBreak();
    }

    /// Add a separator line.
    pub fn addSeparator(self: *Report) !void {
        try self.document.addLineBreak();
        try self.document.addHorizontalRule(40);
        try self.document.addLineBreak();
    }

    /// Check if the report is empty (has no content).
    pub fn isEmpty(self: *const Report) bool {
        return self.document.isEmpty();
    }

    /// Get the number of lines in the report (approximate).
    pub fn getLineCount(self: *const Report) usize {
        var count: usize = 2; // Title + blank line
        for (self.document.elements.items) |element| {
            switch (element) {
                .line_break => count += 1,
                else => {},
            }
        }
        return count;
    }
};

/// Builder for creating reports with a fluent interface.
pub const ReportBuilder = struct {
    report: Report,

    pub fn init(allocator: Allocator, title: []const u8, severity: Severity) ReportBuilder {
        return ReportBuilder{
            .report = Report.init(allocator, title, severity),
        };
    }

    pub fn deinit(self: *ReportBuilder) void {
        self.report.deinit();
    }

    pub fn header(self: *ReportBuilder, text: []const u8) *ReportBuilder {
        self.report.addHeader(text) catch @panic("OOM");
        return self;
    }

    pub fn message(self: *ReportBuilder, text: []const u8) *ReportBuilder {
        self.report.document.addText(text) catch @panic("OOM");
        self.report.document.addLineBreak() catch @panic("OOM");
        return self;
    }

    pub fn code(self: *ReportBuilder, code_text: []const u8) *ReportBuilder {
        self.report.addCodeSnippet(code_text, null) catch @panic("OOM");
        return self;
    }

    pub fn suggestion(self: *ReportBuilder, text: []const u8) *ReportBuilder {
        self.report.addSuggestion(text) catch @panic("OOM");
        return self;
    }

    pub fn note(self: *ReportBuilder, text: []const u8) *ReportBuilder {
        self.report.addNote(text) catch @panic("OOM");
        return self;
    }

    pub fn typeComparison(self: *ReportBuilder, expected: []const u8, actual: []const u8) *ReportBuilder {
        self.report.addTypeComparison(expected, actual) catch @panic("OOM");
        return self;
    }

    pub fn build(self: *ReportBuilder) Report {
        return self.report;
    }
};

// Predefined report templates for common error types
pub const Templates = struct {
    /// Create a type mismatch report.
    pub fn typeMismatch(
        allocator: Allocator,
        expected: []const u8,
        actual: []const u8,
        location: []const u8,
    ) !Report {
        var report = Report.init(allocator, "TYPE MISMATCH", .runtime_error);

        try report.document.addText("I expected this expression to have type:");
        try report.document.addLineBreak();
        try report.document.addIndent(1);
        try report.document.addType(expected);
        try report.document.addLineBreak();
        try report.document.addLineBreak();
        try report.document.addText("But it actually has type:");
        try report.document.addLineBreak();
        try report.document.addIndent(1);
        try report.document.addError(actual);
        try report.document.addLineBreak();

        if (location.len > 0) {
            try report.document.addLineBreak();
            try report.document.addText("At: ");
            try report.document.addAnnotated(location, .path);
        }

        return report;
    }

    /// Create an unrecognized name report.
    pub fn unrecognizedName(
        allocator: Allocator,
        name: []const u8,
        suggestions: []const []const u8,
    ) !Report {
        var report = Report.init(allocator, "NAMING ERROR", .runtime_error);

        try report.document.addText("I cannot find a ");
        try report.document.addError(name);
        try report.document.addText(" variable.");
        try report.document.addLineBreak();

        if (suggestions.len > 0) {
            try report.addSuggestions(suggestions);
        }

        return report;
    }

    /// Create a circular definition report.
    pub fn circularDefinition(
        allocator: Allocator,
        names: []const []const u8,
    ) !Report {
        var report = Report.init(allocator, "CIRCULAR DEFINITION", .runtime_error);

        try report.document.addText("These definitions depend on each other in a cycle:");
        try report.document.addLineBreak();
        try report.document.addLineBreak();

        for (names, 0..) |name, i| {
            try report.document.addIndent(1);
            try report.document.addError(name);
            if (i < names.len - 1) {
                try report.document.addText(" → ");
            } else {
                try report.document.addText(" → ");
                try report.document.addError(names[0]);
            }
            try report.document.addLineBreak();
        }

        try report.addNote("Roc cannot compile definitions that depend on themselves.");

        return report;
    }

    /// Create a compiler internal error report.
    pub fn internalError(
        allocator: Allocator,
        message: []const u8,
        location: []const u8,
    ) !Report {
        var report = Report.init(allocator, "INTERNAL COMPILER ERROR", .fatal);

        try report.document.addText("The compiler encountered an unexpected error:");
        try report.document.addLineBreak();
        try report.document.addLineBreak();
        try report.document.addError(message);
        try report.document.addLineBreak();

        if (location.len > 0) {
            try report.document.addLineBreak();
            try report.document.addText("Location: ");
            try report.document.addAnnotated(location, .path);
            try report.document.addLineBreak();
        }

        try report.document.addLineBreak();
        try report.document.addText("This is a bug in the Roc compiler. Please report it at:");
        try report.document.addLineBreak();
        try report.document.addAnnotated("https://github.com/roc-lang/roc/issues", .path);
        try report.document.addLineBreak();

        return report;
    }
};

// Tests
const testing = std.testing;

test "Report basic functionality" {
    var report = Report.init(testing.allocator, "TEST ERROR", .runtime_error);
    defer report.deinit();

    try report.document.addText("This is a test error message.");
    try report.addSuggestion("Try fixing the issue.");

    try testing.expect(!report.isEmpty());
    try testing.expect(report.getLineCount() > 2);
}

test "ReportBuilder fluent interface" {
    var builder = ReportBuilder.init(testing.allocator, "BUILD ERROR", .runtime_error);
    defer builder.deinit();

    var report = builder
        .message("Something went wrong")
        .suggestion("Try this fix")
        .note("This is just a note")
        .build();

    try testing.expect(!report.isEmpty());
}

test "Type mismatch template" {
    var report = try Templates.typeMismatch(
        testing.allocator,
        "String",
        "Number",
        "main.roc:10:5",
    );
    defer report.deinit();

    try testing.expectEqualStrings("TYPE MISMATCH", report.title);
    try testing.expectEqual(Severity.runtime_error, report.severity);
}

test "Unrecognized name template" {
    const suggestions = [_][]const u8{ "length", "len", "size" };
    var report = try Templates.unrecognizedName(
        testing.allocator,
        "lenght",
        &suggestions,
    );
    defer report.deinit();

    try testing.expectEqualStrings("NAMING ERROR", report.title);
}

test "Source context rendering" {
    var report = Report.init(testing.allocator, "TEST", .runtime_error);
    defer report.deinit();

    const lines = [_][]const u8{
        "fn main() {",
        "    let x = undefinedVariable",
        "    x + 1",
        "}",
    };

    try report.addSourceContext(&lines, 1, 2, 12, 27);
    try testing.expect(!report.isEmpty());
}
