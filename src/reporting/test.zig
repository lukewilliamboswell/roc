//! Test entry point for the reporting module.
//!
//! This file serves as the main test entry point for all reporting-related
//! functionality including rendering, document generation, styling, and reports.

const std = @import("std");
const testing = std.testing;

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
