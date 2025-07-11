//!
//! This file implements the Intermediate Representation (IR) for Roc's parser.
//!
//! The IR provides a structured, tree-based representation of Roc source code after parsing
//!
//! The design uses an arena-based memory allocation strategy with a "multi-list" approach where nodes
//! are stored in a flat list but cross-referenced via indices rather than pointers. This improves
//! memory locality and efficiency.
//!
//! The implementation includes comprehensive facilities for building, manipulating, and traversing
//! the IR, as well as converting it to S-expressions for debugging and visualization.

const std = @import("std");
const testing = std.testing;
const base = @import("../../base.zig");
const tokenize = @import("tokenize.zig");
const collections = @import("../../collections.zig");
const reporting = @import("../../reporting.zig");

const Node = @import("Node.zig");
const NodeStore = @import("NodeStore.zig");
const Token = tokenize.Token;
const TokenizedBuffer = tokenize.TokenizedBuffer;
const exitOnOom = collections.utils.exitOnOom;

const SExpr = base.SExpr;
const Ident = base.Ident;
const Allocator = std.mem.Allocator;

const AST = @This();

source: []const u8,
tokens: TokenizedBuffer,
store: NodeStore,
root_node_idx: u32 = 0,
tokenize_diagnostics: std.ArrayListUnmanaged(tokenize.Diagnostic),
parse_diagnostics: std.ArrayListUnmanaged(AST.Diagnostic),

/// Calculate whether this region is - or will be - multiline
pub fn regionIsMultiline(self: *AST, region: TokenizedRegion) bool {
    var i = region.start;
    const tags = self.tokens.tokens.items(.tag);
    while (i <= region.end) {
        if (tags[i] == .Newline) {
            return true;
        }
        if (tags[i] == .Comma and (tags[i + 1] == .CloseSquare or
            tags[i + 1] == .CloseRound or
            tags[i + 1] == .CloseCurly))
        {
            return true;
        }
        i += 1;
    }
    return false;
}

/// Returns whether this AST has any diagnostic errors.
pub fn hasErrors(self: *AST) bool {
    return self.tokenize_diagnostics.items.len > 0 or self.parse_diagnostics.items.len > 0;
}

/// Returns diagnostic position information for the given region.
pub fn calcRegionInfo(self: *AST, region: TokenizedRegion, line_starts: []const u32) base.RegionInfo {
    const start = self.tokens.resolve(region.start);
    const end = self.tokens.resolve(region.end);
    const info = base.RegionInfo.position(self.source, line_starts, start.start.offset, end.end.offset) catch {
        // std.debug.panic("failed to calculate position info for region {?}, start: {}, end: {}", .{ region, start, end });
        return .{
            .start_line_idx = 0,
            .start_col_idx = 0,
            .end_line_idx = 0,
            .end_col_idx = 0,
            .line_text = "",
        };
    };

    return info;
}

/// Append region information to an S-expression node for diagnostics
pub fn appendRegionInfoToSexprNode(self: *AST, env: *base.ModuleEnv, node: *SExpr, region: TokenizedRegion) void {
    const start = self.tokens.resolve(region.start);
    const end = self.tokens.resolve(region.end);
    const info: base.RegionInfo = base.RegionInfo.position(self.source, env.line_starts.items, start.start.offset, end.end.offset) catch .{
        .start_line_idx = 0,
        .start_col_idx = 0,
        .end_line_idx = 0,
        .end_col_idx = 0,
        .line_text = "",
    };
    node.appendByteRange(
        env.gpa,
        info,
        start.start.offset,
        end.end.offset,
    );
}

pub fn deinit(self: *AST, gpa: std.mem.Allocator) void {
    defer self.tokens.deinit();
    defer self.store.deinit();
    defer self.tokenize_diagnostics.deinit(gpa);
    defer self.parse_diagnostics.deinit(gpa);
}

/// Convert a tokenize diagnostic to a Report for rendering
pub fn tokenizeDiagnosticToReport(self: *AST, diagnostic: tokenize.Diagnostic, allocator: std.mem.Allocator) !reporting.Report {
    _ = self; // TODO: Use self for source information
    const title = switch (diagnostic.tag) {
        .MisplacedCarriageReturn => "MISPLACED CARRIAGE RETURN",
        .AsciiControl => "ASCII CONTROL CHARACTER",
        .LeadingZero => "LEADING ZERO",
        .UppercaseBase => "UPPERCASE BASE",
        .InvalidUnicodeEscapeSequence => "INVALID UNICODE ESCAPE SEQUENCE",
        .InvalidEscapeSequence => "INVALID ESCAPE SEQUENCE",
        .UnclosedString => "UNCLOSED STRING",
        .UnclosedSingleQuote => "UNCLOSED SINGLE QUOTE",
        .OverClosedBrace => "OVER CLOSED BRACE",
        .MismatchedBrace => "MISMATCHED BRACE",
        .NonPrintableUnicodeInStrLiteral => "NON-PRINTABLE UNICODE IN STRING LITERAL",
    };

    const body = switch (diagnostic.tag) {
        .MisplacedCarriageReturn => "Carriage return characters (\\r) are not allowed in Roc source code.",
        .AsciiControl => "ASCII control characters are not allowed in Roc source code.",
        .LeadingZero => "Numbers cannot have leading zeros.",
        .UppercaseBase => "Number base prefixes must be lowercase (0x, 0o, 0b).",
        .InvalidUnicodeEscapeSequence => "This Unicode escape sequence is not valid.",
        .InvalidEscapeSequence => "This escape sequence is not recognized.",
        .UnclosedString => "This string is missing a closing quote.",
        .UnclosedSingleQuote => "This character literal is missing a closing single quote.",
        .OverClosedBrace => "There are too many closing braces here.",
        .MismatchedBrace => "This brace does not match the corresponding opening brace.",
        .NonPrintableUnicodeInStrLiteral => "Non-printable Unicode characters are not allowed in string literals.",
    };

    var report = reporting.Report.init(allocator, title, .runtime_error);
    try report.document.addText(body);
    return report;
}

/// Convert TokenizedRegion to base.Region for error reporting
pub fn tokenizedRegionToRegion(self: *AST, tokenized_region: TokenizedRegion) base.Region {
    const token_count: u32 = @intCast(self.tokens.tokens.len);

    // Ensure both start and end are within bounds
    const safe_start_idx = if (tokenized_region.start >= token_count)
        token_count - 1
    else
        tokenized_region.start;

    const safe_end_idx = if (tokenized_region.end >= token_count)
        token_count - 1
    else
        tokenized_region.end;

    // Ensure end is at least start to prevent invalid regions
    const final_end_idx = if (safe_end_idx < safe_start_idx)
        safe_start_idx
    else
        safe_end_idx;

    const start_region = self.tokens.resolve(safe_start_idx);
    const end_region = self.tokens.resolve(final_end_idx);
    return .{
        .start = start_region.start,
        .end = end_region.end,
    };
}

/// Get the text content of a token for error reporting
fn getTokenText(self: *AST, token_idx: Token.Idx) []const u8 {
    const token_region = self.tokens.resolve(@intCast(token_idx));
    return self.source[token_region.start.offset..token_region.end.offset];
}

