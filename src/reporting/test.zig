//! Test entry point for the reporting module.
//!
//! This file serves as the main test entry point for all reporting-related
//! functionality including rendering, document generation, styling, and reports.

const std = @import("std");
const testing = std.testing;
const document = @import("document.zig");

const Allocator = std.mem.Allocator;
const Document = document.Document;
const DocumentBuilder = document.DocumentBuilder;
const Annotation = document.Annotation;
const DocumentElement = document.DocumentElement;
const SourceRegion = document.SourceRegion;

test {
    // Reference all declarations in reporting modules
    testing.refAllDeclsRecursive(@import("renderer.zig"));
    testing.refAllDeclsRecursive(@import("report.zig"));
    testing.refAllDeclsRecursive(@import("document.zig"));
    testing.refAllDeclsRecursive(@import("style.zig"));
    testing.refAllDeclsRecursive(@import("severity.zig"));
    testing.refAllDeclsRecursive(@import("config.zig"));
    testing.refAllDeclsRecursive(@import("utf8_tests.zig"));
}

// Tests -- these are temporary I think, at some point we will implement these in the actual Canonicalization
// and have snapshot tests that cover these.

test "Document basic operations" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addText("Hello");
    try doc.addSpace(1);
    try doc.addAnnotated("world", .emphasized);
    try doc.addLineBreak();

    try testing.expectEqual(@as(usize, 4), doc.elementCount());
    try testing.expect(!doc.isEmpty());

    // Test element access
    const first = doc.getElement(0).?;
    try testing.expectEqualStrings("Hello", first.getText().?);
}

test "DocumentBuilder fluent interface" {
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
}

test "Annotation semantic names" {
    try testing.expectEqualStrings("error", Annotation.error_highlight.semanticName());
    try testing.expectEqualStrings("keyword", Annotation.keyword.semanticName());
    try testing.expectEqualStrings("type", Annotation.type_variable.semanticName());
}

test "Document code blocks" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addCodeBlock("fn main() {\n    println!(\"Hello\");\n}");

    try testing.expect(doc.elementCount() > 0);
}

test "Document semantic elements" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addQualifiedSymbol("Module.symbol");
    try doc.addUnqualifiedSymbol("symbol");
    try doc.addModuleName("Module");
    try doc.addRecordField("field");
    try doc.addTagName("Tag");
    try doc.addBinaryOperator("+");

    try testing.expectEqual(@as(usize, 6), doc.elementCount());
}

test "Document reflowing text" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addReflowingText("This is a long line of text that should be reflowed automatically when rendered.");

    try testing.expectEqual(@as(usize, 1), doc.elementCount());
}

test "Document vertical stack and horizontal concat" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    const stack_elements = [_]DocumentElement{
        .{ .text = "Line 1" },
        .{ .text = "Line 2" },
    };

    const concat_elements = [_]DocumentElement{
        .{ .text = "Part 1" },
        .{ .text = "Part 2" },
    };

    try doc.addVerticalStack(&stack_elements);
    try doc.addHorizontalConcat(&concat_elements);

    try testing.expectEqual(@as(usize, 2), doc.elementCount());
}

test "Document source code regions" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try doc.addSourceRegion("let x = 42;", 1, 1, 1, 11, .error_highlight, "test.roc");

    const regions = [_]SourceRegion{
        .{ .start_line = 1, .start_column = 1, .end_line = 1, .end_column = 5, .annotation = .keyword },
        .{ .start_line = 1, .start_column = 9, .end_line = 1, .end_column = 11, .annotation = .literal },
    };

    try doc.addSourceMultiRegion("let x = 42;", &regions, "test.roc");

    try testing.expectEqual(@as(usize, 2), doc.elementCount());
}

test "New annotation semantic names" {
    try testing.expectEqualStrings("symbol-qualified", Annotation.symbol_qualified.semanticName());
    try testing.expectEqualStrings("symbol-unqualified", Annotation.symbol_unqualified.semanticName());
    try testing.expectEqualStrings("module", Annotation.module_name.semanticName());
    try testing.expectEqualStrings("record-field", Annotation.record_field.semanticName());
    try testing.expectEqualStrings("tag", Annotation.tag_name.semanticName());
    try testing.expectEqualStrings("operator", Annotation.binary_operator.semanticName());
    try testing.expectEqualStrings("reflow", Annotation.reflowing_text.semanticName());
}

test "DocumentBuilder with new features" {
    var builder = DocumentBuilder.init(testing.allocator);
    defer builder.deinit();

    var doc = builder
        .text("Error in ")
        .qualifiedSymbol("Module.function")
        .text(" at ")
        .recordField("field")
        .lineBreak()
        .reflow("This is a long error message that should be reflowed when displayed to the user.")
        .build();

    try testing.expect(doc.elementCount() > 0);
}

