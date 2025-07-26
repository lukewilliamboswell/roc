//! The evaluation part of the Read-Eval-Print-Loop (REPL)

const std = @import("std");
const roc = @import("roc");
const base = roc.base;
const compile = roc.compile;
const parse = roc.parse;
const reporting = roc.reporting;
const types = roc.types;
const canonicalize = roc.check.canonicalize;
const check_types = roc.check;
const layout_store = roc.layout.store;
const layout = roc.layout;
const eval = roc.eval;
const stack = roc.eval.stack;

const Allocator = std.mem.Allocator;
const ModuleEnv = compile.ModuleEnv;
const AST = parse.AST;
const target = base.target;
const types_store = types.store;

/// Type of definition stored in the REPL history
const DefKind = union(enum) {
    /// An assignment with an identifier
    assignment: []const u8,
    /// An import statement
    import,
};

/// Represents a past definition in the REPL session
const PastDef = struct {
    /// The source code of the definition
    source: []const u8,
    /// The kind of definition
    kind: DefKind,

    pub fn deinit(self: *PastDef, allocator: Allocator) void {
        allocator.free(self.source);
        switch (self.kind) {
            .assignment => |ident| allocator.free(ident),
            .import => {},
        }
    }
};

/// REPL state that tracks past definitions and evaluates expressions
pub const Repl = struct {
    allocator: Allocator,
    /// All past definitions in order (allows redefinition/shadowing)
    past_defs: std.ArrayList(PastDef),
    /// Stack for evaluation
    eval_stack: stack.Stack,
    reports: std.ArrayList(reporting.Report),

    pub fn init(allocator: Allocator) !Repl {
        const eval_stack = try stack.Stack.initCapacity(allocator, 8192);

        return Repl{
            .allocator = allocator,
            .past_defs = std.ArrayList(PastDef).init(allocator),
            .eval_stack = eval_stack,
            .reports = std.ArrayList(reporting.Report).init(allocator),
        };
    }

    pub fn deinit(self: *Repl) void {
        for (self.past_defs.items) |*def| {
            def.deinit(self.allocator);
        }
        self.past_defs.deinit();
        self.eval_stack.deinit();

        for (self.reports.items) |*report| {
            report.deinit();
        }
        self.reports.deinit();
    }

    pub fn addReport(self: *Repl, report: reporting.Report) !void {
        try self.reports.append(report);
    }

    pub const StepResult = union(enum) {
        value: struct {
            string: []const u8,
            type_str: []const u8,
        },
        report: []const u8,
        exit: []const u8,
    };

    /// Process a line of input and return the result
    pub fn step(self: *Repl, line: []const u8) !StepResult {
        // Clear any reports from the previous step
        for (self.reports.items) |*report| {
            report.deinit();
        }
        self.reports.clearRetainingCapacity();

        const trimmed = std.mem.trim(u8, line, " \t\n\r");

        // Handle special commands
        if (trimmed.len == 0) {
            return StepResult{ .value = .{ .string = try self.allocator.dupe(u8, ""), .type_str = try self.allocator.dupe(u8, "") } };
        }

        if (std.mem.eql(u8, trimmed, ":help")) {
            const help_text =
                \\Enter an expression to evaluate, or a definition (like x = 1) to use later.
                \\
                \\  - :q quits
                \\  - :help shows this text again
            ;
            return StepResult{ .value = .{ .string = try self.allocator.dupe(u8, help_text), .type_str = try self.allocator.dupe(u8, "") } };
        }

        if (std.mem.eql(u8, trimmed, ":exit") or
            std.mem.eql(u8, trimmed, ":quit") or
            std.mem.eql(u8, trimmed, ":q"))
        {
            return StepResult{ .exit = try self.allocator.dupe(u8, "Goodbye!") };
        }

        // Process the input
        const result = try self.processInput(trimmed);

        // If there are any reports, return the first one
        if (self.reports.items.len > 0) {
            var report_buffer = std.ArrayList(u8).init(self.allocator);
            // Note: we are not using defer deinit, because we toOwnedSlice and return it.
            // The caller of `step` is responsible for freeing the memory.

            // Render the report to the buffer.
            // We use `.color_terminal` format as this is for a REPL.
            try self.reports.items[0].render(report_buffer.writer(), .color_terminal);

            return StepResult{ .report = try report_buffer.toOwnedSlice() };
        }

        return StepResult{ .value = .{ .string = result.value_str, .type_str = result.type_str } };
    }

    /// Process regular input (not special commands)
    fn processInput(self: *Repl, input: []const u8) !EvalResult {
        // Try to parse as a statement first
        const parse_result = try self.tryParseStatement(input);

        switch (parse_result) {
            .assignment => |info| {
                defer self.allocator.free(info.ident);

                // Add to past definitions (allows redefinition)
                try self.past_defs.append(.{
                    .source = try self.allocator.dupe(u8, input),
                    .kind = .{ .assignment = try self.allocator.dupe(u8, info.ident) },
                });

                // For assignments, evaluate the RHS directly
                // Extract the RHS from the assignment
                if (std.mem.indexOf(u8, input, "=")) |eq_pos| {
                    const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " \t\n");

                    // If the RHS is a simple literal, evaluate it directly
                    if (std.fmt.parseInt(i64, rhs, 10)) |_| {
                        return self.evalExpr(rhs);
                    } else |_| {}

                    // Otherwise, evaluate with context
                    const full_source = try self.buildFullSource(rhs);
                    defer self.allocator.free(full_source);
                    return self.evaluateSource(full_source);
                }

                return .{
                    .value_str = try self.allocator.dupe(u8, ""),
                    .type_str = try self.allocator.dupe(u8, ""),
                };
            },
            .import => {
                // Add import to past definitions
                try self.past_defs.append(.{
                    .source = try self.allocator.dupe(u8, input),
                    .kind = .import,
                });

                return .{
                    .value_str = try self.allocator.dupe(u8, ""),
                    .type_str = try self.allocator.dupe(u8, ""),
                };
            },
            .expression => {
                // Evaluate expression with all past definitions
                const full_source = try self.buildFullSource(input);
                defer self.allocator.free(full_source);

                return self.evaluateSource(full_source);
            },
            .type_decl => {
                // Type declarations can't be evaluated
                return .{
                    .value_str = try self.allocator.dupe(u8, ""),
                    .type_str = try self.allocator.dupe(u8, ""),
                };
            },
            .parse_error => |msg| {
                defer self.allocator.free(msg);
                return .{
                    .value_str = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{msg}),
                    .type_str = "",
                };
            },
        }
    }

    const ParseResult = union(enum) {
        assignment: struct { ident: []const u8 }, // This ident must be allocator.dupe'd
        import,
        expression,
        type_decl,
        parse_error: []const u8, // This must be allocator.dupe'd
    };

    /// Try to parse input as a statement
    fn tryParseStatement(self: *Repl, input: []const u8) !ParseResult {
        var module_env = try ModuleEnv.init(self.allocator, input);
        defer module_env.deinit();

        // Try statement parsing
        if (parse.parseStatement(&module_env)) |ast_const| {
            var ast = ast_const;
            defer ast.deinit(self.allocator);

            if (ast.root_node_idx != 0) {
                const stmt_idx: AST.Statement.Idx = @enumFromInt(ast.root_node_idx);
                const stmt = ast.store.getStatement(stmt_idx);

                switch (stmt) {
                    .decl => |decl| {
                        const pattern = ast.store.getPattern(decl.pattern);
                        if (pattern == .ident) {
                            const ident_tok = pattern.ident.ident_tok;
                            const token_region = ast.tokens.resolve(@intCast(ident_tok));
                            const ident = ast.env.source[token_region.start.offset..token_region.end.offset];
                            // Make a copy of the identifier since ast will be freed
                            const ident_copy = try self.allocator.dupe(u8, ident);
                            return ParseResult{ .assignment = .{ .ident = ident_copy } };
                        }
                        return ParseResult.expression;
                    },
                    .import => return ParseResult.import,
                    .type_decl => return ParseResult.type_decl,
                    else => return ParseResult.expression,
                }
            }
        } else |_| {}

        // Try expression parsing
        if (parse.parseExpr(&module_env)) |ast_const| {
            var ast = ast_const;
            defer ast.deinit(self.allocator);
            if (ast.root_node_idx != 0) {
                return ParseResult.expression;
            }
        } else |_| {}

        return ParseResult{ .parse_error = try self.allocator.dupe(u8, "Failed to parse input") };
    }

    /// Build full source including all past definitions
    fn buildFullSource(self: *Repl, current_expr: []const u8) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Add all past definitions in order (later ones shadow earlier ones)
        for (self.past_defs.items) |def| {
            try buffer.appendSlice(def.source);
            try buffer.append('\n');
        }

        // Add current expression
        try buffer.appendSlice(current_expr);

        return try buffer.toOwnedSlice();
    }

    /// Evaluate source code
    fn evaluateSource(self: *Repl, source: []const u8) !EvalResult {
        // For now, we evaluate the source as a single expression.
        // This will be extended to handle multiple statements and definitions.
        return self.evalExpr(source);
    }

    const EvalResult = struct {
        value_str: []const u8,
        type_str: []const u8,
    };

    fn evalExpr(self: *Repl, expr_source: []const u8) !EvalResult {
        // Create module environment for the expression
        var module_env = try ModuleEnv.init(self.allocator, expr_source);
        defer module_env.deinit();

        // Parse as expression
        var parse_ast = parse.parseExpr(&module_env) catch |err| {
            var report = reporting.Report.init(self.allocator, "Parse Error", .fatal);
            try report.addErrorMessage(try std.fmt.allocPrint(self.allocator, "{}", .{err}));
            try self.addReport(report);
            return .{
                .value_str = "",
                .type_str = "",
            };
        };
        defer parse_ast.deinit(self.allocator);

        // Empty scratch space
        parse_ast.store.emptyScratch();

        // Create CIR
        const cir = &module_env; // CIR is now just ModuleEnv
        try cir.initCIRFields(self.allocator, "repl");

        // Create canonicalizer
        var can = canonicalize.init(cir, &parse_ast, null) catch |err| {
            return .{
                .value_str = try std.fmt.allocPrint(self.allocator, "Canonicalize init error: {}", .{err}),
                .type_str = "",
            };
        };
        defer can.deinit();

        // Canonicalize the expression
        const expr_idx: parse.AST.Expr.Idx = @enumFromInt(parse_ast.root_node_idx);
        const canonical_expr_idx = can.canonicalizeExpr(expr_idx) catch |err| {
            var report = reporting.Report.init(self.allocator, "Canonicalization Error", .fatal);
            try report.addErrorMessage(try std.fmt.allocPrint(self.allocator, "{}", .{err}));
            try self.addReport(report);
            return .{
                .value_str = "",
                .type_str = "",
            };
        } orelse {
            var report = reporting.Report.init(self.allocator, "Canonicalization Error", .fatal);
            try report.addErrorMessage("Failed to canonicalize expression");
            try self.addReport(report);
            return .{
                .value_str = "",
                .type_str = "",
            };
        };

        // Type check
        var checker = check_types.init(self.allocator, &module_env.types, cir, &.{}, &cir.store.regions) catch |err| {
            return .{
                .value_str = try std.fmt.allocPrint(self.allocator, "Type check init error: {}", .{err}),
                .type_str = "",
            };
        };
        defer checker.deinit();

        _ = checker.checkExpr(canonical_expr_idx.get_idx()) catch |err| {
            var report = reporting.Report.init(self.allocator, "Type Error", .fatal);
            try report.addErrorMessage(try std.fmt.allocPrint(self.allocator, "{}", .{err}));
            try self.addReport(report);
            return .{
                .value_str = "",
                .type_str = "",
            };
        };

        // Create layout cache
        var layout_cache = layout_store.Store.init(&module_env, &module_env.types) catch |err| {
            return .{
                .value_str = try std.fmt.allocPrint(self.allocator, "Layout cache error: {}", .{err}),
                .type_str = "",
            };
        };
        defer layout_cache.deinit();

        // Create interpreter
        var interpreter = eval.Interpreter.init(self.allocator, cir, &self.eval_stack, &layout_cache, &module_env.types) catch |err| {
            return .{
                .value_str = try std.fmt.allocPrint(self.allocator, "Interpreter init error: {}", .{err}),
                .type_str = "",
            };
        };
        defer interpreter.deinit();

        // Evaluate the expression
        const result = interpreter.eval(canonical_expr_idx.get_idx()) catch |err| {
            return .{
                .value_str = try std.fmt.allocPrint(self.allocator, "Evaluation error: {}", .{err}),
                .type_str = "",
            };
        };

        // Format the type
        const type_str = try self.formatLayout(result.layout);

        // Format the result
        const value_str = blk: {
            if (result.layout.tag == .scalar) {
                switch (result.layout.data.scalar.tag) {
                    .bool => {
                        // Boolean values are stored as u8 (1 for True, 0 for False)
                        const bool_value: *u8 = @ptrCast(result.ptr.?);
                        break :blk try self.allocator.dupe(u8, if (bool_value.* == 1) "True" else "False");
                    },
                    .int => {
                        const value: i128 = eval.readIntFromMemory(@ptrCast(result.ptr.?), result.layout.data.scalar.data.int);
                        break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{value});
                    },
                    else => {},
                }
                break :blk try std.fmt.allocPrint(self.allocator, "<unsupported scalar>", .{});
            } else if (result.layout.tag == .list_of_zst) {
                _ = try self.allocator.dupe(u8, "<list_of_zst>");
                break :blk "";
            } else {
                break :blk try std.fmt.allocPrint(self.allocator, "<{s}>", .{@tagName(result.layout.tag)});
            }
        };

        return .{
            .value_str = value_str,
            .type_str = type_str,
        };
    }

    fn formatLayout(self: *Repl, l: layout.Layout) ![]const u8 {
        return switch (l.tag) {
            .scalar => switch (l.data.scalar.tag) {
                .int => std.fmt.allocPrint(self.allocator, "{s}", .{@tagName(l.data.scalar.data.int)}),
                .frac => std.fmt.allocPrint(self.allocator, "{s}", .{@tagName(l.data.scalar.data.frac)}),
                .bool => self.allocator.dupe(u8, "Bool"),
                .str => self.allocator.dupe(u8, "Str"),
                .opaque_ptr => self.allocator.dupe(u8, "Opaque"),
            },
            .box => self.allocator.dupe(u8, "Box"),
            .box_of_zst => self.allocator.dupe(u8, "Box"),
            .list => self.allocator.dupe(u8, "List"),
            .list_of_zst => self.allocator.dupe(u8, "List"),
            .record => self.allocator.dupe(u8, "Record"),
            .tuple => self.allocator.dupe(u8, "Tuple"),
            .closure => self.allocator.dupe(u8, "Closure"),
        };
    }
};

