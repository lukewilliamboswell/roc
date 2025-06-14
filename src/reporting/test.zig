//! Comprehensive unit tests for the Roc reporting system.
//!
//! This file contains tests for all components of the reporting system including
//! severity levels, document creation, styling, rendering, and problem processing.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import all reporting components
const reporting = @import("../reporting.zig");
const Severity = @import("severity.zig").Severity;
const Document = @import("document.zig").Document;
const Annotation = @import("document.zig").Annotation;
const DocumentBuilder = @import("document.zig").DocumentBuilder;
const ColorPalette = @import("style.zig").ColorPalette;
const ColorUtils = @import("style.zig").ColorUtils;
const AnsiCodes = @import("style.zig").AnsiCodes;
const RenderTarget = @import("renderer.zig").RenderTarget;
const TerminalRenderer = @import("renderer.zig").TerminalRenderer;
const PlainTextRenderer = @import("renderer.zig").PlainTextRenderer;
const HtmlRenderer = @import("renderer.zig").HtmlRenderer;
const Report = @import("report.zig").Report;
const Templates = @import("report.zig").Templates;
const ProblemProcessor = @import("processor.zig").ProblemProcessor;

// Mock problem types for testing
const MockProblem = union(enum) {
    parse_error: struct {
        message: []const u8,
        line: u32,
        column: u32,
    },
    type_mismatch: struct {
        expected: []const u8,
        actual: []const u8,
        location: []const u8,
    },
    name_error: struct {
        name: []const u8,
        suggestions: [][]const u8,
    },
};

// ===== Severity Tests =====

test "Severity blocking behavior" {
    try testing.expect(!Severity.warning.isBlocking());
    try testing.expect(!Severity.runtime_error.isBlocking());
    try testing.expect(Severity.fatal.isBlocking());
}

test "Severity compiler bug detection" {
    try testing.expect(!Severity.warning.isCompilerBug());
    try testing.expect(!Severity.runtime_error.isCompilerBug());
    try testing.expect(Severity.fatal.isCompilerBug());
}

test "Severity priority ordering" {
    try testing.expect(Severity.fatal.priority() < Severity.runtime_error.priority());
    try testing.expect(Severity.runtime_error.priority() < Severity.warning.priority());
}

test "Severity string representations" {
    try testing.expectEqualStrings("WARNING", Severity.warning.toString());
    try testing.expectEqualStrings("ERROR", Severity.runtime_error.toString());
    try testing.expectEqualStrings("FATAL", Severity.fatal.toString());

    try testing.expectEqualStrings("W", Severity.warning.toCode());
    try testing.expectEqualStrings("E", Severity.runtime_error.toCode());
    try testing.expectEqualStrings("F", Severity.fatal.toCode());
}

// ===== Document Tests =====

test "Document basic operations" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addText("Hello");
    try doc.addSpace(1);
    try doc.addAnnotated("world", .emphasized);
    try doc.addLineBreak();

    try testing.expectEqual(@as(usize, 4), doc.elementCount());
    try testing.expect(!doc.isEmpty());

    const first = doc.getElement(0).?;
    try testing.expectEqualStrings("Hello", first.getText().?);
}

test "Document builder fluent interface" {
    var builder = DocumentBuilder.init(testing.allocator);
    defer builder.deinit();

    var doc = builder
        .text("Error: ")
        .errorText("Type mismatch")
        .lineBreak()
        .indent(1)
        .text("Expected: ")
        .typeText("String")
        .build();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "Document annotation regions" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.startAnnotation(.error_highlight);
    try doc.addText("Error message");
    try doc.endAnnotation();

    try testing.expectEqual(@as(usize, 3), doc.elementCount());
}

test "Document code blocks" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addCodeBlock("fn main() {\n    println!(\"Hello\");\n}");
    try testing.expect(doc.elementCount() > 0);
}

test "Document convenience methods" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addKeyword("fn");
    try doc.addSpace(1);
    try doc.addInlineCode("main()");
    try doc.addLineBreak();
    try doc.addError("Something went wrong");

    try testing.expect(doc.elementCount() >= 5);
}

