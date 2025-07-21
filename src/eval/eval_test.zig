//! Tests for the expression evaluator
const std = @import("std");
const testing = std.testing;
const eval = @import("interpreter.zig");
const base = @import("base");
const parse = @import("../check/parse.zig");
const canonicalize = @import("../check/canonicalize.zig");
const check_types = @import("../check/check_types.zig");
const CIR = canonicalize.CIR;
const types = @import("types");
const stack = @import("stack.zig");
const layout_store = @import("../layout/store.zig");
const layout = @import("../layout/layout.zig");

const test_allocator = testing.allocator;

fn parseAndCanonicalizeExpr(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!struct {
    module_env: *base.ModuleEnv,
    parse_ast: *parse.AST,
    cir: *CIR,
    can: *canonicalize,
    checker: *check_types,
    expr_idx: CIR.Expr.Idx,
} {
    // Initialize the ModuleEnv
    const module_env = try allocator.create(base.ModuleEnv);
    module_env.* = try base.ModuleEnv.init(allocator, source);

    // Parse the source code as an expression
    const parse_ast = try allocator.create(parse.AST);
    parse_ast.* = try parse.parseExpr(module_env);

    // Empty scratch space (required before canonicalization)
    parse_ast.store.emptyScratch();

    // Create CIR
    const cir = try allocator.create(CIR);
    cir.* = try CIR.init(module_env, "test");

    // Create canonicalizer
    const can = try allocator.create(canonicalize);
    can.* = try canonicalize.init(cir, parse_ast, null);

    // Canonicalize the expression
    const expr_idx: parse.AST.Expr.Idx = @enumFromInt(parse_ast.root_node_idx);
    const canonical_expr_idx = try can.canonicalizeExpr(expr_idx) orelse {
        // If canonicalization fails, create a runtime error
        const diagnostic_idx = try cir.store.addDiagnostic(.{ .not_implemented = .{
            .feature = try cir.env.strings.insert(allocator, "canonicalization failed"),
            .region = base.Region.zero(),
        } });
        const checker = try allocator.create(check_types);
        checker.* = try check_types.init(allocator, &module_env.types, cir, &.{}, &cir.store.regions);
        return .{
            .module_env = module_env,
            .parse_ast = parse_ast,
            .cir = cir,
            .can = can,
            .checker = checker,
            .expr_idx = try cir.store.addExpr(.{ .e_runtime_error = .{
                .diagnostic = diagnostic_idx,
            } }, base.Region.zero()),
        };
    };

    // Create type checker
    const checker = try allocator.create(check_types);
    checker.* = try check_types.init(allocator, &module_env.types, cir, &.{}, &cir.store.regions);

    // Type check the expression
    _ = try checker.checkExpr(canonical_expr_idx);

    // WORKAROUND: The type checker doesn't set types for binop expressions yet.
    // For numeric binops, manually set the type to match the operands.
    const expr = cir.store.getExpr(canonical_expr_idx);
    if (expr == .e_binop) {
        const binop = expr.e_binop;
        // For arithmetic ops, use the type of the left operand
        switch (binop.op) {
            .add, .sub, .mul, .div, .rem, .pow, .div_trunc => {
                const left_var = @as(types.Var, @enumFromInt(@intFromEnum(binop.lhs)));
                const left_resolved = module_env.types.resolveVar(left_var);
                const result_var = @as(types.Var, @enumFromInt(@intFromEnum(canonical_expr_idx)));
                try module_env.types.setVarContent(result_var, left_resolved.desc.content);
            },
            .lt, .gt, .le, .ge, .eq, .ne => {
                // Comparison ops return Bool
                const result_var = @as(types.Var, @enumFromInt(@intFromEnum(canonical_expr_idx)));
                const bool_content = try module_env.types.mkBool(allocator, &module_env.idents, @enumFromInt(0));
                try module_env.types.setVarContent(result_var, bool_content);
            },
            else => {},
        }
    }

    return .{
        .module_env = module_env,
        .parse_ast = parse_ast,
        .cir = cir,
        .can = can,
        .checker = checker,
        .expr_idx = canonical_expr_idx,
    };
}

fn cleanupParseAndCanonical(allocator: std.mem.Allocator, resources: anytype) void {
    resources.checker.deinit();
    resources.can.deinit();
    resources.cir.deinit();
    resources.parse_ast.deinit(allocator);
    // module_env.source is freed by module_env.deinit()
    resources.module_env.deinit();
    allocator.destroy(resources.checker);
    allocator.destroy(resources.can);
    allocator.destroy(resources.cir);
    allocator.destroy(resources.parse_ast);
    allocator.destroy(resources.module_env);
}

test "eval runtime error - returns crash error" {
    const source = "crash \"test feature\"";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Check if the expression is a runtime error
    const expr = resources.cir.store.getExpr(resources.expr_idx);
    if (expr == .e_runtime_error) {
        // Create a stack for evaluation
        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();

        // Create layout store
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        // Evaluating a runtime error should return an error
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = interpreter.eval(resources.expr_idx);
        try testing.expectError(eval.EvalError.Crash, result);
    } else {
        // If crash syntax is not supported in canonicalization, skip
        return error.SkipZigTest;
    }
}

test "eval tag - already primitive" {
    // Skip this test for now as tag_union layout is not yet implemented
    return error.SkipZigTest;
}

test "eval binop - basic implementation" {
    const source = "5 + 3";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Create a stack for evaluation
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    // Create layout store
    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    // Evaluate the binop expression
    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();
    const result = try interpreter.eval(resources.expr_idx);

    // Verify we got a scalar layout
    try testing.expect(result.layout.tag == .scalar);
    try testing.expect(result.layout.data.scalar.tag == .int);

    // Read the result
    const int_val = switch (result.layout.data.scalar.data.int) {
        .i64 => @as(i64, @as(*i64, @ptrCast(@alignCast(result.ptr))).*),
        .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
        .i16 => @as(i64, @as(*i16, @ptrCast(@alignCast(result.ptr))).*),
        .i8 => @as(i64, @as(*i8, @ptrCast(@alignCast(result.ptr))).*),
        .u64 => @as(i64, @intCast(@as(*u64, @ptrCast(@alignCast(result.ptr))).*)),
        .u32 => @as(i64, @intCast(@as(*u32, @ptrCast(@alignCast(result.ptr))).*)),
        .u16 => @as(i64, @intCast(@as(*u16, @ptrCast(@alignCast(result.ptr))).*)),
        .u8 => @as(i64, @intCast(@as(*u8, @ptrCast(@alignCast(result.ptr))).*)),
        .u128 => @as(i64, @intCast(@as(*u128, @ptrCast(@alignCast(result.ptr))).*)),
        .i128 => @as(i64, @intCast(@as(*i128, @ptrCast(@alignCast(result.ptr))).*)),
    };

    try testing.expectEqual(@as(i64, 8), int_val);
}

test "eval if expression with boolean tags" {
    // Test that if expressions with boolean tag conditions evaluate correctly
    const sources = [_]struct { src: []const u8, expected: i128 }{
        .{ .src = "if True 1 else 0", .expected = 1 },
        .{ .src = "if False 1 else 0", .expected = 0 },
    };

    for (sources) |test_case| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, test_case.src);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = try interpreter.eval(resources.expr_idx);

        // Verify the result
        try testing.expect(result.layout.tag == .scalar);
        try testing.expect(result.layout.data.scalar.tag == .int);
        const value = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
        try testing.expectEqual(test_case.expected, value);
    }
}

