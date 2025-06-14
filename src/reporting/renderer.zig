//! Rendering system for multiple output targets.
//!
//! This module provides a flexible rendering system that can output formatted
//! content to different targets including terminals, plain text, HTML, and
//! language server protocol formats.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Annotation = @import("document.zig").Annotation;
const ColorPalette = @import("style.zig").ColorPalette;
const ColorUtils = @import("style.zig").ColorUtils;

/// Supported rendering targets.
pub const RenderTarget = enum {
    /// Color terminal with ANSI escape codes
    color_terminal,
    /// Plain text without any formatting
    plain_text,
    /// HTML with CSS styling
    html,
    /// Language Server Protocol format
    language_server,
};

/// Base renderer interface using Zig's function pointer approach.
pub const Renderer = struct {
    const VTable = struct {
        writeText: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
        writeLineBreak: *const fn (ctx: *anyopaque) anyerror!void,
        writeIndent: *const fn (ctx: *anyopaque, levels: u32) anyerror!void,
        writeSpace: *const fn (ctx: *anyopaque, count: u32) anyerror!void,
        writeHorizontalRule: *const fn (ctx: *anyopaque, width: ?u32) anyerror!void,
        pushAnnotation: *const fn (ctx: *anyopaque, annotation: Annotation) anyerror!void,
        popAnnotation: *const fn (ctx: *anyopaque) anyerror!void,
        writeRaw: *const fn (ctx: *anyopaque, content: []const u8) anyerror!void,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn writeText(self: *Renderer, text: []const u8) !void {
        return self.vtable.writeText(self.ptr, text);
    }

    pub fn writeLineBreak(self: *Renderer) !void {
        return self.vtable.writeLineBreak(self.ptr);
    }

    pub fn writeIndent(self: *Renderer, levels: u32) !void {
        return self.vtable.writeIndent(self.ptr, levels);
    }

    pub fn writeSpace(self: *Renderer, count: u32) !void {
        return self.vtable.writeSpace(self.ptr, count);
    }

    pub fn writeHorizontalRule(self: *Renderer, width: ?u32) !void {
        return self.vtable.writeHorizontalRule(self.ptr, width);
    }

    pub fn pushAnnotation(self: *Renderer, annotation: Annotation) !void {
        return self.vtable.pushAnnotation(self.ptr, annotation);
    }

    pub fn popAnnotation(self: *Renderer) !void {
        return self.vtable.popAnnotation(self.ptr);
    }

    pub fn writeRaw(self: *Renderer, content: []const u8) !void {
        return self.vtable.writeRaw(self.ptr, content);
    }
};

/// Terminal renderer with ANSI color support.
pub const TerminalRenderer = struct {
    writer: std.io.AnyWriter,
    palette: ColorPalette,
    annotation_stack: std.ArrayList(Annotation),
    indent_string: []const u8,

    const DEFAULT_INDENT = "    "; // 4 spaces
    const HORIZONTAL_RULE_CHAR = "─";
    const DEFAULT_RULE_WIDTH = 80;

    pub fn init(allocator: Allocator, writer: std.io.AnyWriter, palette: ColorPalette) TerminalRenderer {
        return TerminalRenderer{
            .writer = writer,
            .palette = palette,
            .annotation_stack = std.ArrayList(Annotation).init(allocator),
            .indent_string = DEFAULT_INDENT,
        };
    }

    pub fn deinit(self: *TerminalRenderer) void {
        self.annotation_stack.deinit();
    }

    pub fn renderer(self: *TerminalRenderer) Renderer {
        return Renderer{
            .ptr = self,
            .vtable = &.{
                .writeText = writeText,
                .writeLineBreak = writeLineBreak,
                .writeIndent = writeIndent,
                .writeSpace = writeSpace,
                .writeHorizontalRule = writeHorizontalRule,
                .pushAnnotation = pushAnnotation,
                .popAnnotation = popAnnotation,
                .writeRaw = writeRaw,
            },
        };
    }

    fn writeText(ctx: *anyopaque, text: []const u8) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(text);
    }

    fn writeLineBreak(ctx: *anyopaque) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll("\n");
    }

    fn writeIndent(ctx: *anyopaque, levels: u32) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < levels) : (i += 1) {
            try self.writer.writeAll(self.indent_string);
        }
    }

    fn writeSpace(ctx: *anyopaque, count: u32) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try self.writer.writeAll(" ");
        }
    }

    fn writeHorizontalRule(ctx: *anyopaque, width: ?u32) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        const rule_width = width orelse DEFAULT_RULE_WIDTH;

        var i: u32 = 0;
        while (i < rule_width) : (i += 1) {
            try self.writer.writeAll(HORIZONTAL_RULE_CHAR);
        }
    }

    fn pushAnnotation(ctx: *anyopaque, annotation: Annotation) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        try self.annotation_stack.append(annotation);

        const color = self.palette.colorForAnnotation(annotation);
        try self.writer.writeAll(color);
    }

    fn popAnnotation(ctx: *anyopaque) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        if (self.annotation_stack.items.len > 0) {
            _ = self.annotation_stack.pop();
        }
        try self.writer.writeAll(self.palette.reset);

        // Restore previous annotation if there is one
        if (self.annotation_stack.items.len > 0) {
            const current = self.annotation_stack.items[self.annotation_stack.items.len - 1];
            const color = self.palette.colorForAnnotation(current);
            try self.writer.writeAll(color);
        }
    }

    fn writeRaw(ctx: *anyopaque, content: []const u8) !void {
        const self: *TerminalRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(content);
    }
};

