//! Document system for structured content rendering.
//!
//! This module provides a flexible document building system that allows creating
//! rich, structured content that can be rendered to different output formats.
//! Documents are composed of elements that can be text, annotations, formatting
//! directives, and structural elements.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Annotations that can be applied to document content for styling and semantics.
pub const Annotation = enum {
    /// Basic emphasis (usually bold or bright)
    emphasized,

    /// Language keywords (if, when, etc.)
    keyword,

    /// Type variables and type names
    type_variable,

    /// Error highlighting
    error_highlight,

    /// Warning highlighting
    warning_highlight,

    /// Suggestion highlighting
    suggestion,

    /// Code blocks and inline code
    code_block,

    /// Inline code elements
    inline_code,

    /// Module and symbol names
    symbol,

    /// File paths and locations
    path,

    /// Numbers and literals
    literal,

    /// Comments
    comment,

    /// Region underlines for source code
    underline,

    /// Dimmed text for less important content
    dimmed,

    /// Returns true if this annotation typically uses color.
    pub fn usesColor(self: Annotation) bool {
        return switch (self) {
            .emphasized, .dimmed => false,
            else => true,
        };
    }

    /// Returns a semantic name for this annotation.
    pub fn semanticName(self: Annotation) []const u8 {
        return switch (self) {
            .emphasized => "emphasis",
            .keyword => "keyword",
            .type_variable => "type",
            .error_highlight => "error",
            .warning_highlight => "warning",
            .suggestion => "suggestion",
            .code_block => "code-block",
            .inline_code => "code",
            .symbol => "symbol",
            .path => "path",
            .literal => "literal",
            .comment => "comment",
            .underline => "underline",
            .dimmed => "dim",
        };
    }
};

/// Individual elements that make up a document.
pub const DocumentElement = union(enum) {
    /// Plain text content
    text: []const u8,

    /// Text with annotation for styling
    annotated: struct {
        content: []const u8,
        annotation: Annotation,
    },

    /// Line break
    line_break,

    /// Horizontal indentation
    indent: u32,

    /// Horizontal spacing
    space: u32,

    /// Horizontal rule/separator
    horizontal_rule: ?u32, // Optional width, null means full width

    /// Start of an annotation region
    annotation_start: Annotation,

    /// End of an annotation region
    annotation_end,

    /// Raw content that should not be processed
    raw: []const u8,

    /// Get the text content if this is a text element, null otherwise.
    pub fn getText(self: DocumentElement) ?[]const u8 {
        return switch (self) {
            .text => |t| t,
            .annotated => |a| a.content,
            .raw => |r| r,
            else => null,
        };
    }

    /// Returns true if this element represents actual content.
    pub fn hasContent(self: DocumentElement) bool {
        return switch (self) {
            .text, .annotated, .raw => true,
            else => false,
        };
    }
};