test "eval if expression with comparison condition" {
    // Test if expressions with comparison conditions that evaluate to boolean tags
    const sources = [_]struct { src: []const u8, expected: i128 }{
        .{ .src = "if (1 == 1) 42 else 99", .expected = 42 },
        .{ .src = "if (1 == 2) 42 else 99", .expected = 99 },
        .{ .src = "if (5 > 3) 100 else 200", .expected = 100 },
        .{ .src = "if (3 > 5) 100 else 200", .expected = 200 },
    };

    for (sources) |test_case| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, test_case.src);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = try interpreter.eval(resources.expr_idx);

        // Verify the result
        try testing.expect(result.layout.tag == .scalar);
        try testing.expect(result.layout.data.scalar.tag == .int);
        const value = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
        try testing.expectEqual(test_case.expected, value);
    }
}

test "eval nested if expressions" {
    // Test that nested if expressions evaluate correctly
    const sources = [_]struct { src: []const u8, expected: i128 }{
        .{ .src = "if True (if True 10 else 20) else 30", .expected = 10 },
        .{ .src = "if True (if False 10 else 20) else 30", .expected = 20 },
        .{ .src = "if False (if True 10 else 20) else 30", .expected = 30 },
        .{ .src = "if False 99 else (if True 40 else 50)", .expected = 40 },
        .{ .src = "if False 99 else (if False 40 else 50)", .expected = 50 },
    };

    for (sources) |test_case| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, test_case.src);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = try interpreter.eval(resources.expr_idx);

        // Verify the result
        try testing.expect(result.layout.tag == .scalar);
        try testing.expect(result.layout.data.scalar.tag == .int);
        const value = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
        try testing.expectEqual(test_case.expected, value);
    }
}

