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

pub const renderReport = @import("reporting/renderer.zig").renderReport;
pub const renderReportToTerminal = @import("reporting/renderer.zig").renderReportToTerminal;
pub const renderReportToPlainText = @import("reporting/renderer.zig").renderReportToPlainText;
pub const renderReportToHtml = @import("reporting/renderer.zig").renderReportToHtml;
pub const renderReportToLsp = @import("reporting/renderer.zig").renderReportToLsp;
pub const renderDocument = @import("reporting/renderer.zig").renderDocument;
pub const renderDocumentToTerminal = @import("reporting/renderer.zig").renderDocumentToTerminal;
pub const renderDocumentToPlainText = @import("reporting/renderer.zig").renderDocumentToPlainText;
pub const renderDocumentToHtml = @import("reporting/renderer.zig").renderDocumentToHtml;
pub const renderDocumentToLsp = @import("reporting/renderer.zig").renderDocumentToLsp;