/// Convert a parse diagnostic to a Report for rendering
pub fn parseDiagnosticToReport(self: *AST, diagnostic: Diagnostic, allocator: std.mem.Allocator, filename: []const u8) !reporting.Report {
    const raw_region = self.tokenizedRegionToRegion(diagnostic.region);

    // Ensure region bounds are valid for source slicing
    const region = base.Region{
        .start = .{ .offset = @min(raw_region.start.offset, self.source.len) },
        .end = .{ .offset = @min(@max(raw_region.end.offset, raw_region.start.offset), self.source.len) },
    };

    const title = switch (diagnostic.tag) {
        .bad_indent => "BAD INDENTATION",
        .multiple_platforms => "MULTIPLE PLATFORMS",
        .no_platform => "NO PLATFORM",
        .missing_header => "MISSING HEADER",
        .list_not_closed => "LIST NOT CLOSED",
        .missing_arrow => "MISSING ARROW",
        .expected_exposes => "EXPECTED EXPOSES",
        .expected_exposes_close_square => "EXPECTED CLOSING BRACKET",
        .expected_exposes_open_square => "EXPECTED OPENING BRACKET",
        .expected_imports => "EXPECTED IMPORTS",
        .expected_imports_close_curly => "EXPECTED CLOSING BRACE",
        .expected_imports_open_curly => "EXPECTED OPENING BRACE",
        .header_unexpected_token => "UNEXPECTED TOKEN IN HEADER",
        .pattern_unexpected_token => "UNEXPECTED TOKEN IN PATTERN",
        .pattern_list_rest_old_syntax => "BAD LIST REST PATTERN SYNTAX",
        .pattern_unexpected_eof => "UNEXPECTED END OF FILE IN PATTERN",
        .ty_anno_unexpected_token => "UNEXPECTED TOKEN IN TYPE ANNOTATION",
        .statement_unexpected_eof => "UNEXPECTED END OF FILE",
        .statement_unexpected_token => "UNEXPECTED TOKEN",
        .string_unexpected_token => "UNEXPECTED TOKEN IN STRING",
        .expr_unexpected_token => "UNEXPECTED TOKEN IN EXPRESSION",
        .import_must_be_top_level => "IMPORT MUST BE TOP LEVEL",
        .expected_expr_close_square_or_comma => "LIST NOT CLOSED",
        .where_expected_where => "WHERE CLAUSE ERROR",
        .where_expected_mod_open => "WHERE CLAUSE ERROR",
        .where_expected_var => "WHERE CLAUSE ERROR",
        .where_expected_mod_close => "WHERE CLAUSE ERROR",
        .where_expected_arg_open => "WHERE CLAUSE ERROR",
        .where_expected_arg_close => "WHERE CLAUSE ERROR",
        .where_expected_method_arrow => "WHERE CLAUSE ERROR",
        .where_expected_method_or_alias_name => "WHERE CLAUSE ERROR",
        .where_expected_module => "WHERE CLAUSE ERROR",
        .where_expected_colon => "WHERE CLAUSE ERROR",
        .where_expected_constraints => "WHERE CLAUSE ERROR",
        else => "PARSE ERROR",
    };

    var report = reporting.Report.init(allocator, title, .runtime_error);

    // Add detailed error message based on the diagnostic type
    switch (diagnostic.tag) {
        .missing_header => {
            try report.document.addReflowingText("Roc files must start with a module header.");
            try report.document.addLineBreak();
            try report.document.addLineBreak();
            try report.document.addText("For example:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addCodeBlock("module [main]");
            try report.document.addLineBreak();
            try report.document.addText("or for an app:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addCodeBlock("app [main!] { pf: platform \"../basic-cli/platform.roc\" }");
        },
        .multiple_platforms => {
            try report.document.addReflowingText("Only one platform declaration is allowed per file.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Remove the duplicate platform declaration.");
        },
        .no_platform => {
            try report.document.addReflowingText("App files must specify a platform.");
            try report.document.addLineBreak();
            try report.document.addText("Add a platform specification like:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addCodeBlock("{ pf: platform \"../basic-cli/platform.roc\" }");
        },
        .bad_indent => {
            try report.document.addReflowingText("The indentation here is inconsistent with the surrounding code.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Make sure to use consistent spacing for indentation.");
        },
        .list_not_closed => {
            try report.document.addReflowingText("This list is missing a closing bracket.");
            try report.document.addLineBreak();
            try report.document.addText("Add a ");
            try report.document.addAnnotated("]", .emphasized);
            try report.document.addText(" to close the list.");
        },
        .missing_arrow => {
            try report.document.addText("Expected an arrow ");
            try report.document.addAnnotated("->", .emphasized);
            try report.document.addText(" here.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Function type annotations require arrows between parameter and return types.");
        },
        .expected_exposes, .expected_exposes_close_square, .expected_exposes_open_square => {
            try report.document.addReflowingText("Module headers must have an ");
            try report.document.addKeyword("exposing");
            try report.document.addReflowingText(" section that lists what the module exposes.");
            try report.document.addLineBreak();
            try report.document.addText("For example: ");
            try report.document.addCodeBlock("module [main, add, subtract]");
        },
        .expected_imports, .expected_imports_close_curly, .expected_imports_open_curly => {
            try report.document.addReflowingText("Import statements must specify what is being imported.");
            try report.document.addLineBreak();
            try report.document.addText("For example: ");
            try report.document.addCodeBlock("import pf.Stdout exposing [line!]");
        },
        .header_unexpected_token => {
            // Try to get the actual token text
            const token_text = if (diagnostic.region.start != diagnostic.region.end)
                self.source[region.start.offset..region.end.offset]
            else
                "<unknown>";
            const owned_token = try report.addOwnedString(token_text);
            try report.document.addText("The token ");
            try report.document.addAnnotated(owned_token, .error_highlight);
            try report.document.addText(" is not expected in a module header.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Module headers should only contain the module name and exposing list.");
        },
        .pattern_unexpected_token => {
            const token_text = if (diagnostic.region.start != diagnostic.region.end)
                self.source[region.start.offset..region.end.offset]
            else
                "<unknown>";
            const owned_token = try report.addOwnedString(token_text);
            try report.document.addText("The token ");
            try report.document.addAnnotated(owned_token, .error_highlight);
            try report.document.addText(" is not expected in a pattern.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Patterns can contain identifiers, literals, lists, records, or tags.");
        },
        .pattern_list_rest_old_syntax => {
            try report.document.addReflowingText("List rest patterns should use the `.. as name` syntax, not `..name`.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("For example, use `[first, .. as rest]` instead of `[first, ..rest]`.");
        },
        .pattern_unexpected_eof => {
            try report.document.addReflowingText("This pattern is incomplete - the file ended unexpectedly.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Complete the pattern or remove the incomplete pattern.");
        },
        .ty_anno_unexpected_token => {
            const token_text = if (diagnostic.region.start != diagnostic.region.end)
                self.source[region.start.offset..region.end.offset]
            else
                "<unknown>";
            const owned_token = try report.addOwnedString(token_text);
            try report.document.addText("The token ");
            try report.document.addAnnotated(owned_token, .error_highlight);
            try report.document.addText(" is not expected in a type annotation.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Type annotations should contain types like ");
            try report.document.addType("Str");
            try report.document.addText(", ");
            try report.document.addType("Num a");
            try report.document.addText(", or ");
            try report.document.addType("List U64");
            try report.document.addText(".");
        },
        .statement_unexpected_eof => {
            try report.document.addReflowingText("This statement is incomplete - the file ended unexpectedly.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Complete the statement or remove the incomplete statement.");
        },
        .statement_unexpected_token => {
            const token_text = if (diagnostic.region.start != diagnostic.region.end)
                self.source[region.start.offset..region.end.offset]
            else
                "<unknown>";
            const owned_token = try report.addOwnedString(token_text);
            try report.document.addText("The token ");
            try report.document.addAnnotated(owned_token, .error_highlight);
            try report.document.addText(" is not expected in a statement.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Statements can be definitions, assignments, or expressions.");
        },
        .string_unexpected_token => {
            const token_text = if (diagnostic.region.start != diagnostic.region.end)
                self.source[region.start.offset..region.end.offset]
            else
                "<unknown>";
            const owned_token = try report.addOwnedString(token_text);
            try report.document.addText("The token ");
            try report.document.addAnnotated(owned_token, .error_highlight);
            try report.document.addText(" is not expected in a string literal.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("String literals should be enclosed in double quotes.");
        },
        .expr_unexpected_token => {
            const token_text = if (diagnostic.region.start != diagnostic.region.end)
                self.source[region.start.offset..region.end.offset]
            else
                "<unknown>";
            const owned_token = try report.addOwnedString(token_text);
            try report.document.addText("The token ");
            try report.document.addAnnotated(owned_token, .error_highlight);
            try report.document.addText(" is not expected in an expression.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Expressions can be identifiers, literals, function calls, or operators.");
        },
        .import_must_be_top_level => {
            try report.document.addReflowingText("Import statements must appear at the top level of a module.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Move this import to the top of the file, after the module header but before any definitions.");
        },
        .expected_expr_close_square_or_comma => {
            try report.document.addReflowingText("This list is missing a closing bracket or has a syntax error.");
            try report.document.addLineBreak();
            try report.document.addText("Lists must be closed with ");
            try report.document.addAnnotated("]", .emphasized);
            try report.document.addText(" and list items must be separated by commas.");
            try report.document.addLineBreak();
            try report.document.addText("For example: ");
            try report.document.addCodeBlock("[1, 2, 3]");
        },
        .expected_colon_after_type_annotation => {
            try report.document.addReflowingText("Type applications require parentheses around their type arguments.");
            try report.document.addLineBreak();
            try report.document.addLineBreak();
            try report.document.addReflowingText("I found a type followed by what looks like a type argument, but they need to be connected with parentheses.");
            try report.document.addLineBreak();
            try report.document.addLineBreak();
            try report.document.addText("Instead of:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addAnnotated("List U8", .error_highlight);
            try report.document.addLineBreak();
            try report.document.addLineBreak();
            try report.document.addText("Use:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addAnnotated("List(U8)", .emphasized);
            try report.document.addLineBreak();
            try report.document.addLineBreak();
            try report.document.addText("Other valid examples:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addAnnotated("Dict(Str, Num)", .dimmed);
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addAnnotated("Result(a, Str)", .dimmed);
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addAnnotated("Maybe(List(U64))", .dimmed);
        },
        .where_expected_where => {
            try report.document.addReflowingText("Expected a ");
            try report.document.addKeyword("where");
            try report.document.addText(" clause here.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Where clauses define constraints on type variables.");
        },
        .where_expected_mod_open => {
            try report.document.addReflowingText("Expected an opening parenthesis after ");
            try report.document.addKeyword("module");
            try report.document.addText(" in this where clause.");
            try report.document.addLineBreak();
            try report.document.addText("Module constraints should look like: ");
            try report.document.addCodeBlock("module(a).method : Type");
        },
        .where_expected_var => {
            try report.document.addReflowingText("Expected a type variable name here.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Type variables are lowercase identifiers that represent types.");
        },
        .where_expected_mod_close => {
            try report.document.addReflowingText("Expected a closing parenthesis after the type variable in this module constraint.");
            try report.document.addLineBreak();
            try report.document.addText("Module constraints should look like: ");
            try report.document.addCodeBlock("module(a).method : Type");
        },
        .where_expected_arg_open => {
            try report.document.addReflowingText("Expected an opening parenthesis for the method arguments.");
            try report.document.addLineBreak();
            try report.document.addText("Method constraints should look like: ");
            try report.document.addCodeBlock("module(a).method : args -> ret");
        },
        .where_expected_arg_close => {
            try report.document.addReflowingText("Expected a closing parenthesis after the method arguments.");
            try report.document.addLineBreak();
            try report.document.addText("Method constraints should look like: ");
            try report.document.addCodeBlock("module(a).method : args -> ret");
        },
        .where_expected_method_arrow => {
            try report.document.addReflowingText("Expected an arrow ");
            try report.document.addAnnotated("->", .emphasized);
            try report.document.addText(" after the method arguments.");
            try report.document.addLineBreak();
            try report.document.addText("Method constraints should look like: ");
            try report.document.addCodeBlock("module(a).method : args -> ret");
        },
        .where_expected_method_or_alias_name => {
            try report.document.addReflowingText("Expected a method name or type alias after the dot.");
            try report.document.addLineBreak();
            try report.document.addText("Where clauses can contain:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addText("• Method constraints: ");
            try report.document.addCodeBlock("module(a).method : args -> ret");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addText("• Type aliases: ");
            try report.document.addCodeBlock("module(a).SomeTypeAlias");
        },
        .where_expected_module => {
            try report.document.addReflowingText("Expected ");
            try report.document.addKeyword("module");
            try report.document.addText(" at the start of this where clause constraint.");
            try report.document.addLineBreak();
            try report.document.addText("Where clauses can contain:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addText("• Method constraints: ");
            try report.document.addCodeBlock("module(a).method : Type");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addText("• Type aliases: ");
            try report.document.addCodeBlock("module(a).SomeType");
        },
        .where_expected_colon => {
            try report.document.addReflowingText("Expected a colon ");
            try report.document.addAnnotated(":", .emphasized);
            try report.document.addText(" after the method name in this where clause constraint.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Method constraints require a colon to separate the method name from its type.");
            try report.document.addLineBreak();
            try report.document.addText("For example: ");
            try report.document.addCodeBlock("module(a).method : a -> b");
        },
        .where_expected_constraints => {
            try report.document.addReflowingText("A ");
            try report.document.addKeyword("where");
            try report.document.addText(" clause cannot be empty.");
            try report.document.addLineBreak();
            try report.document.addReflowingText("Where clauses must contain at least one constraint.");
            try report.document.addLineBreak();
            try report.document.addText("For example:");
            try report.document.addLineBreak();
            try report.document.addIndent(1);
            try report.document.addCodeBlock("module(a).method : a -> b");
        },
        else => {
            const tag_name = @tagName(diagnostic.tag);
            const owned_tag = try report.addOwnedString(tag_name);
            try report.document.addText("A parsing error occurred: ");
            try report.document.addAnnotated(owned_tag, .dimmed);
            try report.document.addLineBreak();
            try report.document.addReflowingText("This is an unexpected parsing error. Please check your syntax.");
        },
    }

    // Add source context if we have a valid region
    if (region.start.offset <= region.end.offset and region.end.offset <= self.source.len) {
        // Compute line_starts from source for proper region info calculation
        var line_starts = std.ArrayList(u32).init(allocator);
        defer line_starts.deinit();

        try line_starts.append(0); // First line starts at 0
        for (self.source, 0..) |char, i| {
            if (char == '\n') {
                try line_starts.append(@intCast(i + 1));
            }
        }

        // Use proper region info calculation with converted region
        const region_info = base.RegionInfo.position(self.source, line_starts.items, region.start.offset, region.end.offset) catch {
            return report; // Return report without source context if region calculation fails
        };

        try report.document.addLineBreak();
        try report.document.addLineBreak();
        try report.document.addText("Here is the problematic code:");
        try report.document.addLineBreak();

        // Use the proper addSourceContext method
        try report.addSourceContext(region_info, filename);
    }

    return report;
}

/// Diagnostics related to parsing
pub const Diagnostic = struct {
    tag: Tag,
    region: TokenizedRegion,

    /// different types of diagnostic errors
    pub const Tag = enum {
        bad_indent,
        multiple_platforms,
        no_platform,
        missing_header,
        list_not_closed,
        missing_arrow,
        expected_exposes,
        expected_exposes_close_square,
        expected_exposes_open_square,
        expected_imports,
        expected_imports_close_curly,
        expected_imports_open_curly,
        expected_package_or_platform_name,
        expected_package_or_platform_colon,
        expected_package_or_platform_string,
        expected_package_platform_close_curly,
        expected_package_platform_open_curly,
        expected_packages,
        expected_packages_close_curly,
        expected_packages_open_curly,
        expected_platform_name_end,
        expected_platform_name_start,
        expected_platform_name_string,
        expected_platform_string,
        expected_provides,
        expected_provides_close_square,
        expected_provides_open_square,
        expected_requires,
        expected_requires_rigids_close_curly,
        expected_requires_rigids_open_curly,
        expected_requires_signatures_close_curly,
        expected_requires_signatures_open_curly,
        expect_closing_paren,
        header_expected_open_square,
        header_expected_close_square,
        header_unexpected_token,
        pattern_unexpected_token,
        pattern_list_rest_old_syntax,
        pattern_unexpected_eof,
        bad_as_pattern_name,
        ty_anno_unexpected_token,
        statement_unexpected_eof,
        statement_unexpected_token,
        string_unexpected_token,
        string_expected_close_interpolation,
        expr_if_missing_else,
        expr_no_space_dot_int,
        import_exposing_no_open,
        import_exposing_no_close,
        no_else,
        expected_type_field_name,
        expected_colon_after_type_field_name,
        expected_arrow,
        expected_ty_close_curly_or_comma,
        expected_ty_close_square_or_comma,
        expected_lower_name_after_exposed_item_as,
        expected_upper_name_after_exposed_item_as,
        exposed_item_unexpected_token,
        expected_upper_name_after_import_as,
        expected_colon_after_type_annotation,
        expected_lower_ident_pat_field_name,
        expected_colon_after_pat_field_name,
        expected_expr_bar,
        expected_expr_close_curly_or_comma,
        expected_expr_close_round_or_comma,
        expected_expr_close_square_or_comma,
        expected_close_curly_at_end_of_match,
        expected_open_curly_after_match,
        expr_unexpected_token,
        expected_expr_record_field_name,
        expected_ty_apply_close_round,
        expected_ty_anno_end_of_function,
        expected_ty_anno_end,
        expected_expr_apply_close_round,
        where_expected_where,
        where_expected_mod_open,
        where_expected_var,
        where_expected_mod_close,
        where_expected_arg_open,
        where_expected_arg_close,
        where_expected_method_arrow,
        where_expected_method_or_alias_name,
        where_expected_module,
        where_expected_colon,
        where_expected_constraints,
        import_must_be_top_level,
        invalid_type_arg,
        expr_arrow_expects_ident,
        var_only_allowed_in_a_body,
        var_must_have_ident,
        var_expected_equals,
        for_expected_in,
    };
};

/// The first and last token consumed by a Node
pub const TokenizedRegion = struct {
    start: Token.Idx,
    end: Token.Idx,

    pub fn empty() TokenizedRegion {
        return .{ .start = 0, .end = 0 };
    }

    pub fn spanAcross(self: TokenizedRegion, other: TokenizedRegion) TokenizedRegion {
        return .{
            .start = self.start,
            .end = other.end,
        };
    }

    pub fn toBase(self: TokenizedRegion) base.Region {
        return .{
            .start = base.Region.Position{ .offset = self.start },
            .end = base.Region.Position{ .offset = self.end },
        };
    }
};

/// Resolve a token index to a string slice from the source code.
pub fn resolve(self: *AST, token: Token.Idx) []const u8 {
    const range = self.tokens.resolve(token);
    return self.source[@intCast(range.start.offset)..@intCast(range.end.offset)];
}

/// Resolves a fully qualified name from a chain of qualifier tokens and a final token.
/// If there are qualifiers, returns a slice from the first qualifier to the final token.
/// Otherwise, returns the final token text with any leading dot stripped based on the token type.
pub fn resolveQualifiedName(
    self: *AST,
    qualifiers: Token.Span,
    final_token: Token.Idx,
    strip_dot_from_tokens: []const Token.Tag,
) []const u8 {
    const qualifier_tokens = self.store.tokenSlice(qualifiers);

    if (qualifier_tokens.len > 0) {
        // Get the region of the first qualifier token
        const first_qualifier_tok = @as(Token.Idx, @intCast(qualifier_tokens[0]));
        const first_region = self.tokens.resolve(first_qualifier_tok);

        // Get the region of the final token
        const final_region = self.tokens.resolve(final_token);

        // Slice from the start of the first qualifier to the end of the final token
        const start_offset = first_region.start.offset;
        const end_offset = final_region.end.offset;

        return self.source[@intCast(start_offset)..@intCast(end_offset)];
    } else {
        // Get the raw token text and strip leading dot if it's one of the specified tokens
        const raw_text = self.resolve(final_token);
        const token_tag = self.tokens.tokens.items(.tag)[@intCast(final_token)];

        for (strip_dot_from_tokens) |dot_token_tag| {
            if (token_tag == dot_token_tag and raw_text.len > 0 and raw_text[0] == '.') {
                return raw_text[1..];
            }
        }

        return raw_text;
    }
}

/// Contains properties of the thing to the right of the `import` keyword.
pub const ImportRhs = packed struct {
    /// e.g. 1 in case we use import `as`: `import Module as Mod`
    aliased: u1,
    /// 1 in case the import is qualified, e.g. `pf` in `import pf.Stdout ...`
    qualified: u1,
    /// The number of things in the exposes list. e.g. 3 in `import SomeModule exposing [a1, a2, a3]`
    num_exposes: u30,
};

// Check that all packed structs are 4 bytes size as they as cast to
// and from a u32
comptime {
    std.debug.assert(@sizeOf(Header.AppHeaderRhs) == 4);
    std.debug.assert(@sizeOf(ImportRhs) == 4);
}

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}

/// Helper function to convert the AST to a human friendly representation in S-expression format
pub fn toSExprStr(ast: *@This(), env: *base.ModuleEnv, writer: std.io.AnyWriter) !void {
    const file = ast.store.getFile();

    var node = file.toSExpr(env, ast);
    defer node.deinit(env.gpa);

    node.toStringPretty(writer);
}

/// The kind of the type declaration represented, either:
/// 1. An alias of the form `Foo = (Bar, Baz)`
/// 2. A nominal type of the form `Foo := [Bar, Baz]`
pub const TypeDeclKind = enum {
    alias,
    nominal,
};

/// Represents a statement.  Not all statements are valid in all positions.
pub const Statement = union(enum) {
    decl: Decl,
    @"var": struct {
        name: Token.Idx,
        body: Expr.Idx,
        region: TokenizedRegion,
    },
    expr: struct {
        expr: Expr.Idx,
        region: TokenizedRegion,
    },
    crash: struct {
        expr: Expr.Idx,
        region: TokenizedRegion,
    },
    expect: struct {
        body: Expr.Idx,
        region: TokenizedRegion,
    },
    @"for": struct {
        patt: Pattern.Idx,
        expr: Expr.Idx,
        body: Expr.Idx,
        region: TokenizedRegion,
    },
    @"return": struct {
        expr: Expr.Idx,
        region: TokenizedRegion,
    },
    import: struct {
        module_name_tok: Token.Idx,
        qualifier_tok: ?Token.Idx,
        alias_tok: ?Token.Idx,
        exposes: ExposedItem.Span,
        region: TokenizedRegion,
    },
    type_decl: struct {
        header: TypeHeader.Idx,
        anno: TypeAnno.Idx,
        where: ?Collection.Idx,
        kind: TypeDeclKind,
        region: TokenizedRegion,
    },
    type_anno: struct {
        name: Token.Idx,
        anno: TypeAnno.Idx,
        where: ?Collection.Idx,
        region: TokenizedRegion,
    },
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub const Decl = struct {
        pattern: Pattern.Idx,
        body: Expr.Idx,
        region: TokenizedRegion,
    };

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        switch (self) {
            .decl => |decl| {
                var node = SExpr.init(env.gpa, "s-decl");
                ast.appendRegionInfoToSexprNode(env, &node, decl.region);
                // pattern
                {
                    const pattern = ast.store.getPattern(decl.pattern);
                    var pattern_node = pattern.toSExpr(env, ast);
                    node.appendNode(env.gpa, &pattern_node);
                }
                // body
                {
                    const body = ast.store.getExpr(decl.body);
                    var body_node = body.toSExpr(env, ast);
                    node.appendNode(env.gpa, &body_node);
                }
                return node;
            },
            .@"var" => |v| {
                var node = SExpr.init(env.gpa, "s-var");
                ast.appendRegionInfoToSexprNode(env, &node, v.region);

                const name_str = ast.resolve(v.name);
                node.appendStringAttr(env.gpa, "name", name_str);

                const body = ast.store.getExpr(v.body);
                var body_node = body.toSExpr(env, ast);
                node.appendNode(env.gpa, &body_node);

                return node;
            },
            .expr => |expr| {
                return ast.store.getExpr(expr.expr).toSExpr(env, ast);
            },
            .import => |import| {
                var node = SExpr.init(env.gpa, "s-import");
                ast.appendRegionInfoToSexprNode(env, &node, import.region);

                // Reconstruct full qualified module name
                const module_name_raw = ast.resolve(import.module_name_tok);
                if (import.qualifier_tok) |tok| {
                    const qualifier_str = ast.resolve(tok);
                    // Strip leading dot from module name if present
                    const module_name_clean = if (module_name_raw.len > 0 and module_name_raw[0] == '.')
                        module_name_raw[1..]
                    else
                        module_name_raw;

                    // Combine qualifier and module name
                    const full_module_name = std.fmt.allocPrint(env.gpa, "{s}.{s}", .{ qualifier_str, module_name_clean }) catch |err| exitOnOom(err);
                    defer env.gpa.free(full_module_name);
                    node.appendStringAttr(env.gpa, "raw", full_module_name);
                } else {
                    node.appendStringAttr(env.gpa, "raw", module_name_raw);
                }

                // alias e.g. `OUT` in `import pf.Stdout as OUT`
                if (import.alias_tok) |tok| {
                    const qualifier_str = ast.resolve(tok);
                    node.appendStringAttr(env.gpa, "alias", qualifier_str);
                }

                // exposed identifiers e.g. [foo, bar] in `import pf.Stdout exposing [foo, bar]`
                const exposed_slice = ast.store.exposedItemSlice(import.exposes);
                if (exposed_slice.len > 0) {
                    var exposed = SExpr.init(env.gpa, "exposing");
                    for (ast.store.exposedItemSlice(import.exposes)) |e| {
                        var exposed_item = ast.store.getExposedItem(e).toSExpr(env, ast);
                        exposed.appendNode(env.gpa, &exposed_item);
                    }
                    node.appendNode(env.gpa, &exposed);
                }
                return node;
            },
            // (type_decl (header <name> [<args>]) <annotation>)
            .type_decl => |a| {
                var node = SExpr.init(env.gpa, "s-type-decl");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                var header = SExpr.init(env.gpa, "header");

                // pattern
                {
                    // Check if the type header node is malformed before calling getTypeHeader
                    const header_node = ast.store.nodes.get(@enumFromInt(@intFromEnum(a.header)));
                    if (header_node.tag == .malformed) {
                        // Handle malformed type header by creating a placeholder
                        ast.appendRegionInfoToSexprNode(env, &header, header_node.region);
                        header.appendStringAttr(env.gpa, "name", "<malformed>");
                        var args_node = SExpr.init(env.gpa, "args");
                        header.appendNode(env.gpa, &args_node);
                    } else {
                        const ty_header = ast.store.getTypeHeader(a.header);
                        ast.appendRegionInfoToSexprNode(env, &header, ty_header.region);
                        header.appendStringAttr(env.gpa, "name", ast.resolve(ty_header.name));

                        var args_node = SExpr.init(env.gpa, "args");

                        for (ast.store.typeAnnoSlice(ty_header.args)) |b| {
                            const anno = ast.store.getTypeAnno(b);
                            var anno_sexpr = anno.toSExpr(env, ast);
                            args_node.appendNode(env.gpa, &anno_sexpr);
                        }
                        header.appendNode(env.gpa, &args_node);
                    }

                    node.appendNode(env.gpa, &header);
                }

                // annotation
                {
                    var annotation = ast.store.getTypeAnno(a.anno).toSExpr(env, ast);
                    node.appendNode(env.gpa, &annotation);
                }

                // where clause
                if (a.where) |where_coll| {
                    var where_node = SExpr.init(env.gpa, "where");
                    const where_clauses = ast.store.whereClauseSlice(.{ .span = ast.store.getCollection(where_coll).span });
                    for (where_clauses) |clause_idx| {
                        var clause_child = ast.store.getWhereClause(clause_idx).toSExpr(env, ast);
                        where_node.appendNode(env.gpa, &clause_child);
                    }
                    node.appendNode(env.gpa, &where_node);
                }
                return node;
            },
            // (crash <expr>)
            .crash => |a| {
                var node = SExpr.init(env.gpa, "s-crash");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var child = ast.store.getExpr(a.expr).toSExpr(env, ast);
                node.appendNode(env.gpa, &child);
                return node;
            },
            // (expect <body>)
            .expect => |a| {
                var node = SExpr.init(env.gpa, "s-expect");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var child = ast.store.getExpr(a.body).toSExpr(env, ast);
                node.appendNode(env.gpa, &child);
                return node;
            },
            .@"for" => |a| {
                var node = SExpr.init(env.gpa, "s-for");

                // patt
                {
                    var child = ast.store.getPattern(a.patt).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }
                // expr
                {
                    var child = ast.store.getExpr(a.expr).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }
                // body
                {
                    var child = ast.store.getExpr(a.body).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }

                return node;
            },
            // (return <expr>)
            .@"return" => |a| {
                var node = SExpr.init(env.gpa, "s-return");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var child = ast.store.getExpr(a.expr).toSExpr(env, ast);
                node.appendNode(env.gpa, &child);
                return node;
            },
            // (type_anno <annotation>)
            .type_anno => |a| {
                var node = SExpr.init(env.gpa, "s-type-anno");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                node.appendStringAttr(env.gpa, "name", ast.resolve(a.name));

                var child = ast.store.getTypeAnno(a.anno).toSExpr(env, ast);
                node.appendNode(env.gpa, &child);

                if (a.where) |where_coll| {
                    var where_node = SExpr.init(env.gpa, "where");
                    const where_clauses = ast.store.whereClauseSlice(.{ .span = ast.store.getCollection(where_coll).span });
                    for (where_clauses) |clause_idx| {
                        var clause_child = ast.store.getWhereClause(clause_idx).toSExpr(env, ast);
                        where_node.appendNode(env.gpa, &clause_child);
                    }
                    node.appendNode(env.gpa, &where_node);
                }

                return node;
            },
            .malformed => |a| {
                var node = SExpr.init(env.gpa, "s-malformed");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "tag", @tagName(a.reason));
                return node;
            },
        }
    }
};

/// Represents a Body, or a block of statements.
pub const Body = struct {
    /// The statements that constitute the block
    statements: Statement.Span,
    region: TokenizedRegion,

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var block_node = SExpr.init(env.gpa, "e-block");
        ast.appendRegionInfoToSexprNode(env, &block_node, self.region);
        var statements_node = SExpr.init(env.gpa, "statements");

        for (ast.store.statementSlice(self.statements)) |stmt_idx| {
            const stmt = ast.store.getStatement(stmt_idx);

            var stmt_node = stmt.toSExpr(env, ast);

            statements_node.appendNode(env.gpa, &stmt_node);
        }

        block_node.appendNode(env.gpa, &statements_node);

        return block_node;
    }
};

/// Represents a Pattern used in pattern matching.
pub const Pattern = union(enum) {
    ident: struct {
        ident_tok: Token.Idx,
        region: TokenizedRegion,
    },
    tag: struct {
        tag_tok: Token.Idx,
        args: Pattern.Span,
        region: TokenizedRegion,
    },
    int: struct {
        number_tok: Token.Idx,
        region: TokenizedRegion,
    },
    frac: struct {
        number_tok: Token.Idx,
        region: TokenizedRegion,
    },
    string: struct {
        string_tok: Token.Idx,
        region: TokenizedRegion,
        expr: Expr.Idx,
    },
    single_quote: struct {
        token: Token.Idx,
        region: TokenizedRegion,
    },
    record: struct {
        fields: PatternRecordField.Span,
        region: TokenizedRegion,
    },
    list: struct {
        patterns: Pattern.Span,
        region: TokenizedRegion,
    },
    list_rest: struct {
        name: ?Token.Idx,
        region: TokenizedRegion,
    },
    tuple: struct {
        patterns: Pattern.Span,
        region: TokenizedRegion,
    },
    underscore: struct {
        region: TokenizedRegion,
    },
    alternatives: struct {
        patterns: Pattern.Span,
        region: TokenizedRegion,
    },
    as: struct {
        pattern: Pattern.Idx,
        name: Token.Idx,
        region: TokenizedRegion,
    },
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn to_tokenized_region(self: @This()) TokenizedRegion {
        return switch (self) {
            .ident => |p| p.region,
            .tag => |p| p.region,
            .int => |p| p.region,
            .frac => |p| p.region,
            .string => |p| p.region,
            .single_quote => |p| p.region,
            .record => |p| p.region,
            .list => |p| p.region,
            .list_rest => |p| p.region,
            .tuple => |p| p.region,
            .underscore => |p| p.region,
            .alternatives => |p| p.region,
            .as => |p| p.region,
            .malformed => |p| p.region,
        };
    }

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        switch (self) {
            .ident => |ident| {
                var node = SExpr.init(env.gpa, "p-ident");

                ast.appendRegionInfoToSexprNode(env, &node, ident.region);

                node.appendStringAttr(env.gpa, "raw", ast.resolve(ident.ident_tok));

                return node;
            },
            .tag => |tag| {
                var node = SExpr.init(env.gpa, "p-tag");

                ast.appendRegionInfoToSexprNode(env, &node, tag.region);

                node.appendStringAttr(env.gpa, "raw", ast.resolve(tag.tag_tok));

                // Add arguments if there are any
                for (ast.store.patternSlice(tag.args)) |arg| {
                    var arg_node = ast.store.getPattern(arg).toSExpr(env, ast);
                    node.appendNode(env.gpa, &arg_node);
                }

                return node;
            },
            .int => |num| {
                var node = SExpr.init(env.gpa, "p-int");
                ast.appendRegionInfoToSexprNode(env, &node, num.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(num.number_tok));
                return node;
            },
            .frac => |num| {
                var node = SExpr.init(env.gpa, "p-frac");
                ast.appendRegionInfoToSexprNode(env, &node, num.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(num.number_tok));
                return node;
            },
            .string => |str| {
                var node = SExpr.init(env.gpa, "p-string");
                ast.appendRegionInfoToSexprNode(env, &node, str.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(str.string_tok));
                return node;
            },
            .single_quote => |sq| {
                var node = SExpr.init(env.gpa, "p-single-quote");
                ast.appendRegionInfoToSexprNode(env, &node, sq.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(sq.token));
                return node;
            },
            .record => |rec| {
                var node = SExpr.init(env.gpa, "p-record");
                ast.appendRegionInfoToSexprNode(env, &node, rec.region);

                for (ast.store.patternRecordFieldSlice(rec.fields)) |field_idx| {
                    const field = ast.store.getPatternRecordField(field_idx);
                    var field_node = SExpr.init(env.gpa, "field");
                    ast.appendRegionInfoToSexprNode(env, &field_node, field.region);
                    field_node.appendStringAttr(env.gpa, "name", ast.resolve(field.name));

                    if (field.value) |value| {
                        var value_node = ast.store.getPattern(value).toSExpr(env, ast);
                        field_node.appendNode(env.gpa, &value_node);
                    }

                    field_node.appendBoolAttr(env.gpa, "rest", field.rest);

                    node.appendNode(env.gpa, &field_node);
                }

                return node;
            },
            .list => |list| {
                var node = SExpr.init(env.gpa, "p-list");
                ast.appendRegionInfoToSexprNode(env, &node, list.region);

                for (ast.store.patternSlice(list.patterns)) |pat| {
                    var pattern_node = ast.store.getPattern(pat).toSExpr(env, ast);
                    node.appendNode(env.gpa, &pattern_node);
                }

                return node;
            },
            .list_rest => |rest| {
                var node = SExpr.init(env.gpa, "p-list-rest");
                ast.appendRegionInfoToSexprNode(env, &node, rest.region);

                if (rest.name) |name_tok| {
                    node.appendStringAttr(env.gpa, "name", ast.resolve(name_tok));
                }

                return node;
            },
            .tuple => |tuple| {
                var node = SExpr.init(env.gpa, "p-tuple");
                ast.appendRegionInfoToSexprNode(env, &node, tuple.region);

                for (ast.store.patternSlice(tuple.patterns)) |pat| {
                    var pattern_node = ast.store.getPattern(pat).toSExpr(env, ast);
                    node.appendNode(env.gpa, &pattern_node);
                }

                return node;
            },
            .underscore => {
                return SExpr.init(env.gpa, "p-underscore");
            },
            .alternatives => |a| {
                // '|' separated list of patterns
                var node = SExpr.init(env.gpa, "p-alternatives");
                for (ast.store.patternSlice(a.patterns)) |pat| {
                    var patNode = ast.store.getPattern(pat).toSExpr(env, ast);
                    node.appendNode(env.gpa, &patNode);
                }
                return node;
            },
            .as => |a| {
                var node = SExpr.init(env.gpa, "p-as");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var pattern_node = ast.store.getPattern(a.pattern).toSExpr(env, ast);
                node.appendStringAttr(env.gpa, "name", ast.resolve(a.name));
                node.appendNode(env.gpa, &pattern_node);
                return node;
            },
            .malformed => |a| {
                var node = SExpr.init(env.gpa, "p-malformed");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "tag", @tagName(a.reason));
                return node;
            },
        }
    }
};

/// TODO
pub const BinOp = struct {
    left: Expr.Idx,
    right: Expr.Idx,
    operator: Token.Idx,
    region: TokenizedRegion,

    /// (binop <op> <left> <right>) e.g. (binop '+' 1 2)
    pub fn toSExpr(self: *const @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var node = SExpr.init(env.gpa, "e-binop");
        ast.appendRegionInfoToSexprNode(env, &node, self.region);
        node.appendStringAttr(env.gpa, "op", ast.resolve(self.operator));

        var left = ast.store.getExpr(self.left).toSExpr(env, ast);
        node.appendNode(env.gpa, &left);

        var right = ast.store.getExpr(self.right).toSExpr(env, ast);
        node.appendNode(env.gpa, &right);
        return node;
    }
};

/// TODO
pub const Unary = struct {
    operator: Token.Idx,
    expr: Expr.Idx,
    region: TokenizedRegion,

    pub fn toSExpr(self: *const @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var node = SExpr.init(env.gpa, "unary");
        ast.appendRegionInfoToSexprNode(env, &node, self.region);
        node.appendStringAttr(env.gpa, "op", ast.resolve(self.operator));

        var expr = ast.store.getExpr(self.expr).toSExpr(env, ast);
        node.appendNode(env.gpa, &expr);

        return node;
    }
};

/// Represents a delimited collection of other nodes
pub const Collection = struct {
    span: base.DataSpan,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
};

/// Represents a Roc file.
pub const File = struct {
    header: Header.Idx,
    statements: Statement.Span,
    region: TokenizedRegion,

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var file_node = SExpr.init(env.gpa, "file");

        ast.appendRegionInfoToSexprNode(env, &file_node, self.region);

        const header = ast.store.getHeader(self.header);
        var header_node = header.toSExpr(env, ast);

        file_node.appendNode(env.gpa, &header_node);

        var statements_node = SExpr.init(env.gpa, "statements");

        for (ast.store.statementSlice(self.statements)) |stmt_id| {
            const stmt = ast.store.getStatement(stmt_id);
            var stmt_node = stmt.toSExpr(env, ast);
            statements_node.appendNode(env.gpa, &stmt_node);
        }

        file_node.appendNode(env.gpa, &statements_node);

        return file_node;
    }
};

/// Represents a module header.
pub const Header = union(enum) {
    app: struct {
        provides: Collection.Idx,
        platform_idx: RecordField.Idx,
        packages: Collection.Idx,
        region: TokenizedRegion,
    },
    module: struct {
        exposes: Collection.Idx,
        region: TokenizedRegion,
    },
    package: struct {
        exposes: Collection.Idx,
        packages: Collection.Idx,
        region: TokenizedRegion,
    },
    platform: struct {
        // TODO: complete this
        name: Token.Idx,
        requires_rigids: Collection.Idx,
        requires_signatures: TypeAnno.Idx,
        exposes: Collection.Idx,
        packages: Collection.Idx,
        provides: Collection.Idx,
        region: TokenizedRegion,
    },
    hosted: struct {
        exposes: Collection.Idx,
        region: TokenizedRegion,
    },
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub const Idx = enum(u32) { _ };

    pub const AppHeaderRhs = packed struct { num_packages: u10, num_provides: u22 };

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        switch (self) {
            .app => |a| {
                var node = SExpr.init(env.gpa, "app");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                // Provides
                const provides_coll = ast.store.getCollection(a.provides);
                const provides_items = ast.store.exposedItemSlice(.{ .span = provides_coll.span });
                var provides_node = SExpr.init(env.gpa, "provides");
                ast.appendRegionInfoToSexprNode(env, &provides_node, provides_coll.region);
                for (provides_items) |item_idx| {
                    const item = ast.store.getExposedItem(item_idx);
                    var item_node = item.toSExpr(env, ast);
                    provides_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &provides_node);
                // Platform
                const platform = ast.store.getRecordField(a.platform_idx);
                var platform_node = platform.toSExpr(env, ast);
                node.appendNode(env.gpa, &platform_node);
                // Packages
                const packages_coll = ast.store.getCollection(a.packages);
                const packages_items = ast.store.recordFieldSlice(.{ .span = packages_coll.span });
                var packages_node = SExpr.init(env.gpa, "packages");
                ast.appendRegionInfoToSexprNode(env, &packages_node, packages_coll.region);
                for (packages_items) |item_idx| {
                    const item = ast.store.getRecordField(item_idx);
                    var item_node = item.toSExpr(env, ast);
                    packages_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &packages_node);
                return node;
            },
            .module => |module| {
                var node = SExpr.init(env.gpa, "module");
                ast.appendRegionInfoToSexprNode(env, &node, module.region);
                const exposes = ast.store.getCollection(module.exposes);
                var exposes_node = SExpr.init(env.gpa, "exposes");
                ast.appendRegionInfoToSexprNode(env, &exposes_node, exposes.region);
                for (ast.store.exposedItemSlice(.{ .span = exposes.span })) |exposed| {
                    const item = ast.store.getExposedItem(exposed);
                    var item_node = item.toSExpr(env, ast);
                    exposes_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &exposes_node);
                return node;
            },
            .package => |a| {
                var node = SExpr.init(env.gpa, "package");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                // Exposes
                const exposes = ast.store.getCollection(a.exposes);
                var exposes_node = SExpr.init(env.gpa, "exposes");
                ast.appendRegionInfoToSexprNode(env, &exposes_node, exposes.region);
                for (ast.store.exposedItemSlice(.{ .span = exposes.span })) |exposed| {
                    const item = ast.store.getExposedItem(exposed);
                    var item_node = item.toSExpr(env, ast);
                    exposes_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &exposes_node);
                // Packages
                const packages_coll = ast.store.getCollection(a.packages);
                const packages_items = ast.store.recordFieldSlice(.{ .span = packages_coll.span });
                var packages_node = SExpr.init(env.gpa, "packages");
                ast.appendRegionInfoToSexprNode(env, &packages_node, packages_coll.region);
                for (packages_items) |item_idx| {
                    const item = ast.store.getRecordField(item_idx);
                    var item_node = item.toSExpr(env, ast);
                    packages_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &packages_node);
                return node;
            },
            .platform => |a| {
                var node = SExpr.init(env.gpa, "platform");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                // Name
                node.appendStringAttr(env.gpa, "name", ast.resolve(a.name));
                // Requires Rigids
                const rigids = ast.store.getCollection(a.requires_rigids);
                var rigids_node = SExpr.init(env.gpa, "rigids");
                ast.appendRegionInfoToSexprNode(env, &rigids_node, rigids.region);
                for (ast.store.exposedItemSlice(.{ .span = rigids.span })) |exposed| {
                    const item = ast.store.getExposedItem(exposed);
                    var item_node = item.toSExpr(env, ast);
                    rigids_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &rigids_node);
                // Requires Signatures
                const signatures = ast.store.getTypeAnno(a.requires_signatures);
                var signatures_node = signatures.toSExpr(env, ast);
                node.appendNode(env.gpa, &signatures_node);
                // Exposes
                const exposes = ast.store.getCollection(a.exposes);
                var exposes_node = SExpr.init(env.gpa, "exposes");
                ast.appendRegionInfoToSexprNode(env, &exposes_node, exposes.region);
                for (ast.store.exposedItemSlice(.{ .span = exposes.span })) |exposed| {
                    const item = ast.store.getExposedItem(exposed);
                    var item_node = item.toSExpr(env, ast);
                    exposes_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &exposes_node);
                // Packages
                const packages_coll = ast.store.getCollection(a.packages);
                const packages_items = ast.store.recordFieldSlice(.{ .span = packages_coll.span });
                var packages_node = SExpr.init(env.gpa, "packages");
                ast.appendRegionInfoToSexprNode(env, &packages_node, packages_coll.region);
                for (packages_items) |item_idx| {
                    const item = ast.store.getRecordField(item_idx);
                    var item_node = item.toSExpr(env, ast);
                    packages_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &packages_node);
                // Provides
                const provides = ast.store.getCollection(a.provides);
                var provides_node = SExpr.init(env.gpa, "provides");
                ast.appendRegionInfoToSexprNode(env, &provides_node, provides.region);
                for (ast.store.exposedItemSlice(.{ .span = provides.span })) |exposed| {
                    const item = ast.store.getExposedItem(exposed);
                    var item_node = item.toSExpr(env, ast);
                    provides_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &provides_node);
                return node;
            },
            .hosted => |a| {
                var node = SExpr.init(env.gpa, "hosted");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                const exposes = ast.store.getCollection(a.exposes);
                var exposes_node = SExpr.init(env.gpa, "exposes");
                ast.appendRegionInfoToSexprNode(env, &exposes_node, exposes.region);
                for (ast.store.exposedItemSlice(.{ .span = exposes.span })) |exposed| {
                    const item = ast.store.getExposedItem(exposed);
                    var item_node = item.toSExpr(env, ast);
                    exposes_node.appendNode(env.gpa, &item_node);
                }
                node.appendNode(env.gpa, &exposes_node);
                return node;
            },
            .malformed => |a| {
                var node = SExpr.init(env.gpa, "malformed-header");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "tag", @tagName(a.reason));
                return node;
            },
        }
    }
};

/// TODO
pub const ExposedItem = union(enum) {
    lower_ident: struct {
        as: ?Token.Idx,
        ident: Token.Idx,
        region: TokenizedRegion,
    },
    upper_ident: struct {
        as: ?Token.Idx,
        ident: Token.Idx,
        region: TokenizedRegion,
    },
    upper_ident_star: struct {
        ident: Token.Idx,
        region: TokenizedRegion,
    },
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        _ = env.line_starts.items;
        switch (self) {
            .lower_ident => |i| {
                var node = SExpr.init(env.gpa, "exposed-lower-ident");
                const token = ast.tokens.tokens.get(i.ident);
                const text = env.idents.getText(token.extra.interned);
                node.appendStringAttr(env.gpa, "text", text);
                if (i.as) |a| {
                    const as_tok = ast.tokens.tokens.get(a);
                    const as_text = env.idents.getText(as_tok.extra.interned);
                    node.appendStringAttr(env.gpa, "as", as_text);
                }
                return node;
            },
            .upper_ident => |i| {
                var node = SExpr.init(env.gpa, "exposed-upper-ident");
                const token = ast.tokens.tokens.get(i.ident);
                const text = env.idents.getText(token.extra.interned);
                node.appendStringAttr(env.gpa, "text", text);
                if (i.as) |a| {
                    const as_tok = ast.tokens.tokens.get(a);
                    const as_text = env.idents.getText(as_tok.extra.interned);
                    node.appendStringAttr(env.gpa, "as", as_text);
                }
                return node;
            },
            .upper_ident_star => |i| {
                var node = SExpr.init(env.gpa, "exposed-upper-ident-star");
                const token = ast.tokens.tokens.get(i.ident);
                const text = env.idents.getText(token.extra.interned);
                node.appendStringAttr(env.gpa, "text", text);
                return node;
            },
            .malformed => |m| {
                var node = SExpr.init(env.gpa, "exposed-malformed");
                node.appendStringAttr(env.gpa, "reason", @tagName(m.reason));
                ast.appendRegionInfoToSexprNode(env, &node, m.region);
                return node;
            },
        }
    }
};