/// A document composed of structured elements that can be rendered.
pub const Document = struct {
    elements: std.ArrayList(DocumentElement),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Document {
        return Document{
            .elements = std.ArrayList(DocumentElement).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Document) void {
        self.elements.deinit();
    }

    /// Add plain text to the document.
    pub fn addText(self: *Document, text: []const u8) !void {
        if (text.len == 0) return;
        try self.elements.append(.{ .text = text });
    }

    /// Add annotated text to the document.
    pub fn addAnnotated(self: *Document, text: []const u8, annotation: Annotation) !void {
        if (text.len == 0) return;
        try self.elements.append(.{ .annotated = .{ .content = text, .annotation = annotation } });
    }

    /// Add a line break to the document.
    pub fn addLineBreak(self: *Document) !void {
        try self.elements.append(.line_break);
    }

    /// Add indentation to the document.
    pub fn addIndent(self: *Document, levels: u32) !void {
        if (levels == 0) return;
        try self.elements.append(.{ .indent = levels });
    }

    /// Add horizontal spacing to the document.
    pub fn addSpace(self: *Document, count: u32) !void {
        if (count == 0) return;
        try self.elements.append(.{ .space = count });
    }

    /// Add a horizontal rule separator.
    pub fn addHorizontalRule(self: *Document, width: ?u32) !void {
        try self.elements.append(.{ .horizontal_rule = width });
    }

    /// Start an annotation region.
    pub fn startAnnotation(self: *Document, annotation: Annotation) !void {
        try self.elements.append(.{ .annotation_start = annotation });
    }

    /// End the current annotation region.
    pub fn endAnnotation(self: *Document) !void {
        try self.elements.append(.annotation_end);
    }

    /// Add raw content that should not be processed.
    pub fn addRaw(self: *Document, content: []const u8) !void {
        if (content.len == 0) return;
        try self.elements.append(.{ .raw = content });
    }

    /// Convenience method to add annotated text with automatic annotation boundaries.
    pub fn addAnnotatedText(self: *Document, text: []const u8, annotation: Annotation) !void {
        try self.startAnnotation(annotation);
        try self.addText(text);
        try self.endAnnotation();
    }

    /// Add a formatted string to the document.
    pub fn addFormattedText(self: *Document, comptime fmt: []const u8, args: anytype) !void {
        var buf: [1024]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, fmt, args);
        try self.addText(text);
    }

    /// Add multiple line breaks.
    pub fn addLineBreaks(self: *Document, count: u32) !void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try self.addLineBreak();
        }
    }

    /// Add a code block with proper formatting.
    pub fn addCodeBlock(self: *Document, code: []const u8) !void {
        try self.startAnnotation(.code_block);

        // Split code into lines and add each with proper indentation
        var lines = std.mem.split(u8, code, "\n");
        var first = true;
        while (lines.next()) |line| {
            if (!first) {
                try self.addLineBreak();
            }
            first = false;

            if (line.len > 0) {
                try self.addIndent(1);
                try self.addText(line);
            }
        }

        try self.endAnnotation();
    }

    /// Add an inline code element.
    pub fn addInlineCode(self: *Document, code: []const u8) !void {
        try self.addAnnotated(code, .inline_code);
    }

    /// Add a keyword with proper styling.
    pub fn addKeyword(self: *Document, keyword: []const u8) !void {
        try self.addAnnotated(keyword, .keyword);
    }

    /// Add a type name with proper styling.
    pub fn addType(self: *Document, type_name: []const u8) !void {
        try self.addAnnotated(type_name, .type_variable);
    }

    /// Add an error message with proper styling.
    pub fn addError(self: *Document, message: []const u8) !void {
        try self.addAnnotated(message, .error_highlight);
    }

    /// Add a warning message with proper styling.
    pub fn addWarning(self: *Document, message: []const u8) !void {
        try self.addAnnotated(message, .warning_highlight);
    }

    /// Add a suggestion with proper styling.
    pub fn addSuggestion(self: *Document, suggestion: []const u8) !void {
        try self.addAnnotated(suggestion, .suggestion);
    }

    /// Get the total number of elements in the document.
    pub fn elementCount(self: *const Document) usize {
        return self.elements.items.len;
    }

    /// Check if the document is empty.
    pub fn isEmpty(self: *const Document) bool {
        return self.elements.items.len == 0;
    }

    /// Get an element by index.
    pub fn getElement(self: *const Document, index: usize) ?DocumentElement {
        if (index >= self.elements.items.len) return null;
        return self.elements.items[index];
    }

    /// Clear all elements from the document.
    pub fn clear(self: *Document) void {
        self.elements.clearRetainingCapacity();
    }

    /// Render the document using a renderer.
    pub fn render(self: *const Document, renderer: anytype) !void {
        for (self.elements.items) |element| {
            try renderElement(element, renderer);
        }
    }

    /// Helper function to render a single element.
    fn renderElement(element: DocumentElement, renderer: anytype) !void {
        switch (element) {
            .text => |text| try renderer.writeText(text),
            .annotated => |annotated| {
                try renderer.pushAnnotation(annotated.annotation);
                try renderer.writeText(annotated.content);
                try renderer.popAnnotation();
            },
            .line_break => try renderer.writeLineBreak(),
            .indent => |levels| try renderer.writeIndent(levels),
            .space => |count| try renderer.writeSpace(count),
            .horizontal_rule => |width| try renderer.writeHorizontalRule(width),
            .annotation_start => |annotation| try renderer.pushAnnotation(annotation),
            .annotation_end => try renderer.popAnnotation(),
            .raw => |content| try renderer.writeRaw(content),
        }
    }
};

/// A document builder that provides a fluent interface for creating documents.
pub const DocumentBuilder = struct {
    document: Document,

    pub fn init(allocator: Allocator) DocumentBuilder {
        return DocumentBuilder{
            .document = Document.init(allocator),
        };
    }

    pub fn deinit(self: *DocumentBuilder) void {
        self.document.deinit();
    }

    pub fn text(self: *DocumentBuilder, content: []const u8) *DocumentBuilder {
        self.document.addText(content) catch @panic("OOM");
        return self;
    }

    pub fn annotated(self: *DocumentBuilder, content: []const u8, annotation: Annotation) *DocumentBuilder {
        self.document.addAnnotated(content, annotation) catch @panic("OOM");
        return self;
    }

    pub fn lineBreak(self: *DocumentBuilder) *DocumentBuilder {
        self.document.addLineBreak() catch @panic("OOM");
        return self;
    }

    pub fn indent(self: *DocumentBuilder, levels: u32) *DocumentBuilder {
        self.document.addIndent(levels) catch @panic("OOM");
        return self;
    }

    pub fn space(self: *DocumentBuilder, count: u32) *DocumentBuilder {
        self.document.addSpace(count) catch @panic("OOM");
        return self;
    }

    pub fn rule(self: *DocumentBuilder, width: ?u32) *DocumentBuilder {
        self.document.addHorizontalRule(width) catch @panic("OOM");
        return self;
    }

    pub fn keyword(self: *DocumentBuilder, kw: []const u8) *DocumentBuilder {
        self.document.addKeyword(kw) catch @panic("OOM");
        return self;
    }

    pub fn typeText(self: *DocumentBuilder, type_name: []const u8) *DocumentBuilder {
        self.document.addType(type_name) catch @panic("OOM");
        return self;
    }

    pub fn error(self: *DocumentBuilder, message: []const u8) *DocumentBuilder {
        self.document.addError(message) catch @panic("OOM");
        return self;
    }

    pub fn warning(self: *DocumentBuilder, message: []const u8) *DocumentBuilder {
        self.document.addWarning(message) catch @panic("OOM");
        return self;
    }

    pub fn suggestion(self: *DocumentBuilder, sug: []const u8) *DocumentBuilder {
        self.document.addSuggestion(sug) catch @panic("OOM");
        return self;
    }

    pub fn build(self: *DocumentBuilder) Document {
        return self.document;
    }
};

// Tests
const testing = std.testing;

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
        .error("Type mismatch")
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