// Tests
const testing = std.testing;

test "Repl - initialization and cleanup" {
    var repl = try Repl.init(testing.allocator);
    defer repl.deinit();

    try testing.expect(repl.past_defs.items.len == 0);
}

test "Repl - special commands" {
    var repl = try Repl.init(testing.allocator);
    defer repl.deinit();

    const help_result = try repl.step(":help");
    if (help_result == .value) {
        defer testing.allocator.free(help_result.value.string);
        defer testing.allocator.free(help_result.value.type_str);
        try testing.expect(std.mem.indexOf(u8, help_result.value.string, "Enter an expression") != null);
    } else {
        if (help_result == .report) {
            defer testing.allocator.free(help_result.report);
        } else if (help_result == .exit) {
            defer testing.allocator.free(help_result.exit);
        }
        try testing.expect(false);
    }

    const exit_result = try repl.step(":exit");
    if (exit_result == .exit) {
        defer testing.allocator.free(exit_result.exit);
        try testing.expectEqualStrings("Goodbye!", exit_result.exit);
    } else {
        if (exit_result == .value) {
            defer testing.allocator.free(exit_result.value.string);
            defer testing.allocator.free(exit_result.value.type_str);
        } else if (exit_result == .report) {
            defer testing.allocator.free(exit_result.report);
        }
        try testing.expect(false);
    }

    const empty_result = try repl.step("");
    if (empty_result == .value) {
        defer testing.allocator.free(empty_result.value.string);
        defer testing.allocator.free(empty_result.value.type_str);
        try testing.expectEqualStrings("", empty_result.value.string);
    } else {
        if (empty_result == .report) {
            defer testing.allocator.free(empty_result.report);
        } else if (empty_result == .exit) {
            defer testing.allocator.free(empty_result.exit);
        }
        try testing.expect(false);
    }
}