/// TODO
pub const TypeHeader = struct {
    name: Token.Idx,
    args: TypeAnno.Span,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
};

/// TODO
pub const TypeAnno = union(enum) {
    apply: struct {
        args: TypeAnno.Span,
        region: TokenizedRegion,
    },
    ty_var: struct {
        tok: Token.Idx,
        region: TokenizedRegion,
    },
    underscore: struct {
        region: TokenizedRegion,
    },
    ty: struct {
        token: Token.Idx,
        qualifiers: Token.Span,
        region: TokenizedRegion,
    },
    mod_ty: struct {
        mod_ident: base.Ident.Idx,
        ty_ident: base.Ident.Idx,
        // Region starts with the mod token and ends with the type token.
        region: TokenizedRegion,
    },
    tag_union: struct {
        tags: TypeAnno.Span,
        open_anno: ?TypeAnno.Idx,
        region: TokenizedRegion,
    },
    tuple: struct {
        annos: TypeAnno.Span,
        region: TokenizedRegion,
    },
    record: struct {
        fields: AnnoRecordField.Span,
        region: TokenizedRegion,
    },
    @"fn": struct {
        args: TypeAnno.Span,
        ret: TypeAnno.Idx,
        effectful: bool,
        region: TokenizedRegion,
    },
    parens: struct {
        anno: TypeAnno.Idx,
        region: TokenizedRegion,
    },
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub const TagUnionRhs = packed struct { open: u1, tags_len: u31 };
    pub const TypeAnnoFnRhs = packed struct { effectful: u1, args_len: u31 };

    /// Extract the region from any TypeAnno variant
    pub fn toRegion(self: *const @This()) TokenizedRegion {
        switch (self.*) {
            .apply => |a| return a.region,
            .ty_var => |tv| return tv.region,
            .underscore => |u| return u.region,
            .ty => |t| return t.region,
            .mod_ty => |t| return t.region,
            .tag_union => |tu| return tu.region,
            .tuple => |t| return t.region,
            .record => |r| return r.region,
            .@"fn" => |f| return f.region,
            .parens => |p| return p.region,
            .malformed => |m| return m.region,
        }
    }

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        switch (self) {
            // (apply <ty> [<args>])
            .apply => |a| {
                var node = SExpr.init(env.gpa, "ty-apply");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                for (ast.store.typeAnnoSlice(a.args)) |b| {
                    var child = ast.store.getTypeAnno(b).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }

                return node;
            },
            // (ty_var <var>)
            .ty_var => |a| {
                var node = SExpr.init(env.gpa, "ty-var");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                node.appendStringAttr(env.gpa, "raw", ast.resolve(a.tok));
                return node;
            },
            // (_)
            .underscore => {
                return SExpr.init(env.gpa, "_");
            },
            .ty => |a| {
                var node = SExpr.init(env.gpa, "ty");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                // Resolve the fully qualified name
                const strip_tokens = [_]Token.Tag{.NoSpaceDotUpperIdent};
                const fully_qualified_name = ast.resolveQualifiedName(a.qualifiers, a.token, &strip_tokens);
                node.appendStringAttr(env.gpa, "name", fully_qualified_name);
                return node;
            },
            .mod_ty => |a| {
                var node = SExpr.init(env.gpa, "ty-mod");

                const mod_text = env.idents.getText(a.mod_ident);
                node.appendStringAttr(env.gpa, "module", mod_text);

                const type_text = env.idents.getText(a.ty_ident);
                node.appendStringAttr(env.gpa, "name", type_text);

                return node;
            },
            .tag_union => |a| {
                var node = SExpr.init(env.gpa, "ty-tag-union");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                const tags = ast.store.typeAnnoSlice(a.tags);
                var tags_node = SExpr.init(env.gpa, "tags");
                for (tags) |tag_idx| {
                    const tag = ast.store.getTypeAnno(tag_idx);
                    var tag_node = tag.toSExpr(env, ast);
                    tags_node.appendNode(env.gpa, &tag_node);
                }
                node.appendNode(env.gpa, &tags_node);
                if (a.open_anno) |anno_idx| {
                    const anno = ast.store.getTypeAnno(anno_idx);
                    var anno_node = anno.toSExpr(env, ast);
                    node.appendNode(env.gpa, &anno_node);
                }
                return node;
            },
            // (tuple [<elems>])
            .tuple => |a| {
                var node = SExpr.init(env.gpa, "ty-tuple");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                for (ast.store.typeAnnoSlice(a.annos)) |b| {
                    var child = ast.store.getTypeAnno(b).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }
                return node;
            },
            // (record [<fields>])
            .record => |a| {
                var node = SExpr.init(env.gpa, "ty-record");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                for (ast.store.annoRecordFieldSlice(a.fields)) |f_idx| {
                    const field = ast.store.getAnnoRecordField(f_idx) catch |err| switch (err) {
                        error.MalformedNode => {
                            // Create a malformed-field SExpr node for debugging
                            var malformed_node = SExpr.init(env.gpa, "malformed-field");
                            node.appendNode(env.gpa, &malformed_node);
                            continue;
                        },
                    };
                    var field_node = field.toSExpr(env, ast);
                    node.appendNode(env.gpa, &field_node);
                }
                return node;
            },
            // (fn <ret> [<args>])
            .@"fn" => |a| {
                var node = SExpr.init(env.gpa, "ty-fn");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                // arguments
                for (ast.store.typeAnnoSlice(a.args)) |b| {
                    var child = ast.store.getTypeAnno(b).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }

                // return value
                var ret = ast.store.getTypeAnno(a.ret).toSExpr(env, ast);
                node.appendNode(env.gpa, &ret);

                return node;
            },
            // ignore parens... use inner
            .parens => |a| {
                return ast.store.getTypeAnno(a.anno).toSExpr(env, ast);
            },
            .malformed => |a| {
                var node = SExpr.init(env.gpa, "ty-malformed");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "tag", @tagName(a.reason));
                return node;
            },
        }
    }
};

