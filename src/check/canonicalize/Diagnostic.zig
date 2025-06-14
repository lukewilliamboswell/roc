//! Diagnostics related to canonicalization

const std = @import("std");
const base = @import("../../base.zig");
const reporting = @import("../../reporting.zig");

const Region = base.Region;

tag: Tag,
region: Region,

/// different types of diagnostic errors
pub const Tag = enum {
    not_implemented,
    invalid_num_literal,
    ident_already_in_scope,
    ident_not_in_scope,
    invalid_top_level_statement,
    expr_not_canonicalized,
    invalid_string_interpolation,
    pattern_arg_invalid,
    pattern_not_canonicalized,
    can_lambda_not_implemented,
    lambda_body_not_canonicalized,
};

/// Convert this diagnostic to a Report for rendering
pub fn toReport(self: @This(), allocator: std.mem.Allocator, source: []const u8) !reporting.Report {
    const message = switch (self.tag) {
        .not_implemented => "This feature is not yet implemented",
        .invalid_num_literal => "Invalid number literal",
        .ident_already_in_scope => "Identifier already exists in this scope",
        .ident_not_in_scope => "Identifier not found in scope",
        .invalid_top_level_statement => "Invalid statement at top level",
        .expr_not_canonicalized => "Expression could not be canonicalized",
        .invalid_string_interpolation => "Invalid string interpolation",
        .pattern_arg_invalid => "Invalid pattern argument",
        .pattern_not_canonicalized => "Pattern could not be canonicalized",
        .can_lambda_not_implemented => "Lambda canonicalization not implemented",
        .lambda_body_not_canonicalized => "Lambda body could not be canonicalized",
    };

    var report = reporting.Report.init(allocator, message, .runtime_error);

    // Add source context if we have a valid region
    if (self.region.start.offset < source.len and self.region.end.offset <= source.len) {
        const start_offset = self.region.start.offset;
        const end_offset = self.region.end.offset;
        const problem_text = source[start_offset..end_offset];
        try report.addCodeSnippet(problem_text, null);
    }

    return report;
}