// ===== Annotation Tests =====

test "Annotation semantic names" {
    try testing.expectEqualStrings("error", Annotation.error_highlight.semanticName());
    try testing.expectEqualStrings("keyword", Annotation.keyword.semanticName());
    try testing.expectEqualStrings("type", Annotation.type_variable.semanticName());
    try testing.expectEqualStrings("warning", Annotation.warning_highlight.semanticName());
}

test "Annotation color usage" {
    try testing.expect(Annotation.error_highlight.usesColor());
    try testing.expect(Annotation.keyword.usesColor());
    try testing.expect(!Annotation.emphasized.usesColor());
    try testing.expect(!Annotation.dimmed.usesColor());
}

// ===== Style Tests =====

test "ColorPalette annotation mapping" {
    const palette = ColorPalette.ANSI;

    try testing.expectEqualStrings(AnsiCodes.RED, palette.colorForAnnotation(.error_highlight));
    try testing.expectEqualStrings(AnsiCodes.YELLOW, palette.colorForAnnotation(.warning_highlight));
    try testing.expectEqualStrings(AnsiCodes.MAGENTA, palette.colorForAnnotation(.keyword));
    try testing.expectEqualStrings(AnsiCodes.BLUE, palette.colorForAnnotation(.type_variable));
}

test "ColorPalette no color variant" {
    const palette = ColorPalette.NO_COLOR;

    try testing.expectEqualStrings("", palette.colorForAnnotation(.error_highlight));
    try testing.expectEqualStrings("", palette.colorForAnnotation(.keyword));
    try testing.expectEqualStrings("", palette.reset);
}

test "ColorUtils display width calculation" {
    // Plain text
    try testing.expectEqual(@as(usize, 5), ColorUtils.displayWidth("hello"));

    // Text with ANSI codes
    const colored = AnsiCodes.RED ++ "hello" ++ AnsiCodes.RESET;
    try testing.expectEqual(@as(usize, 5), ColorUtils.displayWidth(colored));

    // Empty string
    try testing.expectEqual(@as(usize, 0), ColorUtils.displayWidth(""));
}

test "ColorUtils ANSI code stripping" {
    const input = AnsiCodes.RED ++ "hello" ++ AnsiCodes.RESET ++ " world";
    const stripped = try ColorUtils.stripAnsiCodes(testing.allocator, input);
    defer testing.allocator.free(stripped);

    try testing.expectEqualStrings("hello world", stripped);
}

// ===== Renderer Tests =====

test "TerminalRenderer basic functionality" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var terminal_renderer = TerminalRenderer.init(testing.allocator, buffer.writer().any(), ColorPalette.NO_COLOR);
    defer terminal_renderer.deinit();

    var renderer = terminal_renderer.renderer();

    try renderer.writeText("Hello");
    try renderer.writeSpace(1);
    try renderer.writeText("world");
    try renderer.writeLineBreak();

    try testing.expectEqualStrings("Hello world\n", buffer.items);
}

test "TerminalRenderer with colors" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var terminal_renderer = TerminalRenderer.init(testing.allocator, buffer.writer().any(), ColorPalette.ANSI);
    defer terminal_renderer.deinit();

    var renderer = terminal_renderer.renderer();

    try renderer.pushAnnotation(.error_highlight);
    try renderer.writeText("Error");
    try renderer.popAnnotation();

    // Should contain ANSI codes
    try testing.expect(buffer.items.len > 5); // "Error" + ANSI codes
    try testing.expect(std.mem.indexOf(u8, buffer.items, AnsiCodes.RED) != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, AnsiCodes.RESET) != null);
}

test "PlainTextRenderer ignores annotations" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();

    var renderer = plain_renderer.renderer();

    try renderer.pushAnnotation(.error_highlight);
    try renderer.writeText("Error");
    try renderer.popAnnotation();
    try renderer.writeText(": something went wrong");

    try testing.expectEqualStrings("Error: something went wrong", buffer.items);
}