// Helper functions for building canonicalize error reports

fn buildSyntaxProblemReport(allocator: Allocator) !Document {
    var doc = Document.init(allocator);
    try doc.addText("Using more than one ");
    try doc.addBinaryOperator("+");
    try doc.addReflowingText(" like this requires parentheses, to clarify how things should be grouped.");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 10, 1, 20, .error_highlight, "example.roc");
    return doc;
}

fn buildNamingProblemReport(allocator: Allocator) !Document {
    var doc = Document.init(allocator);
    try doc.addReflowingText("This annotation does not match the definition immediately following it:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 1, 2, 10, .error_highlight, "example.roc");
    try doc.addReflowingText("Is it a typo? If not, put either a newline or comment between them.");
    return doc;
}

fn buildUnrecognizedNameReport(allocator: Allocator, name: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addText("Nothing is named `");
    try doc.addText(name);
    try doc.addText("` in this scope.");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 5, 1, 8, .error_highlight, "example.roc");
    try doc.addText("Is there an ");
    try doc.addKeyword("import");
    try doc.addText(" or ");
    try doc.addKeyword("exposing");
    try doc.addReflowingText(" missing up-top");
    return doc;
}

fn buildUnusedDefReport(allocator: Allocator, symbol: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addUnqualifiedSymbol(symbol);
    try doc.addReflowingText(" is not used anywhere in your code.");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 1, 1, 10, .warning_highlight, "example.roc");
    try doc.addText("If you didn't intend on using ");
    try doc.addUnqualifiedSymbol(symbol);
    try doc.addReflowingText(" then remove it so future readers of your code don't wonder why it is there.");
    return doc;
}

fn buildUnusedImportReport(allocator: Allocator, symbol: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addQualifiedSymbol(symbol);
    try doc.addReflowingText(" is not used in this module.");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 8, 1, 20, .warning_highlight, "example.roc");
    try doc.addText("Since ");
    try doc.addQualifiedSymbol(symbol);
    try doc.addReflowingText(" isn't used, you don't need to import it.");
    return doc;
}

fn buildImportNameConflictReport(allocator: Allocator, name: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addModuleName("Json");
    try doc.addText(" was imported as ");
    try doc.addModuleName(name);
    try doc.addText(":");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 1, 1, 20, .error_highlight, "example.roc");
    try doc.addText("but ");
    try doc.addModuleName(name);
    try doc.addReflowingText(" is already used by a previous import:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 2, 1, 2, 15, .error_highlight, "example.roc");
    try doc.addReflowingText("Using the same name for both can make it hard to tell which module you are referring to.");
    try doc.addLineBreak();
    try doc.addReflowingText("Make sure each import has a unique alias or none at all.");
    return doc;
}

fn buildUnusedArgReport(allocator: Allocator, closure_symbol: []const u8, argument_symbol: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addUnqualifiedSymbol(closure_symbol);
    try doc.addText(" doesn't use ");
    try doc.addUnqualifiedSymbol(argument_symbol);
    try doc.addText(".");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 10, 1, 15, .warning_highlight, "example.roc");
    try doc.addText("If you don't need ");
    try doc.addUnqualifiedSymbol(argument_symbol);
    try doc.addReflowingText(", then you can just remove it. However, if you really do need ");
    try doc.addUnqualifiedSymbol(argument_symbol);
    try doc.addText(" as an argument of ");
    try doc.addUnqualifiedSymbol(closure_symbol);
    try doc.addText(", prefix it with an underscore, like this: \"_");
    try doc.addUnqualifiedSymbol(argument_symbol);
    try doc.addReflowingText("\". Adding an underscore at the start of a variable name is a way of saying that the variable is not used.");
    return doc;
}

fn buildMissingDefinitionReport(allocator: Allocator, symbol: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addUnqualifiedSymbol(symbol);
    try doc.addReflowingText(" is listed as exposed, but it isn't defined in this module.");
    try doc.addLineBreak();
    try doc.addText("You can fix this by adding a definition for ");
    try doc.addUnqualifiedSymbol(symbol);
    try doc.addText(", or by removing it from ");
    try doc.addKeyword("exposes");
    try doc.addText(".");
    return doc;
}

fn buildDuplicateFieldNameReport(allocator: Allocator, field_name: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addText("This record defines the ");
    try doc.addRecordField(field_name);
    try doc.addReflowingText(" field twice!");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 1, 3, 1, .error_highlight, "example.roc");
    try doc.addReflowingText("In the rest of the program, I will only use the latter definition:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 2, 5, 2, 15, .suggestion, "example.roc");
    try doc.addText("For clarity, remove the previous ");
    try doc.addRecordField(field_name);
    try doc.addReflowingText(" definitions from this record.");
    return doc;
}