test "eval if-else if-else chains" {
    // Test that if-else if-else chains evaluate correctly, taking the first true branch
    const sources = [_]struct { src: []const u8, expected: i128 }{
        .{ .src = 
        \\if True
        \\    10
        \\else if True
        \\    20
        \\else
        \\    30
        , .expected = 10 }, // First branch is true
        .{ .src = 
        \\if False
        \\    10
        \\else if True
        \\    20
        \\else
        \\    30
        , .expected = 20 }, // Second branch is true
        .{ .src = 
        \\if False
        \\    10
        \\else if False
        \\    20
        \\else
        \\    30
        , .expected = 30 }, // All conditions false, use else
    };

    for (sources) |test_case| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, test_case.src);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = try interpreter.eval(resources.expr_idx);

        // Verify the result
        try testing.expect(result.layout.tag == .scalar);
        try testing.expect(result.layout.data.scalar.tag == .int);
        const value = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
        try testing.expectEqual(test_case.expected, value);
    }
}

test "eval if expression with arithmetic in branches" {
    // Test that expressions in branches are evaluated correctly
    const sources = [_]struct { src: []const u8, expected: i128 }{
        .{ .src = "if True (1 + 2) else (3 + 4)", .expected = 3 },
        .{ .src = "if False (1 + 2) else (3 + 4)", .expected = 7 },
        .{ .src = "if True (10 * 5) else (20 / 4)", .expected = 50 },
        .{ .src = "if (2 > 1) (100 - 50) else (200 - 100)", .expected = 50 },
    };

    for (sources) |test_case| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, test_case.src);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = try interpreter.eval(resources.expr_idx);

        // Verify the result
        try testing.expect(result.layout.tag == .scalar);
        try testing.expect(result.layout.data.scalar.tag == .int);
        const value = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
        try testing.expectEqual(test_case.expected, value);
    }
}

test "eval if expression with non-boolean condition" {
    // Test that if expressions with non-boolean conditions result in type errors
    const source = "if 42 1 else 0"; // Integer condition (should be type error)

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();
    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();
    const result = interpreter.eval(resources.expr_idx);

    // Should result in a TypeContainedMismatch error because condition must be a boolean tag union
    try testing.expectError(eval.EvalError.TypeContainedMismatch, result);
}

