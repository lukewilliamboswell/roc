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