test "Repl - simple expressions" {
    var repl = try Repl.init(testing.allocator);
    defer repl.deinit();

    const result = try repl.step("42");
    if (result == .value) {
        defer testing.allocator.free(result.value.string);
        defer testing.allocator.free(result.value.type_str);
        try testing.expectEqualStrings("42", result.value.string);
        try testing.expectEqualStrings("i128", result.value.type_str);
    } else {
        if (result == .report) {
            defer testing.allocator.free(result.report);
        } else if (result == .exit) {
            defer testing.allocator.free(result.exit);
        }
        try testing.expect(false);
    }
}

test "Repl - redefinition with evaluation" {
    var repl = try Repl.init(testing.allocator);
    defer repl.deinit();

    // First definition of x
    const result1 = try repl.step("x = 5");
    if (result1 == .value) {
        defer testing.allocator.free(result1.value.string);
        defer testing.allocator.free(result1.value.type_str);
        try testing.expectEqualStrings("5", result1.value.string);
        try testing.expectEqualStrings("i128", result1.value.type_str);
    } else {
        try testing.expect(false);
    }

    // Define y in terms of x. This should fail because `x` is not in scope.
    const result2 = try repl.step("y = x + 1");
    if (result2 == .report) {
        defer testing.allocator.free(result2.report);
    } else {
        try testing.expect(false);
    }

    // Redefine x
    const result3 = try repl.step("x = 6");
    if (result3 == .value) {
        defer testing.allocator.free(result3.value.string);
        defer testing.allocator.free(result3.value.type_str);
        try testing.expectEqualStrings("6", result3.value.string);
        try testing.expectEqualStrings("i128", result3.value.type_str);
    } else {
        try testing.expect(false);
    }

    // Evaluate x. This should fail because `x` is not in scope.
    const result4 = try repl.step("x");
    if (result4 == .report) {
        defer testing.allocator.free(result4.report);
    } else {
        try testing.expect(false);
    }

    // Evaluate y. This should fail because `y` is not in scope.
    const result5 = try repl.step("y");
    if (result5 == .report) {
        defer testing.allocator.free(result5.report);
    } else {
        try testing.expect(false);
    }
}