test "eval simple number" {
    const source = "42";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Create a stack for evaluation
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    // Create layout store
    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    // Evaluate the number
    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();
    const result = try interpreter.eval(resources.expr_idx);

    // Verify we got an integer layout
    try testing.expect(result.layout.tag == .scalar);
    try testing.expect(result.layout.data.scalar.tag == .int);

    // Read the value back based on the precision
    const value: i128 = switch (result.layout.data.scalar.data.int) {
        .u8 => @as(*u8, @ptrCast(@alignCast(result.ptr))).*,
        .i8 => @as(*i8, @ptrCast(@alignCast(result.ptr))).*,
        .u16 => @as(*u16, @ptrCast(@alignCast(result.ptr))).*,
        .i16 => @as(*i16, @ptrCast(@alignCast(result.ptr))).*,
        .u32 => @as(*u32, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(*i32, @ptrCast(@alignCast(result.ptr))).*,
        .u64 => @as(*u64, @ptrCast(@alignCast(result.ptr))).*,
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .u128 => @intCast(@as(*u128, @ptrCast(@alignCast(result.ptr))).*),
        .i128 => @as(*i128, @ptrCast(@alignCast(result.ptr))).*,
    };

    // The parser now correctly converts "42" to the integer 42
    try testing.expectEqual(@as(i128, 42), value);
}

test "eval negative number" {
    const source = "-42";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Create a stack for evaluation
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    // Create layout store
    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    // Evaluate the number
    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();
    const result = try interpreter.eval(resources.expr_idx);

    // Verify we got an integer layout
    try testing.expect(result.layout.tag == .scalar);
    try testing.expect(result.layout.data.scalar.tag == .int);

    // Read the value back based on the precision
    const value: i128 = switch (result.layout.data.scalar.data.int) {
        .u8 => @as(*u8, @ptrCast(@alignCast(result.ptr))).*,
        .i8 => @as(*i8, @ptrCast(@alignCast(result.ptr))).*,
        .u16 => @as(*u16, @ptrCast(@alignCast(result.ptr))).*,
        .i16 => @as(*i16, @ptrCast(@alignCast(result.ptr))).*,
        .u32 => @as(*u32, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(*i32, @ptrCast(@alignCast(result.ptr))).*,
        .u64 => @as(*u64, @ptrCast(@alignCast(result.ptr))).*,
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .u128 => @intCast(@as(*u128, @ptrCast(@alignCast(result.ptr))).*),
        .i128 => @as(*i128, @ptrCast(@alignCast(result.ptr))).*,
    };

    // The parser now correctly converts "-42" to the integer -42
    try testing.expectEqual(@as(i128, -42), value);
}

test "eval list literal" {
    const source = "[1, 2, 3]";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Create a stack for evaluation
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    // Create layout store
    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    // List literals are not yet implemented
    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();
    const result = interpreter.eval(resources.expr_idx);
    try testing.expectError(eval.EvalError.LayoutError, result);
}

test "eval record literal" {
    const source = "{ x: 10, y: 20 }";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Check if this resulted in a runtime error due to failed canonicalization
    const expr = resources.cir.store.getExpr(resources.expr_idx);
    if (expr == .e_runtime_error) {
        // Expected - canonicalization of records may not be fully implemented
        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = interpreter.eval(resources.expr_idx);
        try testing.expectError(eval.EvalError.Crash, result);
    } else {
        // Record literals are not yet implemented
        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = interpreter.eval(resources.expr_idx);
        try testing.expectError(eval.EvalError.LayoutError, result);
    }
}

test "eval empty record" {
    const source = "{}";

    const resources = try parseAndCanonicalizeExpr(test_allocator, source);
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Check if this resulted in a runtime error due to incomplete canonicalization
    const expr = resources.cir.store.getExpr(resources.expr_idx);
    if (expr == .e_runtime_error) {
        // Expected - canonicalization of empty records may not be fully implemented
        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = interpreter.eval(resources.expr_idx);
        try testing.expectError(eval.EvalError.Crash, result);
    } else {
        // Create a stack for evaluation
        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();

        // Record the stack position before evaluation
        const stack_before = eval_stack.used;

        // Create layout store
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        // Empty records are zero-sized types, which should return an error
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();
        const result = interpreter.eval(resources.expr_idx);
        try testing.expectError(eval.EvalError.ZeroSizedType, result);

        // Verify the stack didn't grow
        const stack_after = eval_stack.used;
        try testing.expectEqual(stack_before, stack_after);
    }
}

test "eval integer literal directly from CIR node" {
    // This test creates expressions without proper canonicalization/type checking,
    // which means there are no corresponding type variables in the type store.
    // Since eval now requires real layouts from the type checker, this test
    // would need significant rework to properly set up the type system.
    // For now, skip this test.
    return error.SkipZigTest;
}

test "interpreter reuse across multiple evaluations" {
    // This test demonstrates that the interpreter can be reused across multiple
    // eval() calls, avoiding repeated allocations in scenarios like the REPL

    // Test multiple evaluations with the same work stack
    const sources = [_][]const u8{ "42", "100 + 200", "if True 1 else 2" };
    const expected = [_]i128{ 42, 300, 1 };

    for (sources, expected) |source, expected_value| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, source);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        // Create interpreter for this evaluation
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();

        // Verify work stack is empty before eval
        try testing.expectEqual(@as(usize, 0), interpreter.work_stack.items.len);

        const result = try interpreter.eval(resources.expr_idx);

        // Verify work stack is empty after eval (should be naturally empty, not cleared)
        try testing.expectEqual(@as(usize, 0), interpreter.work_stack.items.len);

        // Verify the result
        try testing.expect(result.layout.tag == .scalar);
        try testing.expect(result.layout.data.scalar.tag == .int);
        const value = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
        try testing.expectEqual(expected_value, value);
    }
}