fn buildDuplicateTagNameReport(allocator: Allocator, tag_name: []const u8) !Document {
    var doc = Document.init(allocator);
    try doc.addText("This tag union type defines the ");
    try doc.addTagName(tag_name);
    try doc.addReflowingText(" tag twice!");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 1, 3, 1, .error_highlight, "example.roc");
    try doc.addReflowingText("In the rest of the program, I will only use the latter definition:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 2, 5, 2, 15, .suggestion, "example.roc");
    try doc.addText("For clarity, remove the previous ");
    try doc.addTagName(tag_name);
    try doc.addReflowingText(" definitions from this tag union type.");
    return doc;
}

fn buildMissingExclamationReport(allocator: Allocator) !Document {
    var doc = Document.init(allocator);
    try doc.addReflowingText("The type of this record field is an effectful function, but its name does not indicate so:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 5, 1, 20, .error_highlight, "example.roc");
    try doc.addReflowingText("Add an exclamation mark at the end, like:");
    try doc.addLineBreak();
    try doc.addIndent(4);
    try doc.addInlineCode("{ read_file!: Str => Str }");
    try doc.addLineBreak();
    try doc.addReflowingText("This will help readers identify it as a source of effects.");
    return doc;
}

fn buildUnnecessaryExclamationReport(allocator: Allocator) !Document {
    var doc = Document.init(allocator);
    try doc.addReflowingText("The type of this record field is a pure function, but its name suggests otherwise:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 5, 1, 20, .error_highlight, "example.roc");
    try doc.addReflowingText("The exclamation mark at the end is reserved for effectful functions.");
    try doc.addLineBreak();
    try doc.addText("Did you mean to use ");
    try doc.addKeyword("=>");
    try doc.addText(" instead of ");
    try doc.addKeyword("->");
    try doc.addText("?");
    return doc;
}

fn buildEmptyTupleTypeReport(allocator: Allocator) !Document {
    var doc = Document.init(allocator);
    try doc.addReflowingText("This tuple type is empty:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 10, 1, 12, .error_highlight, "example.roc");
    try doc.addReflowingText("Empty tuples are not allowed in Roc.");
    return doc;
}

fn buildUnboundTypeVarsInAsReport(allocator: Allocator) !Document {
    var doc = Document.init(allocator);
    try doc.addReflowingText("This type annotation has unbound type variables:");
    try doc.addLineBreak();
    try doc.addSourceRegion("example.roc", 1, 10, 1, 20, .error_highlight, "example.roc");
    try doc.addReflowingText("Type variables must be bound in the same scope as the type annotation.");
    return doc;
}

// Test cases for canonicalize error reports

test "SYNTAX_PROBLEM report" {
    var doc = try buildSyntaxProblemReport(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "NAMING_PROBLEM report" {
    var doc = try buildNamingProblemReport(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "UNRECOGNIZED_NAME report" {
    var doc = try buildUnrecognizedNameReport(testing.allocator, "foo");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "UNUSED_DEF report" {
    var doc = try buildUnusedDefReport(testing.allocator, "unusedFunction");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "UNUSED_IMPORT report" {
    var doc = try buildUnusedImportReport(testing.allocator, "List.map");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "IMPORT_NAME_CONFLICT report" {
    var doc = try buildImportNameConflictReport(testing.allocator, "Json");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "UNUSED_ARG report" {
    var doc = try buildUnusedArgReport(testing.allocator, "myFunction", "unusedArg");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "MISSING_DEFINITION report" {
    var doc = try buildMissingDefinitionReport(testing.allocator, "missingFunction");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "DUPLICATE_FIELD_NAME report" {
    var doc = try buildDuplicateFieldNameReport(testing.allocator, "name");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "DUPLICATE_TAG_NAME report" {
    var doc = try buildDuplicateTagNameReport(testing.allocator, "Ok");
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "MISSING_EXCLAMATION report" {
    var doc = try buildMissingExclamationReport(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "UNNECESSARY_EXCLAMATION report" {
    var doc = try buildUnnecessaryExclamationReport(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "EMPTY_TUPLE_TYPE report" {
    var doc = try buildEmptyTupleTypeReport(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}

test "UNBOUND_TYPE_VARS_IN_AS report" {
    var doc = try buildUnboundTypeVarsInAsReport(testing.allocator);
    defer doc.deinit();

    try testing.expect(doc.elementCount() > 0);
    try testing.expect(!doc.isEmpty());
}