/// Plain text renderer without any formatting.
pub const PlainTextRenderer = struct {
    writer: std.io.AnyWriter,
    annotation_stack: std.ArrayList(Annotation),
    indent_string: []const u8,

    const DEFAULT_INDENT = "    ";
    const HORIZONTAL_RULE_CHAR = "-";
    const DEFAULT_RULE_WIDTH = 80;

    pub fn init(allocator: Allocator, writer: std.io.AnyWriter) PlainTextRenderer {
        return PlainTextRenderer{
            .writer = writer,
            .annotation_stack = std.ArrayList(Annotation).init(allocator),
            .indent_string = DEFAULT_INDENT,
        };
    }

    pub fn deinit(self: *PlainTextRenderer) void {
        self.annotation_stack.deinit();
    }

    pub fn renderer(self: *PlainTextRenderer) Renderer {
        return Renderer{
            .ptr = self,
            .vtable = &.{
                .writeText = writeText,
                .writeLineBreak = writeLineBreak,
                .writeIndent = writeIndent,
                .writeSpace = writeSpace,
                .writeHorizontalRule = writeHorizontalRule,
                .pushAnnotation = pushAnnotation,
                .popAnnotation = popAnnotation,
                .writeRaw = writeRaw,
            },
        };
    }

    fn writeText(ctx: *anyopaque, text: []const u8) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(text);
    }

    fn writeLineBreak(ctx: *anyopaque) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll("\n");
    }

    fn writeIndent(ctx: *anyopaque, levels: u32) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < levels) : (i += 1) {
            try self.writer.writeAll(self.indent_string);
        }
    }

    fn writeSpace(ctx: *anyopaque, count: u32) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try self.writer.writeAll(" ");
        }
    }

    fn writeHorizontalRule(ctx: *anyopaque, width: ?u32) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        const rule_width = width orelse DEFAULT_RULE_WIDTH;

        var i: u32 = 0;
        while (i < rule_width) : (i += 1) {
            try self.writer.writeAll(HORIZONTAL_RULE_CHAR);
        }
    }

    fn pushAnnotation(ctx: *anyopaque, annotation: Annotation) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        try self.annotation_stack.append(annotation);
        // Plain text renderer ignores annotations
    }

    fn popAnnotation(ctx: *anyopaque) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        if (self.annotation_stack.items.len > 0) {
            _ = self.annotation_stack.pop();
        }
        // Plain text renderer ignores annotations
    }

    fn writeRaw(ctx: *anyopaque, content: []const u8) !void {
        const self: *PlainTextRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(content);
    }
};