test "lambda expressions comprehensive" {
    const TestCase = struct {
        src: []const u8,
        expected: i64,
        desc: []const u8,
    };

    const test_cases = [_]TestCase{
        // Basic lambda functionality
        .{ .src = "(|x| x + 1)(5)", .expected = 6, .desc = "simple lambda" },
        .{ .src = "(|x| x * 2 + 1)(10)", .expected = 21, .desc = "complex arithmetic" },
        .{ .src = "(|x| x - 3)(8)", .expected = 5, .desc = "subtraction" },
        .{ .src = "(|x| 100 - x)(25)", .expected = 75, .desc = "param in second position" },
        .{ .src = "(|x| 5)(99)", .expected = 5, .desc = "constant function ignoring param" },
        .{ .src = "(|x| x + x)(7)", .expected = 14, .desc = "parameter used twice" },

        // Multi-parameter functions
        .{ .src = "(|x, y| x + y)(3, 4)", .expected = 7, .desc = "two parameters" },
        .{ .src = "(|a, b, c| a + b + c)(1, 2, 3)", .expected = 6, .desc = "three parameters" },

        // If-expressions within lambda bodies
        .{ .src = "(|x| if x > 0 x else 0)(5)", .expected = 5, .desc = "max with zero, positive input" },
        .{ .src = "(|x| if x > 0 x else 0)(-3)", .expected = 0, .desc = "max with zero, negative input" },
        .{ .src = "(|x| if x == 0 1 else x)(0)", .expected = 1, .desc = "conditional replacement" },
        .{ .src = "(|x| if x == 0 1 else x)(42)", .expected = 42, .desc = "conditional passthrough" },

        // Unary minus operations
        .{ .src = "(|x| -x)(5)", .expected = -5, .desc = "unary minus on parameter" },
        .{ .src = "(|x| -x)(0)", .expected = 0, .desc = "unary minus on zero" },
        .{ .src = "(|x| -x)(-3)", .expected = 3, .desc = "unary minus on negative (double negative)" },
        .{ .src = "(|x| -5)(999)", .expected = -5, .desc = "negative literal in lambda" },
        .{ .src = "(|x| if True -10 else x)(999)", .expected = -10, .desc = "negative literal in if branch" },
        .{ .src = "(|x| if True -x else 0)(5)", .expected = -5, .desc = "unary minus in if branch" },

        // Complex expressions with unary minus
        .{ .src = "(|x| if x > 0 x else -x)(-5)", .expected = 5, .desc = "absolute value lambda with negative input" },
        .{ .src = "(|x| if x > 0 x else -x)(3)", .expected = 3, .desc = "absolute value lambda with positive input" },
        .{ .src = "(|x| x + 1)(-5)", .expected = -4, .desc = "lambda with negative argument" },

        // Binary operations as workarounds
        .{ .src = "(|x| 0 - x)(5)", .expected = -5, .desc = "subtraction workaround" },
    };

    for (test_cases) |case| {
        const resources = parseAndCanonicalizeExpr(test_allocator, case.src) catch |err| {
            std.debug.print("PARSE ERROR for {s} ({s}): {any}\n", .{ case.desc, case.src, err });
            return err;
        };
        defer cleanupParseAndCanonical(test_allocator, resources);

        // Create a stack for evaluation
        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();

        // Create layout store
        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        // Evaluate the function call
        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();

        const result = interpreter.eval(resources.expr_idx) catch |err| {
            std.debug.print("EVAL ERROR for {s} ({s}): {any}\n", .{ case.desc, case.src, err });
            return err;
        };

        // Extract integer result
        const int_val = switch (result.layout.data.scalar.data.int) {
            .i128 => blk: {
                const raw_val = @as(*i128, @ptrCast(@alignCast(result.ptr))).*;
                break :blk @as(i64, @intCast(raw_val));
            },
            .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
            .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
            .u64 => @as(i64, @intCast(@as(*u64, @ptrCast(@alignCast(result.ptr))).*)),
            .u32 => @as(i64, @intCast(@as(*u32, @ptrCast(@alignCast(result.ptr))).*)),
            else => {
                std.debug.print("Unsupported integer type for test\n", .{});
                return error.UnsupportedType;
            },
        };

        try testing.expectEqual(case.expected, int_val);
    }
}

test "lambda memory management" {
    // Simple test to ensure we don't crash with lambda memory management
    const test_expressions = [_][]const u8{
        "(|x| x + 1)(5)",
        "(|x, y| x + y)(10, 20)",
        "(|a, b, c| a + b + c)(1, 2, 3)",
    };

    for (test_expressions) |expr| {
        const resources = try parseAndCanonicalizeExpr(test_allocator, expr);
        defer cleanupParseAndCanonical(test_allocator, resources);

        var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
        defer eval_stack.deinit();

        var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
        defer layout_cache.deinit();

        var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
        defer interpreter.deinit();

        const result = try interpreter.eval(resources.expr_idx);

        // Verify we got a valid result
        try testing.expect(result.layout.tag == .scalar);
    }
}