/// TODO
pub const AnnoRecordField = struct {
    name: Token.Idx,
    ty: TypeAnno.Idx,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var node = SExpr.init(env.gpa, "anno-record-field");
        ast.appendRegionInfoToSexprNode(env, &node, self.region);
        node.appendStringAttr(env.gpa, "name", ast.resolve(self.name));
        const anno = ast.store.getTypeAnno(self.ty);
        var ty_node = anno.toSExpr(env, ast);
        node.appendNode(env.gpa, &ty_node);
        return node;
    }
};

/// The clause of a `where` constraint
///
/// Where clauses specify constraints on type variables that must be satisfied
/// for a function or type to be valid. They enable generic programming with
/// compile-time guarantees about available capabilities.
pub const WhereClause = union(enum) {
    /// Module method constraint specifying a method must exist in the module containing a type.
    ///
    /// This is the most common form of where clause constraint. It specifies that
    /// a type variable must come from a module that provides a specific method.
    ///
    /// Examples:
    /// ```roc
    /// convert : a -> b where module(a).to_b : a -> b
    /// decode : List(U8) -> a where module(a).decode : List(U8) -> a
    /// hash : a -> U64 where module(a).hash : a -> U64
    /// ```
    mod_method: struct {
        var_tok: Token.Idx,
        name_tok: Token.Idx,
        args: Collection.Idx,
        ret_anno: TypeAnno.Idx,
        region: TokenizedRegion,
    },

    /// Module type alias constraint.
    ///
    /// Specifies that a type variable must satisfy the constraints for an alias type.
    /// This is useful to avoid writing out the constraints repeatedly which can be cumbersome and error prone
    ///
    /// Example:
    /// ```roc
    /// Sort(a) : a where  module(a).order(elem, elem) -> [LT, EQ, GT]
    ///
    /// sort : List(elem) -> List(elem) where module(elem).Sort
    /// ```
    mod_alias: struct {
        var_tok: Token.Idx,
        name_tok: Token.Idx,
        region: TokenizedRegion,
    },

    /// Malformed where clause that failed to parse correctly.
    ///
    /// Contains diagnostic information about what went wrong during parsing.
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub fn toSExpr(self: WhereClause, env: *base.ModuleEnv, ast: *AST) SExpr {
        switch (self) {
            .mod_method => |m| {
                var node = SExpr.init(env.gpa, "method");
                ast.appendRegionInfoToSexprNode(env, &node, m.region);

                node.appendStringAttr(env.gpa, "module-of", ast.resolve(m.var_tok));

                // remove preceding dot
                const method_name = ast.resolve(m.name_tok)[1..];
                node.appendStringAttr(env.gpa, "name", method_name);

                var args_node = SExpr.init(env.gpa, "args");
                const args = ast.store.typeAnnoSlice(.{ .span = ast.store.getCollection(m.args).span });
                for (args) |arg| {
                    var arg_child = ast.store.getTypeAnno(arg).toSExpr(env, ast);
                    args_node.appendNode(env.gpa, &arg_child);
                }
                node.appendNode(env.gpa, &args_node);

                var ret_child = ast.store.getTypeAnno(m.ret_anno).toSExpr(env, ast);
                node.appendNode(env.gpa, &ret_child);
                return node;
            },
            .mod_alias => |a| {
                var node = SExpr.init(env.gpa, "alias");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "module-of", ast.resolve(a.var_tok));

                // remove preceding dot
                const alias_name = ast.resolve(a.name_tok)[1..];
                node.appendStringAttr(env.gpa, "name", alias_name);
                return node;
            },
            .malformed => |m| {
                var node = SExpr.init(env.gpa, "malformed");
                ast.appendRegionInfoToSexprNode(env, &node, m.region);
                node.appendStringAttr(env.gpa, "reason", @tagName(m.reason));
                return node;
            },
        }
    }

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };
};