test "Repl - build full source with redefinitions" {
    var repl = try Repl.init(testing.allocator);
    defer repl.deinit();

    // Add definitions manually to test source building
    try repl.past_defs.append(.{
        .source = try testing.allocator.dupe(u8, "x = 5"),
        .kind = .{ .assignment = try testing.allocator.dupe(u8, "x") },
    });

    try repl.past_defs.append(.{
        .source = try testing.allocator.dupe(u8, "y = x + 1"),
        .kind = .{ .assignment = try testing.allocator.dupe(u8, "y") },
    });

    try repl.past_defs.append(.{
        .source = try testing.allocator.dupe(u8, "x = 6"),
        .kind = .{ .assignment = try testing.allocator.dupe(u8, "x") },
    });

    // Build full source for evaluating y
    const full_source = try repl.buildFullSource("y");
    defer testing.allocator.free(full_source);

    const expected =
        \\x = 5
        \\y = x + 1
        \\x = 6
        \\y
    ;
    try testing.expectEqualStrings(expected, full_source);
}

test "Repl - past def ordering" {
    var repl = try Repl.init(testing.allocator);
    defer repl.deinit();

    // Manually add definitions to test ordering
    try repl.past_defs.append(.{
        .source = try testing.allocator.dupe(u8, "x = 1"),
        .kind = .{ .assignment = try testing.allocator.dupe(u8, "x") },
    });

    try repl.past_defs.append(.{
        .source = try testing.allocator.dupe(u8, "x = 2"),
        .kind = .{ .assignment = try testing.allocator.dupe(u8, "x") },
    });

    try repl.past_defs.append(.{
        .source = try testing.allocator.dupe(u8, "x = 3"),
        .kind = .{ .assignment = try testing.allocator.dupe(u8, "x") },
    });

    // Verify all definitions are kept in order
    try testing.expect(repl.past_defs.items.len == 3);
    try testing.expectEqualStrings("x = 1", repl.past_defs.items[0].source);
    try testing.expectEqualStrings("x = 2", repl.past_defs.items[1].source);
    try testing.expectEqualStrings("x = 3", repl.past_defs.items[2].source);

    // Build source shows all definitions
    const full_source = try repl.buildFullSource("x");
    defer testing.allocator.free(full_source);

    const expected =
        \\x = 1
        \\x = 2
        \\x = 3
        \\x
    ;
    try testing.expectEqualStrings(expected, full_source);
}