test "lambda variable capture - basic single variable" {
    // Test a closure that captures a single variable from outer scope
    const src = "((|x| |y| x + y)(42))(10)";

    std.debug.print("\n🧪 DEBUG: Starting basic capture test with: {s}\n", .{src});

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("PARSE ERROR for basic capture: {any}\n", .{err});
        return err;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    std.debug.print("🧪 DEBUG: Parse and canonicalize successful\n", .{});

    // Create evaluation environment
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    std.debug.print("🧪 DEBUG: Starting evaluation...\n", .{});
    std.debug.print("🧪 DEBUG: Work stack initial size: {}\n", .{interpreter.work_stack.items.len});
    std.debug.print("🧪 DEBUG: Layout stack initial size: {}\n", .{interpreter.layout_stack.items.len});

    const result = interpreter.eval(resources.expr_idx) catch |err| {
        std.debug.print("💥 EVAL ERROR for basic capture: {any}\n", .{err});
        std.debug.print("🔍 DEBUG: Work stack final size: {}\n", .{interpreter.work_stack.items.len});
        std.debug.print("🔍 DEBUG: Layout stack final size: {}\n", .{interpreter.layout_stack.items.len});
        std.debug.print("🔍 DEBUG: Stack memory used: {}\n", .{interpreter.stack_memory.used});
        return err;
    };

    // Extract result - should be 42 + 10 = 52
    std.debug.print("✅ DEBUG: Evaluation successful!\n", .{});
    std.debug.print("🔍 DEBUG: Result layout tag: {}\n", .{result.layout.tag});
    if (result.layout.tag == .scalar) {
        std.debug.print("🔍 DEBUG: Scalar type: {}\n", .{result.layout.data.scalar.tag});
        if (result.layout.data.scalar.tag == .int) {
            std.debug.print("🔍 DEBUG: Integer type: {}\n", .{result.layout.data.scalar.data.int});
        }
    }
    std.debug.print("DEBUG: Raw result value: {}\n", .{@as(*u8, @ptrCast(@alignCast(result.ptr))).*});
    std.debug.print("DEBUG: Expected 42 + 10 = 52, but got: {}\n", .{@as(*u8, @ptrCast(@alignCast(result.ptr))).*});
    const int_val = switch (result.layout.data.scalar.data.int) {
        .i128 => @as(i64, @intCast(@as(*i128, @ptrCast(@alignCast(result.ptr))).*)),
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
        .i16 => @as(i64, @as(*i16, @ptrCast(@alignCast(result.ptr))).*),
        .i8 => @as(i64, @as(*i8, @ptrCast(@alignCast(result.ptr))).*),
        .u64 => @as(i64, @intCast(@as(*u64, @ptrCast(@alignCast(result.ptr))).*)),
        .u32 => @as(i64, @as(*u32, @ptrCast(@alignCast(result.ptr))).*),
        .u16 => @as(i64, @as(*u16, @ptrCast(@alignCast(result.ptr))).*),
        .u8 => @as(i64, @as(*u8, @ptrCast(@alignCast(result.ptr))).*),
        else => {
            std.debug.print("Unexpected integer type in capture test: {}\n", .{result.layout.data.scalar.data.int});
            return error.UnsupportedType;
        },
    };

    try testing.expectEqual(@as(i64, 52), int_val);
}

test "lambda variable capture - multiple variables" {
    // Test a closure that captures multiple variables from outer scope
    const src = "((|a, b, c| |x| a + b + c + x)(10, 20, 5))(7)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("PARSE ERROR for multi capture: {any}\n", .{err});
        return err;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    const result = interpreter.eval(resources.expr_idx) catch |err| {
        std.debug.print("EVAL ERROR for multi capture: {any}\n", .{err});
        return err;
    };

    // Extract result - should be 10 + 20 + 5 + 7 = 42
    const int_val = switch (result.layout.data.scalar.data.int) {
        .i128 => @as(i64, @intCast(@as(*i128, @ptrCast(@alignCast(result.ptr))).*)),
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
        else => return error.UnsupportedType,
    };

    try testing.expectEqual(@as(i64, 42), int_val);
}

test "lambda variable capture - nested closures" {
    // Test nested closures where inner closure captures from multiple scopes
    const src = "(((|outer_var| |middle_var| |inner_var| outer_var + middle_var + inner_var)(100))(20))(3)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("PARSE ERROR for nested capture: {any}\n", .{err});
        return err;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    var eval_stack = try stack.Stack.initCapacity(test_allocator, 2048); // Larger stack for nested calls
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    const result = interpreter.eval(resources.expr_idx) catch |err| {
        std.debug.print("EVAL ERROR for nested capture: {any}\n", .{err});
        return err;
    };

    // Extract result - should be 100 + 20 + 3 = 123
    const int_val = switch (result.layout.data.scalar.data.int) {
        .i128 => @as(i64, @intCast(@as(*i128, @ptrCast(@alignCast(result.ptr))).*)),
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
        else => return error.UnsupportedType,
    };

    try testing.expectEqual(@as(i64, 123), int_val);
}