/// HTML renderer with CSS styling.
pub const HtmlRenderer = struct {
    writer: std.io.AnyWriter,
    annotation_stack: std.ArrayList(Annotation),
    indent_string: []const u8,
    in_pre_block: bool,

    const DEFAULT_INDENT = "    ";
    const DEFAULT_RULE_WIDTH = 80;

    pub fn init(allocator: Allocator, writer: std.io.AnyWriter) HtmlRenderer {
        return HtmlRenderer{
            .writer = writer,
            .annotation_stack = std.ArrayList(Annotation).init(allocator),
            .indent_string = DEFAULT_INDENT,
            .in_pre_block = false,
        };
    }

    pub fn deinit(self: *HtmlRenderer) void {
        self.annotation_stack.deinit();
    }

    pub fn renderer(self: *HtmlRenderer) Renderer {
        return Renderer{
            .ptr = self,
            .vtable = &.{
                .writeText = writeText,
                .writeLineBreak = writeLineBreak,
                .writeIndent = writeIndent,
                .writeSpace = writeSpace,
                .writeHorizontalRule = writeHorizontalRule,
                .pushAnnotation = pushAnnotation,
                .popAnnotation = popAnnotation,
                .writeRaw = writeRaw,
            },
        };
    }

    fn writeText(ctx: *anyopaque, text: []const u8) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        try self.writeEscapedHtml(text);
    }

    fn writeLineBreak(ctx: *anyopaque) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        if (self.in_pre_block) {
            try self.writer.writeAll("\n");
        } else {
            try self.writer.writeAll("<br>\n");
        }
    }

    fn writeIndent(ctx: *anyopaque, levels: u32) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < levels) : (i += 1) {
            try self.writer.writeAll(self.indent_string);
        }
    }

    fn writeSpace(ctx: *anyopaque, count: u32) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try self.writer.writeAll(" ");
        }
    }

    fn writeHorizontalRule(ctx: *anyopaque, width: ?u32) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        _ = width; // HTML hr doesn't need explicit width
        try self.writer.writeAll("<hr>");
    }

    fn pushAnnotation(ctx: *anyopaque, annotation: Annotation) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        try self.annotation_stack.append(annotation);

        const class_name = annotation.semanticName();
        try self.writer.print("<span class=\"roc-{s}\">", .{class_name});

        // Special case for code blocks
        if (annotation == .code_block) {
            try self.writer.writeAll("<pre>");
            self.in_pre_block = true;
        }
    }

    fn popAnnotation(ctx: *anyopaque) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        if (self.annotation_stack.items.len > 0) {
            const annotation = self.annotation_stack.pop();

            // Special case for code blocks
            if (annotation == .code_block) {
                try self.writer.writeAll("</pre>");
                self.in_pre_block = false;
            }

            try self.writer.writeAll("</span>");
        }
    }

    fn writeRaw(ctx: *anyopaque, content: []const u8) !void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(content);
    }

    fn writeEscapedHtml(self: *HtmlRenderer, text: []const u8) !void {
        for (text) |char| {
            switch (char) {
                '<' => try self.writer.writeAll("&lt;"),
                '>' => try self.writer.writeAll("&gt;"),
                '&' => try self.writer.writeAll("&amp;"),
                '"' => try self.writer.writeAll("&quot;"),
                '\'' => try self.writer.writeAll("&#39;"),
                else => try self.writer.writeByte(char),
            }
        }
    }
};

/// Language Server Protocol renderer.
pub const LspRenderer = struct {
    writer: std.io.AnyWriter,
    annotation_stack: std.ArrayList(Annotation),
    current_line: u32,
    current_column: u32,

    pub fn init(allocator: Allocator, writer: std.io.AnyWriter) LspRenderer {
        return LspRenderer{
            .writer = writer,
            .annotation_stack = std.ArrayList(Annotation).init(allocator),
            .current_line = 0,
            .current_column = 0,
        };
    }

    pub fn deinit(self: *LspRenderer) void {
        self.annotation_stack.deinit();
    }

    pub fn renderer(self: *LspRenderer) Renderer {
        return Renderer{
            .ptr = self,
            .vtable = &.{
                .writeText = writeText,
                .writeLineBreak = writeLineBreak,
                .writeIndent = writeIndent,
                .writeSpace = writeSpace,
                .writeHorizontalRule = writeHorizontalRule,
                .pushAnnotation = pushAnnotation,
                .popAnnotation = popAnnotation,
                .writeRaw = writeRaw,
            },
        };
    }

    fn writeText(ctx: *anyopaque, text: []const u8) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(text);
        self.current_column += @intCast(text.len);
    }

    fn writeLineBreak(ctx: *anyopaque) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll("\n");
        self.current_line += 1;
        self.current_column = 0;
    }

    fn writeIndent(ctx: *anyopaque, levels: u32) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        const indent_size = levels * 4; // 4 spaces per level
        var i: u32 = 0;
        while (i < indent_size) : (i += 1) {
            try self.writer.writeAll(" ");
        }
        self.current_column += indent_size;
    }

    fn writeSpace(ctx: *anyopaque, count: u32) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try self.writer.writeAll(" ");
        }
        self.current_column += count;
    }

    fn writeHorizontalRule(ctx: *anyopaque, width: ?u32) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        const rule_width = width orelse 80;
        var i: u32 = 0;
        while (i < rule_width) : (i += 1) {
            try self.writer.writeAll("-");
        }
        self.current_column += rule_width;
    }

    fn pushAnnotation(ctx: *anyopaque, annotation: Annotation) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        try self.annotation_stack.append(annotation);
        // LSP renderer could emit diagnostic ranges here
    }

    fn popAnnotation(ctx: *anyopaque) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        if (self.annotation_stack.items.len > 0) {
            _ = self.annotation_stack.pop();
        }
    }

    fn writeRaw(ctx: *anyopaque, content: []const u8) !void {
        const self: *LspRenderer = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(content);
        // Update position tracking
        for (content) |char| {
            if (char == '\n') {
                self.current_line += 1;
                self.current_column = 0;
            } else {
                self.current_column += 1;
            }
        }
    }
};

// Tests
const testing = std.testing;

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

test "PlainTextRenderer with annotations" {
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
