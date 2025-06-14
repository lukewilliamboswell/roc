//! Reporting for the Roc compiler.

const std = @import("std");
const Allocator = std.mem.Allocator;
const base = @import("base.zig");

pub const Severity = @import("reporting/severity.zig").Severity;
pub const Document = @import("reporting/document.zig").Document;
pub const Annotation = @import("reporting/document.zig").Annotation;
pub const RenderTarget = @import("reporting/renderer.zig").RenderTarget;
pub const ColorPalette = @import("reporting/style.zig").ColorPalette;
pub const Report = @import("reporting/report.zig").Report;

pub const TerminalRenderer = @import("reporting/renderer.zig").TerminalRenderer;
pub const PlainTextRenderer = @import("reporting/renderer.zig").PlainTextRenderer;
pub const HtmlRenderer = @import("reporting/renderer.zig").HtmlRenderer;