test "HtmlRenderer with escaping" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var html_renderer = HtmlRenderer.init(testing.allocator, buffer.writer().any());
    defer html_renderer.deinit();

    var renderer = html_renderer.renderer();

    try renderer.writeText("<script>alert('test')</script>");

    try testing.expect(std.mem.indexOf(u8, buffer.items, "&lt;script&gt;") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "&lt;/script&gt;") != null);
}

test "HtmlRenderer annotations create spans" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var html_renderer = HtmlRenderer.init(testing.allocator, buffer.writer().any());
    defer html_renderer.deinit();

    var renderer = html_renderer.renderer();

    try renderer.pushAnnotation(.error_highlight);
    try renderer.writeText("Error");
    try renderer.popAnnotation();

    try testing.expect(std.mem.indexOf(u8, buffer.items, "<span class=\"roc-error\">") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "</span>") != null);
}

test "Renderer indentation" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();

    var renderer = plain_renderer.renderer();

    try renderer.writeIndent(2);
    try renderer.writeText("indented");

    try testing.expectEqualStrings("        indented", buffer.items);
}

test "Renderer horizontal rule" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();

    var renderer = plain_renderer.renderer();

    try renderer.writeHorizontalRule(5);
    try testing.expectEqualStrings("-----", buffer.items);
}

// ===== Report Tests =====

test "Report basic functionality" {
    var report = Report.init(testing.allocator, "TEST ERROR", .runtime_error);
    defer report.deinit();

    try report.document.addText("This is a test error message.");
    try report.addSuggestion("Try fixing the issue.");

    try testing.expect(!report.isEmpty());
    try testing.expect(report.getLineCount() > 2);
}

test "Report rendering" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();
    var renderer = plain_renderer.renderer();

    var report = Report.init(testing.allocator, "TEST ERROR", .runtime_error);
    defer report.deinit();

    try report.document.addText("Error message");

    try report.render(&renderer);

    try testing.expect(std.mem.indexOf(u8, buffer.items, "TEST ERROR") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Error message") != null);
}

test "Report source context" {
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

test "Report type comparison" {
    var report = Report.init(testing.allocator, "TYPE ERROR", .runtime_error);
    defer report.deinit();

    try report.addTypeComparison("String", "Number");
    try testing.expect(!report.isEmpty());
}

test "Report suggestions" {
    var report = Report.init(testing.allocator, "NAMING ERROR", .runtime_error);
    defer report.deinit();

    const suggestions = [_][]const u8{ "length", "len", "size" };
    try report.addSuggestions(&suggestions);
    try testing.expect(!report.isEmpty());
}

// ===== Template Tests =====

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
    try testing.expect(!report.isEmpty());
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
    try testing.expect(!report.isEmpty());
}

test "Circular definition template" {
    const names = [_][]const u8{ "a", "b", "c" };
    var report = try Templates.circularDefinition(testing.allocator, &names);
    defer report.deinit();

    try testing.expectEqualStrings("CIRCULAR DEFINITION", report.title);
    try testing.expect(!report.isEmpty());
}

test "Internal error template" {
    var report = try Templates.internalError(
        testing.allocator,
        "Something went wrong internally",
        "type_check",
    );
    defer report.deinit();

    try testing.expectEqualStrings("INTERNAL COMPILER ERROR", report.title);
    try testing.expectEqual(Severity.fatal, report.severity);
    try testing.expect(!report.isEmpty());
}

// ===== Problem Processor Tests =====

test "ProblemProcessor creation" {
    var processor = ProblemProcessor.init(testing.allocator);
    defer processor.deinit();
    // Just test creation and destruction
}

// ===== Integration Tests =====

