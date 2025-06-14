//! Diagnostics related to canonicalization

const std = @import("std");
const base = @import("../../base.zig");
const reporting = @import("../../reporting.zig");

const Region = base.Region;
const Ident = base.Ident;
const StringLiteral = base.StringLiteral;
const Document = reporting.Document;
const Allocator = std.mem.Allocator;

/// Different types of diagnostic errors
pub const Diagnostic = union(enum) {
    not_implemented: struct {
        feature: StringLiteral.Idx,
        region: Region,
    },
    invalid_num_literal: struct {
        literal: StringLiteral.Idx,
        region: Region,
    },
    ident_already_in_scope: struct {
        ident: Ident.Idx,
        region: Region,
    },
    ident_not_in_scope: struct {
        ident: Ident.Idx,
        region: Region,
    },
    invalid_top_level_statement: struct {
        region: Region,
    },
    expr_not_canonicalized: struct {
        region: Region,
    },
    invalid_string_interpolation: struct {
        region: Region,
    },
    pattern_arg_invalid: struct {
        region: Region,
    },
    pattern_not_canonicalized: struct {
        region: Region,
    },
    can_lambda_not_implemented: struct {
        region: Region,
    },
    lambda_body_not_canonicalized: struct {
        region: Region,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    /// Build a report for "not implemented" diagnostic
    pub fn buildNotImplementedReport(allocator: Allocator, feature: []const u8, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addText("This feature is not yet implemented: ");
        try doc.addText(feature);
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("This will be supported in a future version of Roc.");
        return doc;
    }

    /// Build a report for "invalid number literal" diagnostic
    pub fn buildInvalidNumLiteralReport(allocator: Allocator, literal: []const u8, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addText("This number literal is not valid: ");
        try doc.addText(literal);
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("Roc supports integers, floats, and scientific notation. Check that the number format is correct.");
        return doc;
    }

    /// Build a report for "identifier already in scope" diagnostic
    pub fn buildIdentAlreadyInScopeReport(allocator: Allocator, ident_name: []const u8, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addText("The name `");
        try doc.addUnqualifiedSymbol(ident_name);
        try doc.addText("` is already defined in this scope.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("Choose a different name for this identifier, or remove the duplicate definition.");
        return doc;
    }

    /// Build a report for "identifier not in scope" diagnostic
    pub fn buildIdentNotInScopeReport(allocator: Allocator, ident_name: []const u8, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addText("Nothing is named `");
        try doc.addUnqualifiedSymbol(ident_name);
        try doc.addText("` in this scope.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addText("Is there an ");
        try doc.addKeyword("import");
        try doc.addText(" or ");
        try doc.addKeyword("exposing");
        try doc.addReflowingText(" missing up-top?");
        return doc;
    }

    /// Build a report for "invalid top level statement" diagnostic
    pub fn buildInvalidTopLevelStatementReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("This statement is not allowed at the top level.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("Only definitions, type annotations, and imports are allowed at the top level.");
        return doc;
    }

    /// Build a report for "expression not canonicalized" diagnostic
    pub fn buildExprNotCanonicalizedReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("This looks like an operator, but it's not one I recognize!");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("Check the spelling and make sure you're using a valid Roc operator.");
        return doc;
    }

    /// Build a report for "invalid string interpolation" diagnostic
    pub fn buildInvalidStringInterpolationReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("This string interpolation is not valid.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("String interpolation should use the format: \"text $(expression) more text\"");
        return doc;
    }

    /// Build a report for "pattern argument invalid" diagnostic
    pub fn buildPatternArgInvalidReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("This pattern argument is not valid.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("Pattern arguments must be valid patterns like identifiers, literals, or destructuring patterns.");
        return doc;
    }

    /// Build a report for "pattern not canonicalized" diagnostic
    pub fn buildPatternNotCanonicalizedReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("This pattern could not be processed.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("This pattern contains invalid syntax or uses unsupported features.");
        return doc;
    }

    /// Build a report for "lambda not implemented" diagnostic
    pub fn buildCanLambdaNotImplementedReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("Lambda expressions are not yet fully implemented.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("Lambda expressions will be supported in a future version of Roc.");
        return doc;
    }

    /// Build a report for "lambda body not canonicalized" diagnostic
    pub fn buildLambdaBodyNotCanonicalizedReport(allocator: Allocator, source: []const u8, region: Region) !Document {
        var doc = Document.init(allocator);
        try doc.addReflowingText("The body of this lambda expression is not valid.");
        try doc.addLineBreak();
        try doc.addLineBreak();

        try doc.addSourceRegion(source, region.start.offset, region.start.offset, region.end.offset, region.end.offset, .error_highlight, null);

        try doc.addLineBreak();
        try doc.addReflowingText("The lambda body must be a valid expression.");
        return doc;
    }
};