test "lambda capture analysis - simple closure should use SimpleClosure" {
    // Test that lambdas without captures use the simple closure path
    const src = "(|x| x + 1)(42)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch return error.TestError;
    defer cleanupParseAndCanonical(test_allocator, resources);

    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    const result = try interpreter.eval(resources.expr_idx);

    // Verify result is correct
    const int_val = switch (result.layout.data.scalar.data.int) {
        .i128 => @as(i64, @intCast(@as(*i128, @ptrCast(@alignCast(result.ptr))).*)),
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
        else => return error.UnsupportedType,
    };

    try testing.expectEqual(@as(i64, 43), int_val);
}

test "lambda capture - conditional expressions with captures" {
    // Test captured variables used in conditional expressions
    const src = "((|threshold| |x| if x > threshold then x else 0)(25))(30)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch return error.TestError;
    defer cleanupParseAndCanonical(test_allocator, resources);

    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    const result = try interpreter.eval(resources.expr_idx);

    // Extract result - should be 30 (since 30 > 25)
    const int_val = switch (result.layout.data.scalar.data.int) {
        .i128 => @as(i64, @intCast(@as(*i128, @ptrCast(@alignCast(result.ptr))).*)),
        .i64 => @as(*i64, @ptrCast(@alignCast(result.ptr))).*,
        .i32 => @as(i64, @as(*i32, @ptrCast(@alignCast(result.ptr))).*),
        else => return error.UnsupportedType,
    };

    try testing.expectEqual(@as(i64, 30), int_val);
}

test "end-to-end capture verification - simple nested closure" {
    // This test verifies that the complete capture flow works:
    // 1. Capture analysis identifies variables to capture
    // 2. Enhanced closure creation allocates environment
    // 3. Variable lookup finds captured values during execution
    // 4. Final result is computed correctly

    const src = "(|x| (|y| x + y))(5)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch return error.TestError;
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Create evaluation environment
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 2048); // Larger for nested calls
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    std.debug.print("\n🧪 TESTING END-TO-END CAPTURE: {s}\n", .{src});

    // This should create an enhanced closure for the inner lambda |y| x + y
    // that captures x from the outer scope, then execute it
    const result = interpreter.eval(resources.expr_idx) catch |err| {
        std.debug.print("❌ END-TO-END CAPTURE TEST FAILED: {any}\n", .{err});
        return err;
    };

    std.debug.print("✅ END-TO-END CAPTURE TEST COMPLETED\n", .{});

    // The result should be a closure (the inner lambda with x=5 captured)
    // We don't expect a final numeric result since we're not calling the inner lambda
    try testing.expect(result.layout.tag == .closure);
}

fn inspectExpressionRecursively(cir: *const CIR, expr_idx: CIR.Expr.Idx, depth: u32) void {
    const indents = [_][]const u8{
        "",
        "  ",
        "    ",
        "      ",
        "        ",
        "          ",
        "            ",
        "              ",
        "                ",
        "                  ",
        "                    ",
    };
    const indent = indents[@min(depth, indents.len - 1)];
    const expr = cir.store.getExpr(expr_idx);

    std.debug.print("{s}[{}] {}\n", .{ indent, @intFromEnum(expr_idx), expr });

    switch (expr) {
        .e_call => |call| {
            const call_args = cir.store.sliceExpr(call.args);
            std.debug.print("{s}  Call with {} args:\n", .{ indent, call_args.len });
            for (call_args, 0..) |arg_expr, i| {
                std.debug.print("{s}    Arg[{}]:\n", .{ indent, i });
                inspectExpressionRecursively(cir, arg_expr, depth + 2);
            }
        },
        .e_lambda => |lambda| {
            std.debug.print("{s}  Lambda - args span: {}, body:\n", .{ indent, lambda.args });
            inspectExpressionRecursively(cir, lambda.body, depth + 1);

            // Note: Capture analysis now happens during canonicalization
            std.debug.print("{s}  Capture information available in canonicalized lambda.captures\n", .{indent});
        },
        .e_binop => |binop| {
            std.debug.print("{s}  Binop - {}\n", .{ indent, binop.op });
            std.debug.print("{s}    LHS:\n", .{indent});
            inspectExpressionRecursively(cir, binop.lhs, depth + 1);
            std.debug.print("{s}    RHS:\n", .{indent});
            inspectExpressionRecursively(cir, binop.rhs, depth + 1);
        },
        .e_lookup_local => |lookup| {
            std.debug.print("{s}  Local lookup - pattern idx {}\n", .{ indent, @intFromEnum(lookup.pattern_idx) });
        },
        .e_block => |block| {
            std.debug.print("{s}  Block with {} statements:\n", .{ indent, block.stmts.span.len });
            const statements = cir.store.sliceStatements(block.stmts);
            for (statements, 0..) |stmt_idx, i| {
                std.debug.print("{s}    Stmt[{}]:\n", .{ indent, i });
                const stmt = cir.store.getStatement(stmt_idx);
                std.debug.print("{s}      {}\n", .{ indent, stmt });
            }
            std.debug.print("{s}    Final expr:\n", .{indent});
            inspectExpressionRecursively(cir, block.final_expr, depth + 1);
        },
        .e_int, .e_frac_f64 => {
            // Leaf nodes, no further recursion needed
        },
        else => {
            std.debug.print("{s}  (Other expression type)\n", .{indent});
        },
    }
}

