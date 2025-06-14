//! Problem processor for converting Problems to Reports.
//!
//! This module is responsible for converting raw compilation problems into
//! structured, formatted reports that can be rendered to different output
//! targets. It handles the logic of extracting information from different
//! problem types and creating appropriate error messages with context.

const std = @import("std");
const Allocator = std.mem.Allocator;
const base = @import("../base.zig");
const Problem = @import("../problem.zig").Problem;
const Report = @import("report.zig").Report;
const Templates = @import("report.zig").Templates;
const Severity = @import("severity.zig").Severity;

const Region = base.Region;
const Ident = base.Ident;

/// Maps module IDs to source file information.
const SourceFile = struct {
    path: []const u8,
    content: []const u8,
    lines: [][]const u8,

    pub fn deinit(self: *SourceFile, allocator: Allocator) void {
        allocator.free(self.lines);
    }
};

/// Processes problems and converts them into formatted reports.
pub const ProblemProcessor = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ProblemProcessor {
        return ProblemProcessor{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProblemProcessor) void {
        _ = self;
    }

    /// Convert a Problem into a Report.
    pub fn problemToReport(
        self: *ProblemProcessor,
        problem: Problem,
        source_files: anytype, // *std.StringHashMap(SourceFile)
    ) !Report {
        return switch (problem) {
            .tokenize => |diagnostic| self.tokenizeToReport(diagnostic, source_files),
            .parser => |diagnostic| self.parserToReport(diagnostic),
            .canonicalize => |diagnostic| self.canonicalizeToReport(diagnostic),
            .compiler => |compiler_error| self.compilerErrorToReport(compiler_error),
        };
    }

    /// Convert tokenize diagnostics to reports.
    fn tokenizeToReport(
        self: *ProblemProcessor,
        diagnostic: anytype,
        source_files: anytype,
    ) !Report {
        _ = diagnostic;
        _ = source_files;

        var report = Report.init(self.allocator, "TOKENIZE ERROR", .runtime_error);

        try report.document.addText("I encountered a problem while tokenizing your code.");
        try report.document.addLineBreak();

        // TODO: Add specific tokenize error handling when tokenize diagnostics are implemented
        try report.addNote("The tokenizer found an unexpected character or sequence.");

        return report;
    }

    /// Convert parser diagnostics to reports.
    fn parserToReport(
        self: *ProblemProcessor,
        diagnostic: anytype,
    ) !Report {
        const tag = diagnostic.tag;

        var report = switch (tag) {
            .bad_indent => Report.init(self.allocator, "INDENT ERROR", .runtime_error),
            .multiple_platforms => Report.init(self.allocator, "MULTIPLE PLATFORMS", .runtime_error),
            .no_platform => Report.init(self.allocator, "MISSING PLATFORM", .runtime_error),
            .missing_header => Report.init(self.allocator, "MISSING HEADER", .runtime_error),
            .list_not_closed => Report.init(self.allocator, "UNCLOSED LIST", .runtime_error),
            .missing_arrow => Report.init(self.allocator, "MISSING ARROW", .runtime_error),
            .expected_exposes => Report.init(self.allocator, "EXPECTED EXPOSES", .runtime_error),
            .expected_exposes_close_square => Report.init(self.allocator, "EXPECTED ]", .runtime_error),
            .expected_exposes_open_square => Report.init(self.allocator, "EXPECTED [", .runtime_error),
            .expected_imports => Report.init(self.allocator, "EXPECTED IMPORTS", .runtime_error),
            .expected_imports_close_curly => Report.init(self.allocator, "EXPECTED }", .runtime_error),
            .expected_imports_open_curly => Report.init(self.allocator, "EXPECTED {", .runtime_error),
            .expect_closing_paren => Report.init(self.allocator, "EXPECTED )", .runtime_error),
            else => Report.init(self.allocator, "PARSE ERROR", .runtime_error),
        };

        // Add specific error messages based on the tag
        switch (tag) {
            .bad_indent => {
                try report.document.addText("I found an indentation problem.");
                try report.document.addLineBreak();
                try report.addSuggestion("Make sure your indentation is consistent and uses spaces or tabs consistently.");
            },
            .multiple_platforms => {
                try report.document.addText("I found multiple platform declarations in your code.");
                try report.document.addLineBreak();
                try report.addSuggestion("A Roc application can only have one platform. Remove the extra platform declarations.");
            },
            .no_platform => {
                try report.document.addText("I couldn't find a platform declaration.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add a platform declaration like: app [main] { pf: platform \"path/to/platform.roc\" }");
            },
            .missing_header => {
                try report.document.addText("I expected to find a header at the top of this file.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add a header like 'app [main] { ... }' or 'interface [MyInterface] ...'");
            },
            .list_not_closed => {
                try report.document.addText("This list is missing a closing bracket.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add a ] to close the list.");
            },
            .missing_arrow => {
                try report.document.addText("I expected to find an arrow (->) here.");
                try report.document.addLineBreak();
                try report.addSuggestion("Function types need arrows between the input and output types.");
            },
            .expected_exposes => {
                try report.document.addText("I expected to find an 'exposes' clause.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add 'exposes [...]' to specify what this module exposes.");
            },
            .expected_exposes_close_square => {
                try report.document.addText("I expected to find a ] to close the exposes list.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add ] after your exposed values.");
            },
            .expected_exposes_open_square => {
                try report.document.addText("I expected to find a [ to start the exposes list.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add [ before your exposed values.");
            },
            .expected_imports => {
                try report.document.addText("I expected to find an 'imports' clause.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add 'imports [...]' to specify what this module imports.");
            },
            .expected_imports_close_curly => {
                try report.document.addText("I expected to find a } to close the imports.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add } after your imports.");
            },
            .expected_imports_open_curly => {
                try report.document.addText("I expected to find a { to start the imports.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add { before your imports.");
            },
            .expect_closing_paren => {
                try report.document.addText("I expected to find a ) to close this parenthesis.");
                try report.document.addLineBreak();
                try report.addSuggestion("Add ) to match the opening parenthesis.");
            },
            else => {
                try report.document.addFormattedText("I encountered a parse error: {s}", .{@tagName(tag)});
                try report.document.addLineBreak();
            },
        }

        // Add source context if available
        // TODO: Skip source context for parser errors due to TokenizedRegion vs Region type mismatch
        // if (self.addSourceContextFromRegion(&report, region, source_files)) {
        //     // Source context was added successfully
        // } else |_| {
        //     // Couldn't add source context, that's okay
        // }

        return report;
    }

    /// Convert canonicalize diagnostics to reports.
    fn canonicalizeToReport(
        self: *ProblemProcessor,
        diagnostic: anytype,
    ) !Report {
        const tag = diagnostic.tag;

        var report = switch (tag) {
            .not_implemented => Report.init(self.allocator, "NOT IMPLEMENTED", .fatal),
            .invalid_num_literal => Report.init(self.allocator, "INVALID NUMBER", .runtime_error),
            .ident_already_in_scope => Report.init(self.allocator, "SHADOWING", .runtime_error),
            .ident_not_in_scope => Report.init(self.allocator, "NOT IN SCOPE", .runtime_error),
            .invalid_top_level_statement => Report.init(self.allocator, "INVALID STATEMENT", .runtime_error),
            else => Report.init(self.allocator, "CANONICALIZE ERROR", .runtime_error),
        };

        // Add specific error messages based on the tag
        switch (tag) {
            .not_implemented => {
                try report.document.addText("This feature is not yet implemented in the Roc compiler.");
                try report.document.addLineBreak();
                try report.addNote("This is a limitation of the current compiler version.");
            },
            .invalid_num_literal => {
                try report.document.addText("This number literal is not valid.");
                try report.document.addLineBreak();
                try report.addSuggestion("Check that the number format is correct (e.g., 42, 3.14, 0x1F).");
            },
            .ident_already_in_scope => {
                try report.document.addText("This name is already defined in the current scope.");
                try report.document.addLineBreak();
                try report.addSuggestion("Choose a different name or remove the duplicate definition.");
            },
            .ident_not_in_scope => {
                try report.document.addText("I can't find this name in scope.");
                try report.document.addLineBreak();
                try report.addSuggestion("Make sure the name is spelled correctly and is defined in an accessible scope.");
            },
            .invalid_top_level_statement => {
                try report.document.addText("This statement is not allowed at the top level.");
                try report.document.addLineBreak();
                try report.addSuggestion("Top-level statements should be definitions, type annotations, or imports.");
            },
            else => {
                try report.document.addFormattedText("I encountered a canonicalization error: {s}", .{@tagName(tag)});
                try report.document.addLineBreak();
            },
        }

        // Add source context if available
        // TODO: Skip source context for canonicalize errors due to potential type mismatch
        // if (self.addSourceContextFromRegion(&report, region, source_files)) {
        //     // Source context was added successfully
        // } else |_| {
        //     // Couldn't add source context, that's okay
        // }

        return report;
    }

    /// Convert compiler errors to reports.
    fn compilerErrorToReport(
        self: *ProblemProcessor,
        compiler_error: anytype,
    ) !Report {
        return switch (compiler_error) {
            .canonicalize => |can_error| self.canErrorToReport(can_error),
            .resolve_imports => self.genericCompilerError("resolve_imports", "Failed to resolve imports"),
            .type_check => self.genericCompilerError("type_check", "Type checking failed"),
            .specialize_types => self.genericCompilerError("specialize_types", "Type specialization failed"),
            .lift_functions => self.genericCompilerError("lift_functions", "Function lifting failed"),
            .solve_functions => self.genericCompilerError("solve_functions", "Function solving failed"),
            .specialize_functions => self.genericCompilerError("specialize_functions", "Function specialization failed"),
            .lower_statements => self.genericCompilerError("lower_statements", "Statement lowering failed"),
            .reference_count => self.genericCompilerError("reference_count", "Reference counting failed"),
        };
    }

    /// Convert canonicalize compiler errors to reports.
    fn canErrorToReport(self: *ProblemProcessor, can_error: anytype) !Report {
        return switch (can_error) {
            .not_implemented => Templates.internalError(
                self.allocator,
                "A feature used in this code is not yet implemented.",
                "canonicalize",
            ),
            .exited_top_scope_level => Templates.internalError(
                self.allocator,
                "The compiler unexpectedly exited the top scope level.",
                "canonicalize",
            ),
            .unable_to_resolve_identifier => Templates.internalError(
                self.allocator,
                "The compiler was unable to resolve an identifier.",
                "canonicalize",
            ),
            .failed_to_canonicalize_decl => Templates.internalError(
                self.allocator,
                "The compiler failed to canonicalize a declaration.",
                "canonicalize",
            ),
            .unexpected_token_binop => Templates.internalError(
                self.allocator,
                "The compiler encountered an unexpected binary operator token.",
                "canonicalize",
            ),
            .concatenate_an_interpolated_string => Templates.internalError(
                self.allocator,
                "The compiler tried to concatenate an interpolated string incorrectly.",
                "canonicalize",
            ),
        };
    }

    /// Create a generic compiler error report.
    fn genericCompilerError(self: *ProblemProcessor, phase: []const u8, message: []const u8) !Report {
        return Templates.internalError(self.allocator, message, phase);
    }

    /// Add source context to a report based on a region.
    fn addSourceContextFromRegion(
        _region: Region,
        _source_files: anytype,
    ) !void {
        // Try to find the source file for this region
        // This is a simplified approach - in a real implementation,
        // we'd need to track which file each region belongs to
        var iterator = _source_files.iterator();
        while (iterator.next()) |entry| {
            const source_file = entry.value_ptr;

            // Check if the region is within this source file
            if (_region.start.offset < source_file.content.len and
                _region.end.offset <= source_file.content.len)
            {
                // Type mismatch - skip source context for now
                // TODO: Fix type conversion between TokenizedRegion and Region
                break;
            }
        }
    }

    /// Add source context from a specific source file.
    fn addSourceContextFromFile(
        self: *ProblemProcessor,
        report: *Report,
        region: Region,
        source_file: *const SourceFile,
    ) !void {
        _ = self;

        // Find the line containing the start of the region
        var current_offset: usize = 0;
        var line_start: u32 = 0;

        for (source_file.lines, 0..) |line, line_index| {
            const line_end = current_offset + line.len;

            if (current_offset <= region.start.offset and region.start.offset <= line_end) {
                line_start = @intCast(line_index);
                break;
            }

            current_offset = line_end + 1; // +1 for newline
        }

        // Calculate how many lines to show (context around the error)
        const context_lines: u32 = 2;
        const start_line = if (line_start >= context_lines) line_start - context_lines else 0;
        const end_line = @min(line_start + context_lines + 1, @as(u32, @intCast(source_file.lines.len)));

        // Extract the lines to show
        const lines_to_show = source_file.lines[start_line..end_line];

        // Calculate column positions for highlighting
        const line_content = source_file.lines[line_start];
        var line_offset: usize = 0;
        for (source_file.lines[0..line_start]) |prev_line| {
            line_offset += prev_line.len + 1; // +1 for newline
        }

        const col_start = if (region.start.offset >= line_offset)
            @as(u32, @intCast(region.start.offset - line_offset))
        else
            0;

        const col_end = if (region.end.offset >= line_offset)
            @as(u32, @intCast(region.end.offset - line_offset))
        else
            @as(u32, @intCast(line_content.len));

        try report.addSourceContext(
            lines_to_show,
            start_line + 1, // Line numbers are 1-indexed for display
            line_start + 1,
            col_start,
            col_end,
        );
    }
};

// Tests
const testing = std.testing;

test "ProblemProcessor creation" {
    var processor = ProblemProcessor.init(testing.allocator);
    defer processor.deinit();

    // Just test that we can create and destroy the processor
}

test "Generic compiler error handling" {
    var processor = ProblemProcessor.init(testing.allocator);
    defer processor.deinit();

    var report = try processor.genericCompilerError("test_phase", "Test error message");
    defer report.deinit();

    try testing.expectEqual(Severity.fatal, report.severity);
    try testing.expectEqualStrings("INTERNAL COMPILER ERROR", report.title);
}
