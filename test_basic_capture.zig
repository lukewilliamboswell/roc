const std = @import("std");
const testing = std.testing;
const eval = @import("src/eval/interpreter.zig");
const base = @import("base");
const parse = @import("src/check/parse.zig");
const canonicalize = @import("src/check/canonicalize.zig");
const check_types = @import("src/check/check_types.zig");
const CIR = canonicalize.CIR;
const types = @import("types");
const stack = @import("src/eval/stack.zig");
const layout_store = @import("src/layout/store.zig");
const layout = @import("src/layout/layout.zig");

const test_allocator = testing.allocator;

fn parseAndCanonicalizeExpr(allocator: std.mem.Allocator, src: []const u8) !struct {
    module_env: base.ModuleEnv,
    parse_ast: parse.Ast,
    cir: CIR,
    can: canonicalize.Canonicalizer,
    checker: check_types.TypeChecker,
    expr_idx: CIR.Expr.Idx,
} {
    var module_env = try base.ModuleEnv.init(allocator);
    var parse_ast = try parse.parse(allocator, src, &module_env);
    var cir = try CIR.init(allocator, &module_env);
    var can = canonicalize.Canonicalizer.init(allocator, &cir);

    const expr_idx = try can.canonicalizeExpr(parse_ast.ast.items[0].expr) orelse {
        std.debug.print("canonicalizeExpr returned null for src: {s}\n", .{src});
        return error.CanonicalizeError;
    };

    var checker = check_types.TypeChecker.init(allocator, &cir);
    try checker.solve();

    return .{
        .module_env = module_env,
        .parse_ast = parse_ast,
        .cir = cir,
        .can = can,
        .checker = checker,
        .expr_idx = expr_idx,
    };
}

fn cleanupParseAndCanonical(allocator: std.mem.Allocator, resources: anytype) void {
    _ = allocator;
    resources.module_env.deinit();
    resources.parse_ast.deinit();
    resources.cir.deinit();
    resources.can.deinit();
    resources.checker.deinit();
}

test "debug basic lambda capture - ArityMismatch investigation" {
    // Test the exact failing case
    const src = "((|x| |y| x + y)(42))(10)";
    std.debug.print("\n🧪 DEBUGGING BASIC CAPTURE: {s}\n", .{src});

    const resources = parseAndCanonicalizeExpr(test_allocator, src) catch |err| {
        std.debug.print("PARSE ERROR for basic capture: {any}\n", .{err});
        return err;
    };
    defer cleanupParseAndCanonical(test_allocator, resources);

    // Create evaluation environment
    var eval_stack = try stack.Stack.initCapacity(test_allocator, 1024);
    defer eval_stack.deinit();

    var layout_cache = try layout_store.Store.init(resources.module_env, &resources.module_env.types);
    defer layout_cache.deinit();

    var interpreter = try eval.Interpreter.init(test_allocator, resources.cir, &eval_stack, &layout_cache, &resources.module_env.types);
    defer interpreter.deinit();

    std.debug.print("🚀 STARTING EVALUATION...\n", .{});

    const result = interpreter.eval(resources.expr_idx) catch |err| {
        std.debug.print("💥 EVAL ERROR for basic capture: {any}\n", .{err});

        // Print some debug info about the current state
        std.debug.print("🔍 DEBUG INFO:\n", .{});
        std.debug.print("   Work stack size: {}\n", .{interpreter.work_stack.items.len});
        std.debug.print("   Layout stack size: {}\n", .{interpreter.layout_stack.items.len});
        std.debug.print("   Stack memory used: {}\n", .{interpreter.stack_memory.used});

        return err;
    };

    // Extract result - should be 42 + 10 = 52
    std.debug.print("✅ EVALUATION COMPLETE!\n", .{});
    std.debug.print("🔍 Result layout: {}\n", .{result.layout.tag});

    if (result.layout.tag == .scalar and result.layout.data.scalar.tag == .int) {
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
                std.debug.print("❌ Unexpected integer type: {}\n", .{result.layout.data.scalar.data.int});
                return error.UnsupportedType;
            },
        };

        std.debug.print("🎯 RESULT VALUE: {} (expected: 52)\n", .{int_val});
        try testing.expectEqual(@as(i64, 52), int_val);
    } else {
        std.debug.print("❌ Expected integer result, got: {}\n", .{result.layout.tag});
        return error.UnexpectedResultType;
    }
}