test "Repl - minimal interpreter integration" {
    const allocator = testing.allocator;

    // Step 1: Create module environment
    const source = "42";
    var module_env = try ModuleEnv.init(allocator, source);
    defer module_env.deinit();

    // Step 2: Parse as expression
    var parse_ast = try parse.parseExpr(&module_env);
    defer parse_ast.deinit(allocator);

    // Empty scratch space (required before canonicalization)
    parse_ast.store.emptyScratch();

    // Step 3: Create CIR
    const cir = &module_env; // CIR is now just ModuleEnv
    try cir.initCIRFields(allocator, "test");

    // Step 4: Canonicalize
    var can = try canonicalize.init(cir, &parse_ast, null);
    defer can.deinit();

    const expr_idx: parse.AST.Expr.Idx = @enumFromInt(parse_ast.root_node_idx);
    const canonical_expr_idx = try can.canonicalizeExpr(expr_idx) orelse {
        return error.CanonicalizeError;
    };

    // Step 5: Type check
    var checker = try check_types.init(allocator, &module_env.types, cir, &.{}, &cir.store.regions);
    defer checker.deinit();

    _ = try checker.checkExpr(canonical_expr_idx.get_idx());

    // Step 6: Create evaluation stack
    var eval_stack = try stack.Stack.initCapacity(allocator, 1024);
    defer eval_stack.deinit();

    // Step 7: Create layout cache
    var layout_cache = try layout_store.Store.init(&module_env, &module_env.types);
    defer layout_cache.deinit();

    // Step 8: Create interpreter
    var interpreter = try eval.Interpreter.init(allocator, cir, &eval_stack, &layout_cache, &module_env.types);
    defer interpreter.deinit();

    // Step 9: Evaluate
    const result = try interpreter.eval(canonical_expr_idx.get_idx());

    // Step 10: Verify result
    try testing.expect(result.layout.tag == .scalar);
    try testing.expect(result.layout.data.scalar.tag == .int);

    // Read the value back
    const precision = result.layout.data.scalar.data.int;
    const value: i128 = eval.readIntFromMemory(@ptrCast(result.ptr.?), precision);

    try testing.expectEqual(@as(i128, 42), value);
}