/// Represents an expression.
pub const Expr = union(enum) {
    int: struct {
        token: Token.Idx,
        region: TokenizedRegion,
    },
    frac: struct {
        token: Token.Idx,
        region: TokenizedRegion,
    },
    single_quote: struct {
        token: Token.Idx,
        region: TokenizedRegion,
    },
    string_part: struct { // TODO: this should be more properly represented in its own union enum
        token: Token.Idx,
        region: TokenizedRegion,
    },
    string: struct {
        token: Token.Idx,
        region: TokenizedRegion,
        parts: Expr.Span,
    },
    list: struct {
        items: Expr.Span,
        region: TokenizedRegion,
    },
    tuple: struct {
        items: Expr.Span,
        region: TokenizedRegion,
    },
    record: struct {
        fields: RecordField.Span,
        /// Record extension: { ..person, field: value }
        ext: ?Expr.Idx,
        region: TokenizedRegion,
    },
    tag: struct {
        token: Token.Idx,
        qualifiers: Token.Span,
        region: TokenizedRegion,
    },
    lambda: struct {
        args: Pattern.Span,
        body: Expr.Idx,
        region: TokenizedRegion,
    },
    apply: struct {
        args: Expr.Span,
        @"fn": Expr.Idx,
        region: TokenizedRegion,
    },
    record_updater: struct {
        token: Token.Idx,
        region: TokenizedRegion,
    },
    field_access: BinOp,
    local_dispatch: BinOp,
    bin_op: BinOp,
    suffix_single_question: Unary,
    unary_op: Unary,
    if_then_else: struct {
        condition: Expr.Idx,
        then: Expr.Idx,
        @"else": Expr.Idx,
        region: TokenizedRegion,
    },
    match: struct {
        expr: Expr.Idx,
        branches: MatchBranch.Span,
        region: TokenizedRegion,
    },
    ident: struct {
        token: Token.Idx,
        qualifiers: Token.Span,
        region: TokenizedRegion,
    },
    dbg: struct {
        expr: Expr.Idx,
        region: TokenizedRegion,
    },
    record_builder: struct {
        mapper: Expr.Idx,
        fields: RecordField.Idx,
        region: TokenizedRegion,
    },
    ellipsis: struct {
        region: TokenizedRegion,
    },
    block: Body,
    malformed: struct {
        reason: Diagnostic.Tag,
        region: TokenizedRegion,
    },

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn as_string_part_region(self: @This()) !TokenizedRegion {
        switch (self) {
            .string_part => |part| return part.region,
            else => return error.ExpectedStringPartRegion,
        }
    }

    pub fn to_tokenized_region(self: @This()) TokenizedRegion {
        return switch (self) {
            .ident => |e| e.region,
            .int => |e| e.region,
            .frac => |e| e.region,
            .string => |e| e.region,
            .tag => |e| e.region,
            .list => |e| e.region,
            .record => |e| e.region,
            .tuple => |e| e.region,
            .field_access => |e| e.region,
            .local_dispatch => |e| e.region,
            .lambda => |e| e.region,
            .record_updater => |e| e.region,
            .bin_op => |e| e.region,
            .unary_op => |e| e.region,
            .suffix_single_question => |e| e.region,
            .apply => |e| e.region,
            .if_then_else => |e| e.region,
            .match => |e| e.region,
            .dbg => |e| e.region,
            .block => |e| e.region,
            .record_builder => |e| e.region,
            .ellipsis => |e| e.region,
            .malformed => |e| e.region,
            .string_part => |e| e.region,
            .single_quote => |e| e.region,
        };
    }

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        switch (self) {
            .int => |int| {
                var node = SExpr.init(env.gpa, "e-int");
                ast.appendRegionInfoToSexprNode(env, &node, int.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(int.token));
                return node;
            },
            .string => |str| {
                var node = SExpr.init(env.gpa, "e-string");
                ast.appendRegionInfoToSexprNode(env, &node, str.region);
                for (ast.store.exprSlice(str.parts)) |part_id| {
                    const part_expr = ast.store.getExpr(part_id);
                    var part_sexpr = part_expr.toSExpr(env, ast);
                    node.appendNode(env.gpa, &part_sexpr);
                }
                return node;
            },
            .string_part => |sp| {
                var node = SExpr.init(env.gpa, "e-string-part");
                ast.appendRegionInfoToSexprNode(env, &node, sp.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(sp.token));
                return node;
            },
            // (tag <tag>)
            .tag => |tag| {
                var node = SExpr.init(env.gpa, "e-tag");

                ast.appendRegionInfoToSexprNode(env, &node, tag.region);

                // Resolve the fully qualified name
                const strip_tokens = [_]Token.Tag{.NoSpaceDotUpperIdent};
                const fully_qualified_name = ast.resolveQualifiedName(tag.qualifiers, tag.token, &strip_tokens);
                node.appendStringAttr(env.gpa, "raw", fully_qualified_name);
                return node;
            },
            .block => |block| {
                return block.toSExpr(env, ast);
            },
            .if_then_else => |stmt| {
                var node = SExpr.init(env.gpa, "e-if-then-else");

                ast.appendRegionInfoToSexprNode(env, &node, stmt.region);

                var condition = ast.store.getExpr(stmt.condition).toSExpr(env, ast);
                node.appendNode(env.gpa, &condition);

                var then = ast.store.getExpr(stmt.then).toSExpr(env, ast);
                node.appendNode(env.gpa, &then);

                var else_ = ast.store.getExpr(stmt.@"else").toSExpr(env, ast);

                node.appendNode(env.gpa, &else_);

                return node;
            },
            .ident => |ident| {
                var node = SExpr.init(env.gpa, "e-ident");

                ast.appendRegionInfoToSexprNode(env, &node, ident.region);

                // Resolve the fully qualified name
                const strip_tokens = [_]Token.Tag{ .NoSpaceDotLowerIdent, .NoSpaceDotUpperIdent };
                const fully_qualified_name = ast.resolveQualifiedName(ident.qualifiers, ident.token, &strip_tokens);
                node.appendStringAttr(env.gpa, "raw", fully_qualified_name);
                return node;
            },
            .list => |a| {
                var node = SExpr.init(env.gpa, "e-list");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                for (ast.store.exprSlice(a.items)) |b| {
                    var child = ast.store.getExpr(b).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }
                return node;
            },
            .malformed => |a| {
                var node = SExpr.init(env.gpa, "e-malformed");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "reason", @tagName(a.reason));
                return node;
            },
            .frac => |a| {
                var node = SExpr.init(env.gpa, "e-frac");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                node.appendStringAttr(env.gpa, "raw", ast.resolve(a.token));
                return node;
            },
            .single_quote => |a| {
                var node = SExpr.init(env.gpa, "e-single-quote");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);
                node.appendStringAttr(env.gpa, "raw", ast.resolve(a.token));
                return node;
            },
            .tuple => |a| {
                var node = SExpr.init(env.gpa, "e-tuple");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                for (ast.store.exprSlice(a.items)) |item| {
                    var child = ast.store.getExpr(item).toSExpr(env, ast);
                    node.appendNode(env.gpa, &child);
                }

                return node;
            },
            .record => |a| {
                var node = SExpr.init(env.gpa, "e-record");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                // Add extension if present
                if (a.ext) |ext_idx| {
                    var ext_wrapper = SExpr.init(env.gpa, "ext");
                    var ext_node = ast.store.getExpr(ext_idx).toSExpr(env, ast);
                    ext_wrapper.appendNode(env.gpa, &ext_node);
                    node.appendNode(env.gpa, &ext_wrapper);
                }

                for (ast.store.recordFieldSlice(a.fields)) |field_idx| {
                    const record_field = ast.store.getRecordField(field_idx);
                    var record_field_node = SExpr.init(env.gpa, "field");
                    record_field_node.appendStringAttr(env.gpa, "field", ast.resolve(record_field.name));
                    if (record_field.value != null) {
                        var value_node = ast.store.getExpr(record_field.value.?).toSExpr(env, ast);
                        record_field_node.appendNode(env.gpa, &value_node);
                    }
                    record_field_node.appendBoolAttr(env.gpa, "optional", record_field.optional);
                    node.appendNode(env.gpa, &record_field_node);
                }

                return node;
            },
            .apply => |a| {
                var node = SExpr.init(env.gpa, "e-apply");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var apply_fn = ast.store.getExpr(a.@"fn").toSExpr(env, ast);
                node.appendNode(env.gpa, &apply_fn);

                for (ast.store.exprSlice(a.args)) |arg| {
                    var arg_node = ast.store.getExpr(arg).toSExpr(env, ast);
                    node.appendNode(env.gpa, &arg_node);
                }

                return node;
            },
            .field_access => |a| {
                var node = SExpr.init(env.gpa, "e-field-access");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var left = ast.store.getExpr(a.left).toSExpr(env, ast);
                node.appendNode(env.gpa, &left);

                var right = ast.store.getExpr(a.right).toSExpr(env, ast);
                node.appendNode(env.gpa, &right);
                return node;
            },
            .local_dispatch => |a| {
                var node = SExpr.init(env.gpa, "e-local-dispatch");
                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var left = ast.store.getExpr(a.left).toSExpr(env, ast);
                var right = ast.store.getExpr(a.right).toSExpr(env, ast);
                node.appendNode(env.gpa, &left);
                node.appendNode(env.gpa, &right);
                return node;
            },
            .bin_op => |a| {
                return a.toSExpr(env, ast);
            },
            .lambda => |a| {
                var node = SExpr.init(env.gpa, "e-lambda");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                // arguments
                var args = SExpr.init(env.gpa, "args");
                for (ast.store.patternSlice(a.args)) |arg| {
                    var arg_node = ast.store.getPattern(arg).toSExpr(env, ast);
                    args.appendNode(env.gpa, &arg_node);
                }
                node.appendNode(env.gpa, &args);

                // body
                var body = ast.store.getExpr(a.body).toSExpr(env, ast);
                node.appendNode(env.gpa, &body);

                return node;
            },
            .dbg => |a| {
                var node = SExpr.init(env.gpa, "e-dbg");

                var arg = ast.store.getExpr(a.expr).toSExpr(env, ast);
                node.appendNode(env.gpa, &arg);

                return node;
            },
            .match => |a| {
                var node = SExpr.init(env.gpa, "e-match");

                var expr = ast.store.getExpr(a.expr).toSExpr(env, ast);

                // handle branches
                var branches = SExpr.init(env.gpa, "branches");
                for (ast.store.matchBranchSlice(a.branches)) |branch| {
                    var branch_node = ast.store.getBranch(branch).toSExpr(env, ast);
                    branches.appendNode(env.gpa, &branch_node);
                }

                node.appendNode(env.gpa, &expr);

                node.appendNode(env.gpa, &branches);

                return node;
            },
            .ellipsis => {
                return SExpr.init(env.gpa, "e-ellipsis");
            },
            .suffix_single_question => |a| {
                var node = SExpr.init(env.gpa, "e-question-suffix");

                ast.appendRegionInfoToSexprNode(env, &node, a.region);

                var child = ast.store.getExpr(a.expr).toSExpr(env, ast);
                node.appendNode(env.gpa, &child);
                return node;
            },
            else => {
                std.debug.print("\n\n toSExpr not implement for Expr {}\n\n", .{self});
                @panic("not implemented yet");
            },
        }
    }
};