test "Full reporting system integration" {
    var reporting_system = reporting.ReportingSystem.init(testing.allocator);
    defer reporting_system.deinit();

    // Add a source file
    try reporting_system.addSourceFile("test.roc", "fn main() {\n    42\n}\n");

    // Test that we can create and destroy without issues
    try testing.expect(!reporting_system.hasErrors());
    try testing.expect(!reporting_system.hasFatalErrors());
    try testing.expectEqual(@as(u8, 0), reporting_system.getExitCode());
}

test "Reporting system with source files" {
    var reporting_system = reporting.ReportingSystem.init(testing.allocator);
    defer reporting_system.deinit();

    try reporting_system.addSourceFile("test.roc", "app [main] {}\n\nmain = 42\n");

    // Verify source file was added
    try testing.expect(reporting_system.source_files.contains("test.roc"));
}

test "Document rendering with different targets" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addText("Hello ");
    try doc.addAnnotated("world", .emphasized);
    try doc.addLineBreak();

    // Test plain text rendering
    {
        var buffer = std.ArrayList(u8).init(testing.allocator);
        defer buffer.deinit();

        var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
        defer plain_renderer.deinit();
        var renderer = plain_renderer.renderer();

        try doc.render(&renderer);
        try testing.expect(std.mem.indexOf(u8, buffer.items, "Hello world") != null);
    }

    // Test terminal rendering
    {
        var buffer = std.ArrayList(u8).init(testing.allocator);
        defer buffer.deinit();

        var terminal_renderer = TerminalRenderer.init(testing.allocator, buffer.writer().any(), ColorPalette.NO_COLOR);
        defer terminal_renderer.deinit();
        var renderer = terminal_renderer.renderer();

        try doc.render(&renderer);
        try testing.expect(std.mem.indexOf(u8, buffer.items, "Hello world") != null);
    }

    // Test HTML rendering
    {
        var buffer = std.ArrayList(u8).init(testing.allocator);
        defer buffer.deinit();

        var html_renderer = HtmlRenderer.init(testing.allocator, buffer.writer().any());
        defer html_renderer.deinit();
        var renderer = html_renderer.renderer();

        try doc.render(&renderer);
        try testing.expect(std.mem.indexOf(u8, buffer.items, "Hello world") != null);
    }
}

// ===== Performance Tests =====

test "Large document performance" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    // Create a large document
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try doc.addText("Line ");
        try doc.addFormattedText("{d}", .{i});
        try doc.addLineBreak();
    }

    try testing.expect(doc.elementCount() >= 2000);

    // Test rendering performance
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();
    var renderer = plain_renderer.renderer();

    try doc.render(&renderer);
    try testing.expect(buffer.items.len > 10000);
}

test "Multiple reports rendering" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();
    var renderer = plain_renderer.renderer();

    // Create multiple reports
    var reports = std.ArrayList(Report).init(testing.allocator);
    defer {
        for (reports.items) |*report| {
            report.deinit();
        }
        reports.deinit();
    }

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var report = Report.init(testing.allocator, "TEST ERROR", .runtime_error);
        try report.document.addFormattedText("Error number {d}", .{i});
        try reports.append(report);
    }

    // Render all reports
    for (reports.items) |*report| {
        try report.render(&renderer);
        try renderer.writeLineBreak();
    }

    try testing.expect(buffer.items.len > 100);
}

// ===== Error Handling Tests =====

test "Empty document handling" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.isEmpty());
    try testing.expectEqual(@as(usize, 0), doc.elementCount());

    // Rendering empty document should not crash
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();
    var renderer = plain_renderer.renderer();

    try doc.render(&renderer);
    try testing.expectEqualStrings("", buffer.items);
}

test "Report with empty content" {
    var report = Report.init(testing.allocator, "EMPTY ERROR", .runtime_error);
    defer report.deinit();

    try testing.expect(report.isEmpty());

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    var plain_renderer = PlainTextRenderer.init(testing.allocator, buffer.writer().any());
    defer plain_renderer.deinit();
    var renderer = plain_renderer.renderer();

    try report.render(&renderer);
    // Should at least contain the title
    try testing.expect(std.mem.indexOf(u8, buffer.items, "EMPTY ERROR") != null);
}