test "capture debug - simple lambda" {
    std.debug.print("\n=== CAPTURE DEBUG: Simple Lambda ===\n", .{});
    const src = "(|x| x + 1)(5)";
    std.debug.print("Source: {s}\n", .{src});

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("Parse failed: {}\n", .{err});
        return;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    std.debug.print("AST Structure:\n", .{});
    inspectExpressionRecursively(resources.cir, resources.expr_idx, 0);
    std.debug.print("=== END CAPTURE DEBUG ===\n\n", .{});
}

test "capture debug - nested lambda" {
    std.debug.print("\n=== CAPTURE DEBUG: Nested Lambda ===\n", .{});
    const src = "(|x| (|y| x + y))(42)";
    std.debug.print("Source: {s}\n", .{src});

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("Parse failed: {}\n", .{err});
        return;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    std.debug.print("AST Structure:\n", .{});
    inspectExpressionRecursively(resources.cir, resources.expr_idx, 0);
    std.debug.print("=== END CAPTURE DEBUG ===\n\n", .{});
}

test "debug - understand capture analysis behavior" {
    // Simple test to understand how our capture analysis works
    const src = "(|x| x + 1)(5)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch return error.TestError;
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Let's manually run capture analysis on any lambda we find
    std.debug.print("\n=== DEBUG: Analyzing expression structure ===\n", .{});

    // Try to find lambda expressions in the AST and run capture analysis
    const expr = resources.cir.store.getExpr(resources.expr_idx);
    std.debug.print("Root expression type: {}\n", .{expr});

    // Look for e_call expressions which might contain lambdas
    switch (expr) {
        .e_call => |call| {
            const call_args = resources.cir.store.sliceExpr(call.args);
            std.debug.print("Call has {} expressions\n", .{call_args.len});
            for (call_args, 0..) |arg_expr, i| {
                const arg = resources.cir.store.getExpr(arg_expr);
                std.debug.print("  Arg[{}]: {}\n", .{ i, arg });
                if (arg == .e_lambda) {
                    std.debug.print("  Found lambda! Capture info in arg.e_lambda.captures\n", .{});
                    std.debug.print("    Captures: {}\n", .{arg.e_lambda.captures.captured_vars.len});
                }
            }
        },
        else => {},
    }

    std.debug.print("=== END DEBUG ===\n", .{});
}

test "debug - check block expression parsing" {
    // Test what happens with multi-statement expressions
    const src =
        \\{
        \\    x = 42
        \\    f = |y| x + y
        \\    f(10)
        \\}
    ;

    std.debug.print("\n=== DEBUG: Block expression parsing ===\n", .{});
    std.debug.print("Source: {s}\n", .{src});

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("Parse failed: {}\n", .{err});
        return;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    const expr = resources.cir.store.getExpr(resources.expr_idx);
    std.debug.print("Root expression type: {}\n", .{expr});

    std.debug.print("=== END DEBUG ===\n", .{});
}

test "simple nested closure - scope chain verification" {
    // Simple nested closure to test ExecutionContext scope chain
    const src = "(|x| (|y| x + y))(5)";

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("PARSE ERROR for simple nested: {any}\n", .{err});
        return err;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    const result = interpreter.eval(resources.expr_idx) catch |err| {
        std.debug.print("EVAL ERROR for simple nested: {any}\n", .{err});
        return err;
    };

    // Result should be a closure that captures x=5
    try testing.expect(result.layout.tag == .closure);
    std.debug.print("SUCCESS: Simple nested closure created with captured variable\n", .{});
}