/// TODO
pub const PatternRecordField = struct {
    name: Token.Idx,
    value: ?Pattern.Idx,
    rest: bool,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };
};

/// TODO
pub const RecordField = struct {
    name: Token.Idx,
    value: ?Expr.Idx,
    optional: bool,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var node = SExpr.init(env.gpa, "record-field");
        ast.appendRegionInfoToSexprNode(env, &node, self.region);
        node.appendStringAttr(env.gpa, "name", ast.resolve(self.name));
        if (self.value) |idx| {
            const value = ast.store.getExpr(idx);
            var value_node = value.toSExpr(env, ast);
            node.appendNode(env.gpa, &value_node);
        }
        return node;
    }
};

/// TODO
pub const IfElse = struct {
    condition: Expr.Idx,
    body: Expr.Idx,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };
};

/// TODO
pub const MatchBranch = struct {
    pattern: Pattern.Idx,
    body: Expr.Idx,
    region: TokenizedRegion,

    pub const Idx = enum(u32) { _ };
    pub const Span = struct { span: base.DataSpan };

    pub fn toSExpr(self: @This(), env: *base.ModuleEnv, ast: *AST) SExpr {
        var node = SExpr.init(env.gpa, "branch");
        ast.appendRegionInfoToSexprNode(env, &node, self.region);
        var pattern = ast.store.getPattern(self.pattern).toSExpr(env, ast);
        node.appendNode(env.gpa, &pattern);
        var body = ast.store.getExpr(self.body).toSExpr(env, ast);
        node.appendNode(env.gpa, &body);
        return node;
    }
};
