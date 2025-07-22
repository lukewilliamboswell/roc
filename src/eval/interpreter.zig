//! Evaluates canonicalized Roc expressions
//!
//! This module implements a stack-based interpreter for evaluating Roc expressions.
//! Values are pushed directly onto a stack, and operations pop their operands and
//! push results. No heap allocations are used for intermediate results.
//!
//! ## Architecture
//!
//! ### Work Queue System
//! Uses an iterative work queue (LIFO stack) to evaluate complex expressions without
//! recursion. This avoids stack overflow issues and provides better debugging visibility.
//! Work items are pushed in reverse order to achieve natural left-to-right evaluation.
//!
//! ### Memory Management
//! - **Stack Memory**: All values stored in a single stack for automatic cleanup
//! - **Layout Stack**: Tracks type information parallel to value stack
//! - **Zero Heap Allocation**: All intermediate results are stack-based for performance
//!
//! ### Function Calling Convention
//! 1. **Allocate Return Space**: Pre-allocate correctly-sized/aligned return space
//! 2. **Push Arguments**: Function and arguments pushed onto stack
//! 3. **Execute Function**: Body evaluated with parameter bindings active
//! 4. **Copy Result**: Function result copied to pre-allocated return space
//! 5. **Cleanup Frame**: Function and arguments removed, return value moved to base

const std = @import("std");
const base = @import("base");
const CIR = @import("../check/canonicalize/CIR.zig");
const types = @import("types");
const layout = @import("../layout/layout.zig");
const build_options = @import("build_options");
const layout_store = @import("../layout/store.zig");
const stack = @import("stack.zig");
const collections = @import("collections");

const SExprTree = base.SExprTree;
const types_store = types.store;
const target = base.target;
const Layout = layout.Layout;
const target_usize = base.target.Target.native.target_usize;

/// Debug configuration set at build time using flag `zig build test -Dtrace-eval`
///
/// Used in conjunction with tracing in a single test e.g.
///
/// ```zig
/// interpreter.startTrace("<name of my trace>", std.io.getStdErr().writer().any());
/// defer interpreter.endTrace();
/// ```
///
const DEBUG_ENABLED = build_options.trace_eval;

/// Errors that can occur during expression evaluation
pub const EvalError = error{
    LayoutError,
    OutOfMemory,
    Crash,
    StackOverflow,
    InvalidBranchNode,
    TypeMismatch,
    ArityMismatch,
    ZeroSizedType,
    TypeContainedMismatch,
    InvalidRecordExtension,
    BugUnboxedFlexVar,
    DivisionByZero,
    InvalidStackState,
    NoCapturesProvided,
    CaptureBindingFailed,
    PatternNotFound,
    GlobalDefinitionNotSupported,
};

// Work item for the iterative evaluation stack
const WorkKind = enum {
    w_eval_expr,
    w_binop_add,
    w_binop_sub,
    w_binop_mul,
    w_binop_div,
    w_binop_eq,
    w_binop_ne,
    w_binop_gt,
    w_binop_lt,
    w_binop_ge,
    w_binop_le,
    w_unary_minus,
    w_if_check_condition,
    /// Function call step 1 -- Allocate space for return value
    w_func_alloc_return_space,
    /// Function call step 2 -- Push call frame marker with function position
    w_func_push_call_frame,
    /// Function call step 3 -- Orchestrate function call
    w_func_call_function,
    /// Function call step 4 -- Bind arguments to parameters
    w_func_bind_parameters,
    /// Function call step 5 -- Evaluate lambda body
    w_func_eval_function_body,
    /// Function call step 6 -- Copy function result to return space
    w_func_copy_result_to_return_space,
    /// Function call step 7 -- Clean up bindings
    w_func_cleanup_function,

    fn toStr(self: WorkKind) []const u8 {
        return switch (self) {
            .w_eval_expr => "evaluate expression",
            .w_binop_add => "calculate addition",
            .w_binop_sub => "calculate subtraction",
            .w_binop_mul => "calculate multiplication",
            .w_binop_div => "calculate division",
            .w_binop_eq => "calculate equal",
            .w_binop_ne => "calculate not equal",
            .w_binop_gt => "calculate greater than",
            .w_binop_lt => "calculate less than",
            .w_binop_ge => "calculate greater than or equal",
            .w_binop_le => "calculate less than or equal",
            .w_unary_minus => "calculate unary minus",
            .w_if_check_condition => "check if-else condition",
            .w_func_alloc_return_space => "allocate lambda return space",
            .w_func_push_call_frame => "push lambda call frame",
            .w_func_call_function => "call lambda",
            .w_func_bind_parameters => "bind lambda parameters",
            .w_func_eval_function_body => "evaluate lambda body",
            .w_func_copy_result_to_return_space => "copy result to lambda return space",
            .w_func_cleanup_function => "cleanup lambda",
        };
    }
};

/// A unit of work to be processed during iterative evaluation.
///
/// The interpreter uses a work queue (LIFO stack) to break down complex
/// expressions into smaller, manageable steps. Each WorkItem represents
/// one step in the evaluation process.
///
/// # Work Queue Pattern
/// Items are pushed in reverse order since the work stack is LIFO:
/// - Last pushed item = first executed
/// - This allows natural left-to-right evaluation order
///
/// # Examples
/// For `2 + 3`, the work items would be:
/// 1. `eval_expr` - Evaluate `3` (pushed first, executed last)
/// 2. `eval_expr` - Evaluate `2` (pushed second, executed first)
/// 3. `binop_add` - Add the two values together
pub const WorkItem = struct {
    /// The type of work to be performed
    kind: WorkKind,
    /// The expression index this work item operates on
    expr_idx: CIR.Expr.Idx,
};

/// Data for conditional branch evaluation in if-expressions.
///
/// Used internally by the interpreter to track condition-body pairs
/// during if-expression evaluation. Each branch represents one
/// `if condition then body` clause.
const BranchData = struct {
    /// Expression index for the branch condition (must evaluate to Bool)
    cond: CIR.Expr.Idx,
    /// Expression index for the branch body (evaluated if condition is true)
    body: CIR.Expr.Idx,
};

/// Simple closure representation for lambda expressions.
///
/// Represents a lambda function in its simplest form without variable capture
/// from enclosing scopes. Contains only the essential information needed to
/// execute a function call: the body expression and parameter patterns.
///
/// # Current Limitations
/// - **No Variable Capture**: Cannot access variables from enclosing scopes
/// - **No Recursive References**: Cannot reference itself by name
/// - **Simple Parameter Binding**: Uses linear pattern matching only
///
/// # Memory Layout
/// Stored directly on the interpreter's stack as a simple struct. The closure
/// layout is tracked in the layout cache with tag `.closure`.
///
/// # Future Phases
/// Later implementations will extend this to `FullClosure` with:
/// - Captured variable environment
/// - Support for recursive lambdas
/// - More complex parameter patterns
///
/// # Usage
/// Created during `e_lambda` evaluation and consumed during function calls.
/// The `body_expr_idx` is evaluated when the closure is called, with arguments
/// bound to the patterns specified by `args_pattern_span`.
/// A captured binding represents a variable from an outer scope that's been captured by a closure
// Removed CapturedBinding - no longer needed with direct capture storage

/// Environment of captured variables for a closure
// Simplified: For closure conversion, we don't need complex environment chains
// Captures will be passed as an extra parameter (a record) to the function

// /// Entry in the captured environments registry
// const CapturedEnvironmentEntry = struct {
//     position: usize,
//     env: *CapturedEnvironment,
// };

/// Closure structure that stores captured values directly
pub const Closure = struct {
    body_expr_idx: CIR.Expr.Idx, // What expression to execute
    args_pattern_span: CIR.Pattern.Span, // Parameters to bind
    captures_count: u32, // Number of captured variables
    captures_size: u32, // Total size of captured data in bytes

    // Memory layout:
    // [body_expr_idx: u32]
    // [args_pattern_span.offset: u32]
    // [args_pattern_span.len: u32]
    // [captures_count: u32]
    // [captures_size: u32]
    // If captures_count > 0:
    //   For each capture:
    //     [pattern_idx: u32]
    //     [value_size: u32]
    //     [value_data: ...]  (aligned to 8 bytes)

    pub const HEADER_SIZE: u32 = 20; // 5 * 4 bytes

    pub fn write(memory: []u8, body_expr_idx: CIR.Expr.Idx, args_pattern_span: CIR.Pattern.Span, captures_count: u32, captures_size: u32) void {
        var offset: u32 = 0;

        // Write body expression index
        std.mem.writeInt(u32, memory[offset..][0..4], @intFromEnum(body_expr_idx), .little);
        offset += 4;

        // Write args pattern span
        std.mem.writeInt(u32, memory[offset..][0..4], args_pattern_span.span.start, .little);
        offset += 4;
        std.mem.writeInt(u32, memory[offset..][0..4], args_pattern_span.span.len, .little);
        offset += 4;

        // Write captures count
        std.mem.writeInt(u32, memory[offset..][0..4], captures_count, .little);
        offset += 4;

        // Write captures size
        std.mem.writeInt(u32, memory[offset..][0..4], captures_size, .little);
    }

    pub fn read(memory: []const u8) Closure {
        var offset: u32 = 0;

        // Read body expression index
        const body_expr_raw = std.mem.readInt(u32, memory[offset..][0..4], .little);
        const body_expr_idx: CIR.Expr.Idx = @enumFromInt(body_expr_raw);
        offset += 4;

        // Read args pattern span
        const pattern_start = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;
        const pattern_len = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;

        // Read captures count
        const captures_count = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;

        // Read captures size
        const captures_size = std.mem.readInt(u32, memory[offset..][0..4], .little);

        return Closure{
            .body_expr_idx = body_expr_idx,
            .args_pattern_span = .{ .span = .{ .start = pattern_start, .len = pattern_len } },
            .captures_count = captures_count,
            .captures_size = captures_size,
        };
    }
};

/// Call frame marker that stores function position and metadata during calls
/// This eliminates the need to calculate closure positions dynamically
pub const CallFrame = struct {
    function_pos: u32, // Stack position where the function closure is stored
    function_layout: layout.Layout, // Layout of the function closure
    return_layout_idx: u32, // Index in layout_stack of the return value layout
    arg_count: u32, // Number of arguments in this call

    /// Write call frame to memory in a serialized format
    pub fn write(self: *const CallFrame, memory: []u8) void {
        var offset: u32 = 0;

        // Write function_pos
        std.mem.writeInt(u32, memory[offset..][0..4], self.function_pos, .little);
        offset += 4;

        // Write function_layout (simplified - store tag)
        std.mem.writeInt(u32, memory[offset..][0..4], @intFromEnum(self.function_layout.tag), .little);
        offset += 4;

        // Write return_layout_idx
        std.mem.writeInt(u32, memory[offset..][0..4], self.return_layout_idx, .little);
        offset += 4;

        // Write arg_count
        std.mem.writeInt(u32, memory[offset..][0..4], self.arg_count, .little);
        offset += 4;
    }

    /// Read call frame from memory
    pub fn read(memory: []const u8) CallFrame {
        var offset: u32 = 0;

        const function_pos = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;

        const layout_tag_raw = std.mem.readInt(u32, memory[offset..][0..4], .little);
        const layout_tag: layout.LayoutTag = @enumFromInt(layout_tag_raw);
        offset += 4;

        const return_layout_idx = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;

        const arg_count = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;

        // Create a basic layout - for closure, we need env_size
        const function_layout = switch (layout_tag) {
            .closure => layout.Layout{
                .tag = .closure,
                .data = .{ .closure = .{ .env_size = 0 } }, // Will be filled properly when needed
            },
            else => layout.Layout{
                .tag = layout_tag,
                .data = undefined, // Basic layout without specific data
            },
        };

        return CallFrame{
            .function_pos = function_pos,
            .function_layout = function_layout,
            .return_layout_idx = return_layout_idx,
            .arg_count = arg_count,
        };
    }

    /// Calculate the size needed to store this call frame
    pub fn size() u32 {
        return @sizeOf(u32) + // function_pos
            @sizeOf(u32) + // function_layout.tag (simplified)
            @sizeOf(u32) + // return_layout_idx
            @sizeOf(u32); // arg_count
    }
};

/// - **No Heap Allocation**: Values are stack-only for performance and safety
pub const Interpreter = struct {
    /// Memory allocator for dynamic data structures
    allocator: std.mem.Allocator,
    /// Canonicalized Intermediate Representation containing expressions to evaluate
    cir: *const CIR,
    /// Stack memory for storing expression values during evaluation
    stack_memory: *stack.Stack,
    /// Cache for type layout information and size calculations
    layout_cache: *layout_store.Store,
    /// Type information store from the type checker
    type_store: *types_store.Store,
    /// Work queue for iterative expression evaluation (LIFO stack)
    work_stack: std.ArrayList(WorkItem),
    /// Parallel stack tracking type layouts of values in stack_memory
    layout_stack: std.ArrayList(layout.Layout),

    // Debug tracing state
    /// Indentation level for nested debug output
    trace_indent: u32,
    /// Writer interface for trace output (null when no trace active)
    trace_writer: ?std.io.AnyWriter,

    pub fn init(
        allocator: std.mem.Allocator,
        cir: *CIR,
        stack_memory: *stack.Stack,
        layout_cache: *layout_store.Store,
        type_store: *types_store.Store,
    ) !Interpreter {
        return Interpreter{
            .allocator = allocator,
            .cir = cir,
            .stack_memory = stack_memory,
            .layout_cache = layout_cache,
            .type_store = type_store,
            .work_stack = try std.ArrayList(WorkItem).initCapacity(allocator, 128),
            .layout_stack = try std.ArrayList(layout.Layout).initCapacity(allocator, 128),
            .trace_indent = 0,
            .trace_writer = null,
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.work_stack.deinit();
        self.layout_stack.deinit();
    }

    /// Evaluates a CIR expression and returns the result.
    ///
    /// This is the main entry point for expression evaluation. Uses an iterative
    /// work queue approach to evaluate complex expressions without recursion.
    pub fn eval(self: *Interpreter, expr_idx: CIR.Expr.Idx) EvalError!StackValue {
        // Ensure work_stack and layout_stack are empty before we start. (stack_memory might not be, and that's fine!)
        std.debug.assert(self.work_stack.items.len == 0);
        std.debug.assert(self.layout_stack.items.len == 0);
        errdefer self.layout_stack.clearRetainingCapacity();

        // We'll calculate the result pointer at the end based on the final layout

        self.traceInfo("══ EXPRESSION ══", .{});
        self.traceExpression(expr_idx);

        self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = expr_idx });

        // Main evaluation loop
        while (self.take_work()) |work| {
            switch (work.kind) {
                .w_eval_expr => try self.evalExpr(work.expr_idx),
                .w_binop_add, .w_binop_sub, .w_binop_mul, .w_binop_div, .w_binop_eq, .w_binop_ne, .w_binop_gt, .w_binop_lt, .w_binop_ge, .w_binop_le => {
                    try self.completeBinop(work.kind);
                },
                .w_unary_minus => {
                    try self.completeUnaryMinus();
                },
                .w_if_check_condition => {
                    // The expr_idx encodes both the if expression and the branch index
                    // Lower 16 bits: if expression index
                    // Upper 16 bits: branch index
                    const if_expr_idx: CIR.Expr.Idx = @enumFromInt(@intFromEnum(work.expr_idx) & 0xFFFF);
                    const branch_index: u16 = @intCast((@intFromEnum(work.expr_idx) >> 16) & 0xFFFF);
                    try self.checkIfCondition(if_expr_idx, branch_index);
                },

                // Function call work items

                .w_func_alloc_return_space => try self.handleAllocReturnSpace(work.expr_idx),
                .w_func_push_call_frame => try self.handlePushCallFrame(work.expr_idx),
                .w_func_call_function => try self.handleCallFunction(work.expr_idx),
                .w_func_bind_parameters => try self.handleBindParameters(work.expr_idx),
                .w_func_eval_function_body => try self.handleEvalFunctionBody(work.expr_idx),
                .w_func_copy_result_to_return_space => try self.handleCopyResultToReturnSpace(work.expr_idx),
                .w_func_cleanup_function => try self.handleCleanupFunction(work.expr_idx),
            }
        }

        // Pop the final layout - should be the only thing left on the layout stack
        const final_layout = self.layout_stack.pop() orelse return error.InvalidStackState;

        // Debug: check what's left on the layout stack
        if (self.layout_stack.items.len > 0) {
            self.traceWarn("Layout stack not empty! {} items remaining:", .{self.layout_stack.items.len});
            for (self.layout_stack.items, 0..) |item_layout, i| {
                self.traceInfo("[{}]: tag = {s}", .{ i, @tagName(item_layout.tag) });
            }
        }

        // Ensure both stacks are empty at the end - if not, it's a bug!
        std.debug.assert(self.work_stack.items.len == 0);
        std.debug.assert(self.layout_stack.items.len == 0);

        // With proper calling convention, after cleanup the result is at the start of the stack
        const result_ptr = @as([*]u8, @ptrCast(self.stack_memory.start));

        self.traceInfo("Final result at stack pos 0 (calling convention)", .{});

        return StackValue{
            .layout = final_layout,
            .ptr = @as(*anyopaque, @ptrCast(result_ptr)),
        };
    }

    fn schedule_work(self: *Interpreter, work: WorkItem) void {
        if (self.trace_writer) |writer| {
            const expr = self.cir.store.getExpr(work.expr_idx);
            const region = self.cir.store.getExprRegion(work.expr_idx);
            const regionInfo = self.cir.calcRegionInfo(region);
            self.printTraceIndent();
            writer.print(
                "🏗️  scheduling {s} for ({s} @{}.{}-{}.{})\n",
                .{
                    work.kind.toStr(),
                    @tagName(expr),
                    regionInfo.start_line_idx,
                    regionInfo.start_col_idx,
                    regionInfo.end_line_idx,
                    regionInfo.end_col_idx,
                },
            ) catch {};
        }

        self.work_stack.append(work) catch {};
    }

    fn take_work(self: *Interpreter) ?WorkItem {
        const maybe_work = self.work_stack.pop();
        if (self.trace_writer) |writer| {
            if (maybe_work) |work| {
                const expr = self.cir.store.getExpr(work.expr_idx);
                const region = self.cir.store.getExprRegion(work.expr_idx);
                const regionInfo = self.cir.calcRegionInfo(region);
                self.printTraceIndent();
                writer.print(
                    "🏗️  starting {s} for ({s} @{}.{}-{}.{})\n",
                    .{
                        work.kind.toStr(),
                        @tagName(expr),
                        regionInfo.start_line_idx,
                        regionInfo.start_col_idx,
                        regionInfo.end_line_idx,
                        regionInfo.end_col_idx,
                    },
                ) catch {};
            }
        }
        return maybe_work;
    }

    /// Evaluates a single CIR expression, pushing the result onto the stack.
    ///
    /// # Stack Effects
    /// - Pushes exactly one value onto `stack_memory`
    /// - Pushes corresponding layout onto `layout_stack`
    /// - May push additional work items for complex expressions
    ///
    /// # Error Handling
    /// Malformed expressions result in runtime error placeholders rather
    /// than evaluation failure.
    fn evalExpr(self: *Interpreter, expr_idx: CIR.Expr.Idx) EvalError!void {
        const expr = self.cir.store.getExpr(expr_idx);

        self.traceEnter("evalExpr {s}", .{@tagName(expr)});
        defer self.traceExit("", .{});

        // Check for runtime errors first
        switch (expr) {
            .e_runtime_error => return error.Crash,
            else => {},
        }

        // Get the type variable for this expression
        const expr_var: types.Var = @enumFromInt(@intFromEnum(expr_idx));

        // Get the real layout from the type checker
        const layout_idx = self.layout_cache.addTypeVar(expr_var) catch |err| switch (err) {
            error.ZeroSizedType => return error.ZeroSizedType,
            error.BugUnboxedRigidVar => return error.BugUnboxedFlexVar,
            else => |e| return e,
        };
        const expr_layout = self.layout_cache.getLayout(layout_idx);

        // Calculate size and alignment
        const size = self.layout_cache.layoutSize(expr_layout);
        const alignment = expr_layout.alignment(target.TargetUsize.native);

        // Handle different expression types
        switch (expr) {
            // Runtime errors are handled at the beginning
            .e_runtime_error => unreachable,

            // Numeric literals - push directly to stack
            .e_int => |int_lit| {
                const result_ptr = (try self.pushStackValue(expr_layout)).?;

                if (expr_layout.tag == .scalar and expr_layout.data.scalar.tag == .int) {
                    const precision = expr_layout.data.scalar.data.int;
                    writeIntToMemory(@ptrCast(result_ptr), int_lit.value.toI128(), precision);
                    self.traceInfo("Pushed integer literal {d}", .{int_lit.value.toI128()});
                } else {
                    return error.LayoutError;
                }
            },

            .e_frac_f64 => |float_lit| {
                const ptr = self.stack_memory.alloca(size, alignment) catch |err| switch (err) {
                    error.StackOverflow => return error.StackOverflow,
                };

                const typed_ptr = @as(*f64, @ptrCast(@alignCast(ptr)));
                typed_ptr.* = float_lit.value;

                self.traceEnter("PUSH e_frac_f64", .{});
                try self.layout_stack.append(expr_layout);
            },

            // Zero-argument tags (e.g., True, False)
            .e_zero_argument_tag => |tag| {
                const ptr = self.stack_memory.alloca(size, alignment) catch |err| switch (err) {
                    error.StackOverflow => return error.StackOverflow,
                };

                const tag_ptr = @as(*u8, @ptrCast(@alignCast(ptr)));
                const tag_name = self.cir.env.idents.getText(tag.name);
                if (std.mem.eql(u8, tag_name, "True")) {
                    tag_ptr.* = 1;
                } else if (std.mem.eql(u8, tag_name, "False")) {
                    tag_ptr.* = 0;
                } else {
                    tag_ptr.* = 0; // TODO: get actual tag discriminant
                }

                try self.layout_stack.append(expr_layout);
            },

            // Empty record
            .e_empty_record => {
                // Empty record has no bytes
                try self.layout_stack.append(expr_layout);
            },

            // Empty list
            .e_empty_list => {
                // Empty list has no bytes
                try self.layout_stack.append(expr_layout);
            },

            // Binary operations
            .e_binop => |binop| {
                // Push work to complete the binop after operands are evaluated
                const binop_kind: WorkKind = switch (binop.op) {
                    .add => .w_binop_add,
                    .sub => .w_binop_sub,
                    .mul => .w_binop_mul,
                    .div => .w_binop_div,
                    .eq => .w_binop_eq,
                    .ne => .w_binop_ne,
                    .gt => .w_binop_gt,
                    .lt => .w_binop_lt,
                    .ge => .w_binop_ge,
                    .le => .w_binop_le,
                    else => return error.Crash,
                };

                self.schedule_work(WorkItem{ .kind = binop_kind, .expr_idx = expr_idx });

                // Push operands in reverse order (right, then left)
                self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = binop.rhs });
                self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = binop.lhs });
            },

            // If expressions
            .e_if => |if_expr| {
                if (if_expr.branches.span.len > 0) {

                    // Check if condition is true
                    self.schedule_work(WorkItem{ .kind = .w_if_check_condition, .expr_idx = expr_idx });

                    // Push work to evaluate the first condition
                    const branches = self.cir.store.sliceIfBranches(if_expr.branches);
                    const branch = self.cir.store.getIfBranch(branches[0]);

                    self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = branch.cond });
                } else {
                    // No branches, evaluate final_else directly
                    self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = if_expr.final_else });
                }
            },

            // Pattern lookup
            .e_lookup_local => |lookup| {
                self.traceInfo("evalExpr e_lookup_local pattern_idx={}", .{@intFromEnum(lookup.pattern_idx)});
                self.tracePattern(lookup.pattern_idx);

                // First, check parameter bindings (most recent function call)

                // If not found in parameters, fall back to global definitions lookup
                const defs = self.cir.store.sliceDefs(self.cir.all_defs);
                for (defs) |def_idx| {
                    const def = self.cir.store.getDef(def_idx);
                    if (@intFromEnum(def.pattern) == @intFromEnum(lookup.pattern_idx)) {
                        // Found the definition, evaluate its expression
                        try self.work_stack.append(.{
                            .kind = .w_eval_expr,
                            .expr_idx = def.expr,
                        });
                        return;
                    }
                }

                return error.LayoutError; // Pattern not found
            },

            // Nominal expressions
            .e_nominal => |nominal| {
                // Evaluate the backing expression
                try self.work_stack.append(.{
                    .kind = .w_eval_expr,
                    .expr_idx = nominal.backing_expr,
                });
            },

            // Tags with arguments
            .e_tag => |tag| {
                const ptr = self.stack_memory.alloca(size, alignment) catch |err| switch (err) {
                    error.StackOverflow => return error.StackOverflow,
                };

                // For now, handle boolean tags (True/False) as u8
                const tag_ptr = @as(*u8, @ptrCast(@alignCast(ptr)));
                const tag_name = self.cir.env.idents.getText(tag.name);
                if (std.mem.eql(u8, tag_name, "True")) {
                    tag_ptr.* = 1;
                } else if (std.mem.eql(u8, tag_name, "False")) {
                    tag_ptr.* = 0;
                } else {
                    tag_ptr.* = 0; // TODO: get actual tag discriminant
                }

                self.traceEnter("PUSH e_tag", .{});
                try self.layout_stack.append(expr_layout);
            },

            .e_call => |call| {

                // Get function and arguments from the call
                const all_exprs = self.cir.store.sliceExpr(call.args);

                if (all_exprs.len == 0) {
                    return error.LayoutError; // No function to call
                }

                const function_expr = all_exprs[0];
                const arg_exprs = all_exprs[1..];

                // Push work items in reverse order (LIFO stack) for proper calling convention:

                // Step 3 - Orchestrate the call (after function and args are evaluated)
                self.schedule_work(WorkItem{ .kind = .w_func_call_function, .expr_idx = expr_idx });

                // 2. Evaluate arguments in reverse order (right to left)
                var i = arg_exprs.len;
                while (i > 0) {
                    i -= 1;
                    self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = arg_exprs[i] });
                }

                // Step 3 - call the function
                self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = function_expr });

                // Step 2 - push call frame marker to track new function context

                // Step 1 - allocate return value space (landing pad) first
                self.schedule_work(WorkItem{ .kind = .w_func_alloc_return_space, .expr_idx = expr_idx });
            },

            // Unary minus operation
            .e_unary_minus => |unary| {
                // Push work to complete unary minus after operand is evaluated
                try self.work_stack.append(.{
                    .kind = .w_unary_minus,
                    .expr_idx = expr_idx,
                });

                // Evaluate the operand expression
                try self.work_stack.append(.{
                    .kind = .w_eval_expr,
                    .expr_idx = unary.expr,
                });
            },

            // Not yet implemented
            .e_str, .e_str_segment, .e_list, .e_tuple, .e_record, .e_dot_access, .e_block, .e_lookup_external, .e_match, .e_frac_dec, .e_dec_small, .e_crash, .e_dbg, .e_expect, .e_ellipsis => {
                return error.LayoutError;
            },

            .e_lambda => |lambda_expr| {

                // We need the parameters binded before here... so we can use the correct values

                // Calculate size needed for captures first, before creating layout
                const captures_size: u32 = 0;
                const captures_idxs = self.cir.store.sliceCaptures(lambda_expr.captures);
                const captures_count: u32 = @intCast(captures_idxs.len);

                // Calculate total size for all captured values
                // for (captures_idxs) |captured_var_idx| {
                //     const captured_var = self.cir.store.getCapture(captured_var_idx);

                //     // Add space for pattern_idx and value_size
                //     captures_size += 8; // 4 bytes each

                //     // Find the captured variable's current value and layout
                //     // const capture_result = self.lookupVariableForCapture(captured_var.pattern_idx) catch {
                //     //     self.traceError("Failed to find variable for capture: pattern_idx={}", .{@intFromEnum(captured_var.pattern_idx)});
                //     //     return error.PatternNotFound;
                //     // };

                //     const value_size = self.layout_cache.layoutSize(capture_result.layout);
                //     const capture_alignment = capture_result.layout.alignment(target.Target.native);

                //     // Align each captured value
                //     captures_size = std.mem.alignForward(u32, captures_size + value_size, capture_alignment);
                // }

                const closure_layout = layout.Layout{
                    .tag = .closure,
                    .data = .{ .closure = .{ .env_size = @intCast(captures_size) } }, // env_size is just the captures
                };

                // Push layout first
                self.traceEnter("PUSH closure FOR call_expr_idx={}", .{@intFromEnum(expr_idx)});
                try self.layout_stack.append(closure_layout);

                // Create closure layout with actual size
                const total_closure_size = Closure.HEADER_SIZE + captures_size;
                const closure_alignment = closure_layout.alignment(target_usize);
                const closure_ptr = try self.stack_memory.alloca(@intCast(total_closure_size), closure_alignment);

                // Write closure header
                const memory = @as([*]u8, @ptrCast(closure_ptr));
                Closure.write(
                    memory[0..Closure.HEADER_SIZE],
                    lambda_expr.body,
                    lambda_expr.args,
                    captures_count,
                    captures_size,
                );

                // Write captured values
                // var offset: u32 = Closure.HEADER_SIZE;

                for (captures_idxs) |_| {
                    // const captured_var = self.cir.store.getCapture(captured_var_idx);

                    // Look up the captured variable
                    // const capture_result = self.lookupVariableForCapture(captured_var.pattern_idx) catch {
                    //     self.traceError("Failed to find variable for capture: pattern_idx={}", .{@intFromEnum(captured_var.pattern_idx)});
                    //     return error.PatternNotFound;
                    // };

                    // Write pattern_idx
                    // std.mem.writeInt(u32, memory[offset..][0..4], @intFromEnum(captured_var.pattern_idx), .little);
                    // offset += 4;

                    // // Write value_size
                    // const value_size = self.layout_cache.layoutSize(capture_result.layout);
                    // std.mem.writeInt(u32, memory[offset..][0..4], value_size, .little);
                    // offset += 4;

                    // // Copy the value
                    // const src_ptr = @as([*]const u8, @ptrCast(capture_result.ptr));
                    // @memcpy(memory[offset..][0..value_size], src_ptr[0..value_size]);

                    // // Align to 8 bytes for next capture
                    // offset = std.mem.alignForward(u32, offset + value_size, 8);

                    // if (DEBUG_ENABLED) {
                    //     self.traceInfo("Captured variable: pattern_idx={}, size={}", .{ @intFromEnum(captured_var.pattern_idx), value_size });
                    // }
                }
            },
        }
    }

    fn completeBinop(self: *Interpreter, kind: WorkKind) EvalError!void {
        const lhs = try self.popStackValue();
        const rhs = try self.popStackValue();

        // For now, only support integer operations
        if (lhs.layout.tag != .scalar or rhs.layout.tag != .scalar) {
            return error.LayoutError;
        }

        if (lhs.layout.data.scalar.tag != .int or rhs.layout.data.scalar.tag != .int) {
            return error.LayoutError;
        }

        // Read the values
        const lhs_val = readIntFromMemory(@ptrCast(rhs.ptr.?), lhs.layout.data.scalar.data.int);
        const rhs_val = readIntFromMemory(@ptrCast(lhs.ptr.?), rhs.layout.data.scalar.data.int);

        // Debug: Values read from memory
        self.tracePrint("completeBinop {s}", .{@tagName(kind)});
        self.traceInfo("\tRead values - left = {}, right = {}", .{ lhs_val, rhs_val });
        self.traceInfo("\tLeft layout: tag={}, precision={}", .{ lhs.layout.tag, lhs.layout.data.scalar.data.int });
        self.traceInfo("\tRight layout: tag={}, precision={}", .{ rhs.layout.tag, rhs.layout.data.scalar.data.int });

        // Determine result layout
        const result_layout = switch (kind) {
            .w_binop_add, .w_binop_sub, .w_binop_mul, .w_binop_div => lhs.layout, // Numeric result
            .w_binop_eq, .w_binop_ne, .w_binop_gt, .w_binop_lt, .w_binop_ge, .w_binop_le => blk: {
                // Boolean result
                const bool_layout = layout.Layout{
                    .tag = .scalar,
                    .data = .{ .scalar = .{
                        .tag = .int,
                        .data = .{ .int = .u8 },
                    } },
                };
                break :blk bool_layout;
            },
            else => unreachable,
        };

        const result_ptr = (try self.pushStackValue(result_layout)).?;

        const lhs_precision: types.Num.Int.Precision = lhs.layout.data.scalar.data.int;

        // Perform the operation and write to our result_ptr
        switch (kind) {
            .w_binop_add => {
                const result_val: i128 = lhs_val + rhs_val;
                self.traceInfo("Addition operation: {} + {} = {}", .{ lhs_val, rhs_val, result_val });
                writeIntToMemory(@ptrCast(result_ptr), result_val, lhs_precision);

                {
                    // Debug: Verify what was written to memory
                    const verification = readIntFromMemory(@as([*]u8, @ptrCast(result_ptr)), lhs_precision);
                    self.traceInfo("Verification read from result memory = {}", .{verification});
                }
            },
            .w_binop_sub => {
                const result_val: i128 = lhs_val - rhs_val;
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_precision);
            },
            .w_binop_mul => {
                const result_val: i128 = lhs_val * rhs_val;
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_precision);
            },
            .w_binop_div => {
                if (rhs_val == 0) {
                    return error.DivisionByZero;
                }
                const result_val: i128 = @divTrunc(lhs_val, rhs_val);
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_precision);
            },
            .w_binop_eq => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val == rhs_val) 1 else 0;
            },
            .w_binop_ne => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val != rhs_val) 1 else 0;
            },
            .w_binop_gt => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val > rhs_val) 1 else 0;
            },
            .w_binop_lt => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val < rhs_val) 1 else 0;
            },
            .w_binop_ge => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val >= rhs_val) 1 else 0;
            },
            .w_binop_le => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val <= rhs_val) 1 else 0;
            },
            else => unreachable,
        }
    }

    fn completeUnaryMinus(self: *Interpreter) EvalError!void {
        // Pop the operand layout
        const operand_layout = self.layout_stack.pop() orelse return error.InvalidStackState;

        // For now, only support integer operations
        if (operand_layout.tag != .scalar) {
            return error.LayoutError;
        }

        const operand_scalar = operand_layout.data.scalar;
        if (operand_scalar.tag != .int) {
            return error.LayoutError;
        }

        // Calculate operand size and read the value
        const operand_size = self.layout_cache.layoutSize(operand_layout);
        const operand_ptr = @as(*anyopaque, @ptrFromInt(@intFromPtr(self.stack_memory.start) + self.stack_memory.used - operand_size));
        const operand_val = readIntFromMemory(@as([*]u8, @ptrCast(operand_ptr)), operand_scalar.data.int);

        self.traceInfo("Unary minus operation: -{} = {}", .{ operand_val, -operand_val });

        // Negate the value and write it back to the same location
        const result_val: i128 = -operand_val;
        writeIntToMemory(@as([*]u8, @ptrCast(operand_ptr)), result_val, operand_scalar.data.int);

        // Push result layout (same as operand layout)
        try self.layout_stack.append(operand_layout);
    }

    fn checkIfCondition(self: *Interpreter, expr_idx: CIR.Expr.Idx, branch_index: u16) EvalError!void {

        // Pop the condition layout
        const condition = try self.popStackValue();

        // Read the condition value
        const cond_val: *u8 = @ptrCast(condition.ptr.?);

        // Get the if expression
        const if_expr = switch (self.cir.store.getExpr(expr_idx)) {
            .e_if => |e| e,
            else => return error.InvalidBranchNode,
        };

        const branches = self.cir.store.sliceIfBranches(if_expr.branches);

        if (branch_index >= branches.len) {
            return error.InvalidBranchNode;
        }

        const branch = self.cir.store.getIfBranch(branches[branch_index]);

        if (cond_val.* == 1) {
            // Condition is true, evaluate this branch's body
            self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = branch.body });
        } else {
            // Condition is false, check if there's another branch
            if (branch_index + 1 < branches.len) {
                // Evaluate the next branch
                const next_branch_idx = branch_index + 1;
                const next_branch = self.cir.store.getIfBranch(branches[next_branch_idx]);

                // Encode branch index in upper 16 bits
                const encoded_idx: CIR.Expr.Idx = @enumFromInt(@intFromEnum(expr_idx) | (@as(u32, next_branch_idx) << 16));

                // Push work to check next condition after it's evaluated
                self.schedule_work(WorkItem{ .kind = .w_if_check_condition, .expr_idx = encoded_idx });

                // Push work to evaluate the next condition
                self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = next_branch.cond });
            } else {
                // No more branches, evaluate final_else
                self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = if_expr.final_else });
            }
        }
    }

    /// Allocates appropriately-sized and aligned memory for the function's return value
    /// before any arguments or the function itself are evaluated.
    fn handleAllocReturnSpace(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {

        // Get the type variable for the call expression (which is the return type)
        const expr_var = @as(types.Var, @enumFromInt(@intFromEnum(call_expr_idx)));

        // Get the return type layout
        const return_layout_idx = self.layout_cache.addTypeVar(expr_var) catch |err| switch (err) {
            error.ZeroSizedType => return error.ZeroSizedType,
            error.BugUnboxedRigidVar => return error.BugUnboxedFlexVar,
            else => |e| return e,
        };
        const return_layout = self.layout_cache.getLayout(return_layout_idx);

        // Allocate space for the return value
        const return_size = self.layout_cache.layoutSize(return_layout);
        const return_alignment = return_layout.alignment(target.TargetUsize.native);

        _ = self.stack_memory.alloca(return_size, return_alignment) catch |err| switch (err) {
            error.StackOverflow => return error.StackOverflow,
        };

        // Push the return layout to track the return space
        // self.traceLayout("return_space", return_layout);
        self.traceEnter("PUSH return_space FOR call_expr_idx={}", .{@intFromEnum(call_expr_idx)});
        try self.layout_stack.append(return_layout);
    }

    fn handleCallFunction(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        // if (DEBUG_ENABLED) {
        //     self.traceEnter("CALL FUNCTION (expr_idx={})", .{@intFromEnum(call_expr_idx)});
        //     self.traceStackState("call_function_entry");
        // }

        // Get the call expression to find argument count
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => {
                self.traceError("Invalid call expression type: {s}", .{@tagName(call_expr)});
                return error.LayoutError;
            },
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        // Check if we're calling a lambda directly or a closure value
        // const callee_expr = all_exprs[0]; // First expression is the function
        // const callee = self.cir.store.getExpr(callee_expr);
        // const is_direct_lambda_call = (callee == .e_lambda);

        // if (DEBUG_ENABLED) {
        //     self.traceInfo("Call type: {s} (callee is {s})", .{ if (is_direct_lambda_call) "direct lambda" else "indirect closure value", @tagName(std.meta.activeTag(callee)) });
        // }

        // Verify we have function + arguments on layout stack
        if (self.layout_stack.items.len < arg_count + 1) {
            self.traceError("Insufficient layout items: have {}, need {}", .{ self.layout_stack.items.len, arg_count + 1 });
            return error.InvalidStackState;
        }

        // Schedule call sequence work items (executed in reverse order due to LIFO stack):

        // 1. Cleanup function (executed last)
        self.schedule_work(WorkItem{ .kind = .w_func_cleanup_function, .expr_idx = call_expr_idx });

        // 2. Copy result to return space
        self.schedule_work(WorkItem{ .kind = .w_func_copy_result_to_return_space, .expr_idx = call_expr_idx });

        // 3. Evaluate function body
        self.schedule_work(WorkItem{ .kind = .w_func_eval_function_body, .expr_idx = call_expr_idx });

        // 4. Bind parameters (executed second)
        self.schedule_work(WorkItem{ .kind = .w_func_bind_parameters, .expr_idx = call_expr_idx });

        // 5. Push call frame only for direct lambda calls
        self.schedule_work(WorkItem{ .kind = .w_func_push_call_frame, .expr_idx = call_expr_idx });

        // self.traceInfo(
        //     "LAYOUT STACK in handleCallFunction(expr_idx={}): len={}",
        //     .{ @intFromEnum(call_expr_idx), self.layout_stack.items.len },
        // );
        // self.traceSuccess(
        //     "CALL FUNCTION(expr_idx={}): scheduled {} work items for {} args",
        //     .{ @intFromEnum(call_expr_idx), if (is_direct_lambda_call) @as(u32, 5) else @as(u32, 4), arg_count },
        // );
    }

    /// Push call frame marker to stack with function position and call metadata
    fn handlePushCallFrame(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.traceEnter("PUSH CALL FRAME (expr_idx={})", .{@intFromEnum(call_expr_idx)});

        // Get call information
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        // Find function on layout stack - it's right before the arguments
        const function_layout_idx = self.layout_stack.items.len - arg_count - 1;
        const function_layout = self.layout_stack.items[function_layout_idx];

        // Verify it's a closure
        if (function_layout.tag != .closure) {
            if (DEBUG_ENABLED) {
                self.traceError("Expected closure but got: {s}", .{@tagName(function_layout.tag)});
            }
            return error.LayoutError;
        }

        // Calculate function position by walking forward from stack start
        var pos: u32 = 0;

        // if (DEBUG_ENABLED) {
        //     self.traceInfo("Calculating function position by walking forward from stack start", .{});
        // }

        // Walk forward to the function position
        for (self.layout_stack.items[0..function_layout_idx]) |layout_item| {
            const size = self.layout_cache.layoutSize(layout_item);
            const alignment = layout_item.alignment(target.TargetUsize.native);

            // Align position
            pos = std.mem.alignForward(u32, pos, @intCast(alignment.toByteUnits()));

            // if (DEBUG_ENABLED) {
            //     self.traceInfo("  item[{}]: tag={s}, size={}, align={}, pos_before={}, pos_after={}", .{ i, @tagName(layout_item.tag), size, alignment, pos, pos + size });
            // }

            pos += size;
        }

        // Align to 8-byte boundary like alloca(.@"8") does during lambda creation
        pos = std.mem.alignForward(u32, pos, 8);
        const function_pos = pos;

        // if (DEBUG_ENABLED) {
        //     self.traceInfo("  🎯 FINAL function_pos={} (function at layout_idx={}) after 8-byte alignment", .{ function_pos, function_layout_idx });
        // }

        // Create call frame
        const call_frame = CallFrame{
            .function_pos = function_pos,
            .function_layout = function_layout,
            .return_layout_idx = @intCast(function_layout_idx - 1), // Return layout is before function
            .arg_count = @intCast(arg_count),
        };

        // Allocate space and write call frame to stack
        const frame_size = CallFrame.size();
        const frame_ptr = try self.stack_memory.alloca(frame_size, .@"8");
        const frame_memory = @as([*]u8, @ptrCast(frame_ptr))[0..frame_size];
        call_frame.write(frame_memory);

        // Add call frame layout to layout stack
        self.traceEnter("PUSH call_frame FOR call_expr_idx={}", .{@intFromEnum(call_expr_idx)});
        const frame_layout = layout.Layout{
            .tag = .scalar, // Simple marker layout
            .data = .{ .scalar = .{ .tag = .int, .data = .{ .int = .u32 } } },
        };
        try self.layout_stack.append(frame_layout);

        // if (DEBUG_ENABLED) {
        //     self.traceInfo("PUSHED CALL FRAME LAYOUT: expr_idx={}, layout_stack.len={}", .{ @intFromEnum(call_expr_idx), self.layout_stack.items.len });
        // }

        // if (DEBUG_ENABLED) {
        //     self.traceInfo("LAYOUT STACK after pushing call frame(expr_idx={}): len={}", .{ @intFromEnum(call_expr_idx), self.layout_stack.items.len });
        //     for (self.layout_stack.items, 0..) |lay, i| {
        //         self.traceInfo("  [{}]: tag={s}", .{ i, @tagName(lay.tag) });
        //     }
        //     self.traceSuccess("PUSH CALL FRAME(expr_idx={}): function_pos={}, arg_count={}, frame_size={}", .{ @intFromEnum(call_expr_idx), function_pos, arg_count, frame_size });
        // }

        // self.tracePrint("=== COPY RESULT TO RETURN SPACE ===\n", .{});
        // self.traceInfo("Initial stack.used = {}", .{self.stack_memory.used});
        // self.traceInfo("Layout stack size = {}", .{self.layout_stack.items.len});
        // if (DEBUG_ENABLED) {
        //     self.traceInfo("LAYOUT STACK contents at copy start:", .{});
        //     for (self.layout_stack.items, 0..) |lay, i| {
        //         self.traceInfo("  [{}]: tag={s}", .{ i, @tagName(lay.tag) });
        //     }
        // }
    }

    /// Handle capture arguments for functions that capture variables from outer scopes.
    /// Creates capture records and pushes them as hidden arguments.
    fn handleCaptureArguments(self: *Interpreter, call_expr_idx: CIR.Expr.Idx, function_layout_idx: usize) EvalError!void {
        // Get the closure pointer and read layout information directly from the closure
        const function_layout = self.layout_stack.items[function_layout_idx];

        if (function_layout.tag != .closure) {
            self.traceInfo("EARLY RETURN: Not a closure, tag={s}", .{@tagName(function_layout.tag)});
            return;
        }

        // For now, simplified implementation - just check if captures are needed
        if (function_layout.data.closure.env_size == 0) {
            if (DEBUG_ENABLED) {
                self.traceInfo("EARLY RETURN: Closure has no captures (env_size=0)", .{});
            }
            return;
        }

        if (DEBUG_ENABLED) {
            self.traceInfo("ADDING CAPTURE RECORD: env_size={}", .{function_layout.data.closure.env_size});
        }

        // Get call expression for capture info

        // Get the call expression to find the function and get capture info
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        if (all_exprs.len == 0) return;

        // Get the function expression (first argument in call.args)
        const function_expr_idx = all_exprs[0];
        const function_expr = self.cir.store.getExpr(function_expr_idx);

        // Get capture info from lambda (if it's a direct lambda call)
        const lambda_captures = switch (function_expr) {
            .e_lambda => |lambda| lambda.captures,
            else => {
                // This is calling a closure (not direct lambda)
                // We need to get capture info from the closure on the stack
                self.traceInfo("🎯 CLOSURE CALL WITH CAPTURES: env_size={}", .{function_layout.data.closure.env_size});

                // For now, create a simple capture record based on env_size
                // TODO: Store actual capture info with closure for proper implementation
                const num_captures = function_layout.data.closure.env_size;
                const capture_record_size: u32 = @intCast(num_captures * @sizeOf(usize));
                const capture_record_alignment = @as(std.mem.Alignment, @enumFromInt(@alignOf(usize)));

                const capture_record_ptr = self.stack_memory.alloca(capture_record_size, capture_record_alignment) catch |err| switch (err) {
                    error.StackOverflow => return error.StackOverflow,
                };

                // Initialize with dummy values for now - this needs proper capture value lookup
                const capture_record = @as([*]usize, @ptrCast(@alignCast(capture_record_ptr)));
                for (0..num_captures) |i| {
                    capture_record[i] = 42; // Placeholder - need actual captured values
                }

                // Push capture record layout as a scalar argument
                self.traceEnter("PUSH capture record argument FOR call_expr_idx={}", .{@intFromEnum(call_expr_idx)});
                const capture_layout = layout.Layout{
                    .tag = .scalar,
                    .data = .{ .scalar = .{ .tag = .int, .data = .{ .int = .i64 } } },
                };
                try self.layout_stack.append(capture_layout);

                // self.traceInfo("✅ CLOSURE CAPTURE RECORD PUSHED: {} vars", .{num_captures});

                return;
            },
        };

        if (lambda_captures.captured_vars.len == 0) return;

        // Create simple capture record - just store pattern indices for now
        const capture_record_size: u32 = @intCast(lambda_captures.captured_vars.len * @sizeOf(usize));
        const capture_record_alignment = @as(std.mem.Alignment, @enumFromInt(@alignOf(usize)));

        const capture_record_ptr = self.stack_memory.alloca(capture_record_size, capture_record_alignment) catch |err| switch (err) {
            error.StackOverflow => return error.StackOverflow,
        };

        // Initialize capture record with current values
        const capture_record = @as([*]usize, @ptrCast(@alignCast(capture_record_ptr)));

        for (lambda_captures.captured_vars, 0..) |captured_var, i| {
            // Look up current value of captured variable from parameter bindings
            const current_value = self.lookupCapturedVariableValue(captured_var.pattern_idx) catch {
                capture_record[i] = 0; // Default value if lookup fails
                continue;
            };
            capture_record[i] = current_value;
        }

        // Push capture record layout as a scalar argument
        self.traceEnter("PUSH capture record argument FOR call_expr_idx={}", .{@intFromEnum(call_expr_idx)});
        const capture_layout = layout.Layout{
            .tag = .scalar,
            .data = .{ .scalar = .{ .tag = .int, .data = .{ .int = .i64 } } },
        };
        try self.layout_stack.append(capture_layout);

        // self.traceInfo("✅ CAPTURE RECORD PUSHED: {} vars", .{lambda_captures.captured_vars.len});
    }

    /// Look up the current value of a captured variable from parameter bindings
    fn lookupCapturedVariableValue(self: *Interpreter, pattern_idx: CIR.Pattern.Idx) !usize {
        // Search through parameter bindings for the captured variable
        for (self.parameter_bindings.items) |binding| {
            if (binding.pattern_idx == pattern_idx) {
                // Found the binding, return the value (simplified for now)
                return @intFromPtr(binding.value_ptr);
            }
        }

        // Search through execution contexts if not found in current bindings
        if (self.current_context) |context| {
            if (context.findBinding(pattern_idx)) |binding| {
                return @intFromPtr(binding.value_ptr);
            }
        }

        return error.CaptureNotFound;
    }

    /// Binds function arguments to parameter patterns.
    fn handleBindParameters(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.traceEnter("START handleBindParameters(expr_idx={})", .{@intFromEnum(call_expr_idx)});
        defer self.traceEnter("END handleBindParameters(expr_idx={})", .{@intFromEnum(call_expr_idx)});

        // Get call information to determine if this is a direct lambda call
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself
        const callee_expr = all_exprs[0]; // First expression is the function
        const callee = self.cir.store.getExpr(callee_expr);
        const is_direct_lambda_call = (callee == .e_lambda);

        var function_pos: u32 = 0;
        var function_layout: layout.Layout = undefined;

        if (is_direct_lambda_call) {
            self.traceInfo("direct lambda call", .{});

            // Read call frame from top of stack (it was pushed by handlePushCallFrame)
            const frame_size = CallFrame.size();

            // Bounds check to prevent integer underflow
            if (self.stack_memory.used < frame_size) {
                if (DEBUG_ENABLED) {
                    self.traceError("Stack underflow: used={}, frame_size={}", .{ self.stack_memory.used, frame_size });
                }
                return error.InvalidStackState;
            }

            const frame_pos = self.stack_memory.used - frame_size;
            const frame_memory_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + frame_pos;
            const frame_memory = frame_memory_ptr[0..frame_size];
            const call_frame = CallFrame.read(frame_memory);

            function_pos = call_frame.function_pos;
            function_layout = call_frame.function_layout;
        } else {
            self.traceInfo("indirect closure call", .{});

            // For indirect calls, the closure is on the stack before the arguments
            // Stack layout: [return_space] [closure] [arg1] [arg2] ... [argN]

            // Find the closure layout in the layout stack
            const function_layout_idx = self.layout_stack.items.len - arg_count - 1;
            function_layout = self.layout_stack.items[function_layout_idx];

            // Special case: If this is a call to a closure returned from a previous function,
            // the cleanup process has moved it to position 0
            if (function_layout_idx == 1 and self.layout_stack.items[0].tag == .scalar) {
                // This is calling a returned closure - it's at position 0
                function_pos = 0;

                if (DEBUG_ENABLED) {
                    self.traceInfo("Detected call to returned closure - using position 0", .{});
                }
            } else {
                // Calculate position by walking forward from stack start
                var pos: u32 = 0;
                for (self.layout_stack.items[0..function_layout_idx], 0..) |layout_item, i| {
                    const size = self.layout_cache.layoutSize(layout_item);
                    const alignment = layout_item.alignment(target.TargetUsize.native);

                    // Align position
                    pos = std.mem.alignForward(u32, pos, @intCast(alignment.toByteUnits()));

                    if (DEBUG_ENABLED and i < 5) { // Only log first few for brevity
                        self.traceInfo("  item[{}]: size={}, align={}, pos={}", .{ i, size, alignment, pos });
                    }

                    pos += size;
                }

                // Align to 8-byte boundary for closure position
                pos = std.mem.alignForward(u32, pos, 8);
                function_pos = pos;
            }

            // Bounds check for calculated position
            const closure_size = self.layout_cache.layoutSize(function_layout);
            if (function_pos + closure_size > self.stack_memory.used) {
                if (DEBUG_ENABLED) {
                    self.traceError("Closure position out of bounds: pos={}, size={}, stack.used={}", .{ function_pos, closure_size, self.stack_memory.used });
                }
                return error.InvalidStackState;
            }

            if (DEBUG_ENABLED) {
                self.traceInfo("Calculated closure position: {}", .{function_pos});
            }
        }

        // Read closure from the calculated/retrieved position
        const closure_memory_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + function_pos;

        // Read closure header
        const closure = Closure.read(closure_memory_ptr[0..Closure.HEADER_SIZE]);

        // Verify arity
        const expected_arg_count = arg_count;
        if (closure.args_pattern_span.span.len != expected_arg_count) {
            if (DEBUG_ENABLED) {
                self.traceError("ARITY MISMATCH: expected={}, actual={}", .{
                    closure.args_pattern_span.span.len, expected_arg_count,
                });
            }
            return error.ArityMismatch;
        }

        const parameter_patterns = self.cir.store.slicePatterns(closure.args_pattern_span);

        // Create parameter bindings
        // First, create new execution context
        // const new_context = try ExecutionContext.init(self.allocator, self.current_context);
        // try self.execution_contexts.append(new_context);
        // self.current_context = &self.execution_contexts.items[self.execution_contexts.items.len - 1];

        // Calculate argument starting position based on call type
        var arg_start_pos: u32 = 0;

        if (is_direct_lambda_call) {
            // For direct calls, arguments are after the function but BEFORE the call frame
            // Stack layout: [return_space] [function] [args...] [call_frame]
            // The call frame is pushed AFTER arguments are evaluated
            const closure_size = self.layout_cache.layoutSize(function_layout);
            arg_start_pos = function_pos + closure_size;
        } else {
            // For indirect calls, arguments start right after the function
            // Stack layout: [return_space] [function] [args...]
            arg_start_pos = function_pos + @sizeOf(Closure);
        }

        // Align to match how arguments were pushed
        // Get the first argument's layout to determine proper alignment
        if (arg_count > 0) {
            // Same calculation as in the parameter binding loop below
            const first_arg_layout_idx = self.layout_stack.items.len - arg_count + 0 - 1;
            const first_arg_layout = self.layout_stack.items[first_arg_layout_idx];
            const first_arg_alignment = first_arg_layout.alignment(target.TargetUsize.native);
            arg_start_pos = std.mem.alignForward(u32, arg_start_pos, @intCast(first_arg_alignment.toByteUnits()));
        } else {
            arg_start_pos = std.mem.alignForward(u32, arg_start_pos, 8);
        }

        // Bind parameters
        var current_pos = arg_start_pos;
        for (parameter_patterns, 0..) |_, i| {

            // Find argument layout
            // For direct calls: layout stack has [return, function, args..., call_frame]
            // For indirect calls: layout stack has [return, function, args...]
            const arg_layout_idx = self.layout_stack.items.len - arg_count + i - 1;
            const arg_layout = self.layout_stack.items[arg_layout_idx];
            const arg_size = self.layout_cache.layoutSize(arg_layout);

            // Create parameter binding
            // const binding = ParameterBinding{
            //     .pattern_idx = pattern_idx,
            //     .value_ptr = @as(*anyopaque, @ptrCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + current_pos)),
            //     .layout = arg_layout,
            // };

            // try self.parameter_bindings.append(binding);
            // try self.current_context.?.parameter_bindings.append(binding);

            // if (DEBUG_ENABLED) {
            //     self.traceInfo("PARAMETER BINDING[{}]: pattern={}, arg_size={}, stack_pos={}", .{ i, @intFromEnum(pattern_idx), arg_size, current_pos });
            // }

            // Move to next argument position
            current_pos += arg_size;
            current_pos = std.mem.alignForward(u32, current_pos, 8);
        }

        // if (DEBUG_ENABLED) {
        //     self.traceSuccess("Parameter binding complete: {} bindings created", .{arg_count});
        // }

    }

    fn handleEvalFunctionBody(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.traceEnter("START handleEvalFunctionBody expr_idx={}", .{@intFromEnum(call_expr_idx)});
        defer self.traceExit("END handleEvalFunctionBody expr_idx={}", .{@intFromEnum(call_expr_idx)});

        // Evaluate the function body and copy the result to the return space (landing pad)

        // Get the call expression to access the function
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        if (all_exprs.len == 0) {
            return error.LayoutError; // No function to call
        }

        const function_expr_idx = all_exprs[0];
        const function_expr = self.cir.store.getExpr(function_expr_idx);

        // Determine the lambda body based on whether this is a direct or indirect call
        const lambda_body = switch (function_expr) {
            .e_lambda => |lambda| lambda.body,
            else => {
                // Indirect closure call
                @panic("TODO");
            },
        };

        self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = lambda_body });
    }

    /// Copies function body result to the return space (landing pad).
    ///
    /// After the function body executes, its result is on top of the stack.
    /// This function copies that result back to the pre-allocated return space
    /// and removes the body result from the stack.
    ///
    /// # Process
    /// 1. Pop body result layout from layout_stack
    /// 2. Calculate return space position (at base of call frame)
    /// 3. Copy result data from stack top to return space
    /// 4. Remove body result from stack
    ///
    /// # Stack Transformation
    /// Before: `[return_space, function, args..., body_result]`
    /// After:  `[return_space, function, args...]` (with return_space updated)
    ///
    /// # Memory Safety
    /// Uses byte-level copying to handle different result types safely.
    /// Return space was pre-allocated with correct size and alignment.
    fn handleCopyResultToReturnSpace(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        // Copy the function body result to the return space (landing pad)
        // At this point the stack has: [return_space, function, args..., body_result]
        // We need to copy body_result to return_space and clean up body_result

        self.tracePrint("=== COPY RESULT TO RETURN SPACE(expr_idx={}) ===\n", .{@intFromEnum(call_expr_idx)});
        self.traceInfo("Initial stack.used = {}", .{self.stack_memory.used});
        self.traceInfo("Layout stack size = {}", .{self.layout_stack.items.len});
        if (DEBUG_ENABLED) {
            self.traceInfo("LAYOUT STACK contents at copy start(expr_idx={}):", .{@intFromEnum(call_expr_idx)});
            for (self.layout_stack.items, 0..) |lay, i| {
                self.traceInfo("  [{}]: tag={s}", .{ i, @tagName(lay.tag) });
            }
        }

        // The body result is at the top of the stack
        const body_result_layout = self.layout_stack.pop() orelse return error.InvalidStackState;
        const body_result_size = self.layout_cache.layoutSize(body_result_layout);

        // Detailed closure layout tracking during result copy
        if (body_result_layout.tag == .closure) {
            self.traceInfo("POPPING RESULT LAYOUT: tag=closure, env_size={}, remaining_stack_depth={}", .{ body_result_layout.data.closure.env_size, self.layout_stack.items.len });
        }

        self.traceInfo("Body result layout = {}, size = {}", .{ body_result_layout.tag, body_result_size });

        // Debug: Show actual stack state before calculating position
        // if (DEBUG_ENABLED) {
        //     self.traceInfo("DEBUG: Stack state before body result position calc:", .{});
        //     self.traceInfo("  stack.used = {}", .{self.stack_memory.used});
        //     self.traceInfo("  body_result_size from layout = {}", .{body_result_size});

        //     // Dump last 64 bytes of stack to see what's there
        //     const dump_start = if (self.stack_memory.used > 64) self.stack_memory.used - 64 else 0;
        //     self.traceInfo("  Stack dump from position {} to {}:", .{ dump_start, self.stack_memory.used });
        //     const stack_ptr = @as([*]u8, @ptrCast(self.stack_memory.start));
        //     var pos = dump_start;
        //     while (pos < self.stack_memory.used) : (pos += 16) {
        //         self.tracePrint("    [{}]: ", .{pos});
        //         const end = @min(pos + 16, self.stack_memory.used);
        //         for (pos..end) |i| {
        //             self.tracePrint("{x:0>2} ", .{stack_ptr[i]});
        //         }
        //         self.tracePrint("\n", .{});
        //     }
        // }

        // Calculate position of body result
        const body_result_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - body_result_size;

        self.traceInfo("Body result layout = {}, size = {}", .{ body_result_layout.tag, body_result_size });
        self.traceInfo("Body result at stack position = {} (calculated as {} - {})", .{ self.stack_memory.used - body_result_size, self.stack_memory.used, body_result_size });

        // Find the return space - it should be at the bottom of our call frame
        // We need to find how many items are in our call frame to calculate the return space position

        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function

        self.traceInfo("Call has {} arguments\n", .{arg_count});

        // The return space (landing pad) is at position 0 for this simple case
        // For nested calls, we would need to track where each call's return space starts
        const return_space_pos: u32 = 0;

        const return_space_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + return_space_pos;

        // if (DEBUG_ENABLED) {
        //     self.traceInfo("Final return space position = {}", .{return_space_pos});
        //     self.traceInfo("Copying {} bytes from {} to {}", .{ body_result_size, self.stack_memory.used - body_result_size, return_space_pos });

        //     // Verify the copy source data before copying
        //     const source_bytes = @as([*]u8, @ptrCast(body_result_ptr));
        //     self.tracePrint("Source bytes: ", .{});
        //     for (0..@min(body_result_size, 16)) |i| {
        //         self.traceInfo("{x:0>2} ", .{source_bytes[i]});
        //     }
        //     self.tracePrint("\n", .{});
        // }

        // Copy the result (check for overlap first)
        const src_start = @intFromPtr(body_result_ptr);
        const src_end = src_start + body_result_size;
        const dst_start = @intFromPtr(return_space_ptr);
        const dst_end = dst_start + body_result_size;

        if ((src_start < dst_end) and (dst_start < src_end)) {
            // Overlapping memory - need to handle carefully
            if (src_start < dst_start) {
                // Copy backwards to avoid overwriting source
                var i = body_result_size;
                while (i > 0) {
                    i -= 1;
                    return_space_ptr[i] = body_result_ptr[i];
                }
            } else if (src_start > dst_start) {
                // Copy forwards
                for (0..body_result_size) |i| {
                    return_space_ptr[i] = body_result_ptr[i];
                }
            }
            // If src_start == dst_start, no copy needed
        } else {
            // Non-overlapping, safe to use memcpy
            @memcpy(return_space_ptr[0..body_result_size], body_result_ptr[0..body_result_size]);
        }

        // Verify the copy destination data after copying
        // if (DEBUG_ENABLED) {
        //     const dest_bytes = @as([*]u8, @ptrCast(return_space_ptr));
        //     self.tracePrint("Dest bytes after copy: ", .{});
        //     for (0..@min(body_result_size, 16)) |i| {
        //         self.traceInfo("{x:0>2} ", .{dest_bytes[i]});
        //     }
        //     self.tracePrint("\n", .{});
        // }

        // Pop the body result from stack
        self.stack_memory.used -= @as(u32, @intCast(body_result_size));

        if (DEBUG_ENABLED) {
            self.traceInfo("After cleanup: stack.used = {}", .{self.stack_memory.used});

            // Don't push the layout - the return space layout is already on the stack
            self.tracePrint("=== END COPY RESULT TO RETURN SPACE(expr_idx={}) ===\n", .{@intFromEnum(call_expr_idx)});
        }
    }

    /// Cleans up function call frame, leaving only the return value.
    ///
    /// Removes the function and argument data from both stack memory and
    /// layout stack, then moves the return value to the base of the stack
    /// for consistent result positioning.
    ///
    /// # Process
    /// 1. Clear parameter bindings for this call
    /// 2. Calculate positions of return value, function, and arguments
    /// 3. Move return value from landing pad to stack base
    /// 4. Update stack_memory.used to reflect only the return value
    /// 5. Clean up function and argument layouts from layout_stack
    ///
    /// # Stack Transformation
    /// Before: `[return_space, function, args...]` (return_space contains result)
    /// After:  `[return_value]` (moved to position 0)
    ///
    /// # Memory Management
    /// - Compacts stack to eliminate unused call frame data
    /// - Ensures return value is at predictable location (stack base)
    /// - Maintains proper alignment for return value
    fn handleCleanupFunction(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.tracePrint("START CLEANUP FUNCTION(expr_idx={})\n", .{@intFromEnum(call_expr_idx)});
        self.traceLayoutStackSummary();

        defer self.tracePrint("END CLEANUP FUNCTION(expr_idx={})\n", .{@intFromEnum(call_expr_idx)});
        defer self.traceLayoutStackSummary();

        // Get call information
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        // Check if this was a direct lambda call
        const callee_expr = all_exprs[0];
        const callee = self.cir.store.getExpr(callee_expr);
        const is_direct_lambda_call = (callee == .e_lambda);

        // Layout stack has different structure for direct vs indirect calls
        // Direct: [return_layout, function_layout, call_frame_layout, arg_layouts...]
        // Indirect: [return_layout, function_layout, arg_layouts...]
        const expected_layouts = if (is_direct_lambda_call) arg_count + 3 else arg_count + 2;

        if (self.layout_stack.items.len < expected_layouts) {
            self.traceError(
                "CLEANUP FAILED: Not enough layouts! expected={}, actual={}",
                .{ expected_layouts, self.layout_stack.items.len },
            );
            return error.InvalidStackState;
        }

        // Get the return layout (at bottom of call frame)
        const return_layout_idx = if (is_direct_lambda_call)
            self.layout_stack.items.len - arg_count - 3 // Skip function + call_frame
        else
            self.layout_stack.items.len - arg_count - 2; // Skip function only
        const return_layout = self.layout_stack.items[return_layout_idx];
        const return_size = self.layout_cache.layoutSize(return_layout);

        // Calculate total size of function, call frame (if present), and arguments to remove
        var cleanup_size: u32 = 0;

        // Function size
        const function_layout_idx = if (is_direct_lambda_call)
            self.layout_stack.items.len - arg_count - 2 // Skip call frame
        else
            self.layout_stack.items.len - arg_count - 1;
        const function_layout = self.layout_stack.items[function_layout_idx];
        cleanup_size += @as(u32, @intCast(self.layout_cache.layoutSize(function_layout)));

        // Call frame size (if direct lambda call)
        if (is_direct_lambda_call) {
            cleanup_size += CallFrame.size();
        }

        // Argument sizes
        for (0..arg_count) |i| {
            const arg_layout = self.layout_stack.items[self.layout_stack.items.len - 1 - i];
            cleanup_size += @as(u32, @intCast(self.layout_cache.layoutSize(arg_layout)));
        }

        // The return value was copied to the landing pad at position 0
        const return_value_current_pos: u32 = 0;

        // Move return value from current position to position 0
        const source_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + return_value_current_pos;
        const dest_ptr = @as([*]u8, @ptrCast(self.stack_memory.start));

        std.mem.copyForwards(u8, dest_ptr[0..return_size], source_ptr[0..return_size]);

        // Update stack to contain only the return value
        self.stack_memory.used = @as(u32, @intCast(return_size));

        // Clean up layout stack: remove all call-related layouts except return
        const layouts_to_remove = if (is_direct_lambda_call)
            arg_count + 2 // function + call_frame + arguments
        else
            arg_count + 1; // function + arguments

        // Remove function, call frame (if present), and argument layouts (but keep return layout)
        for (0..layouts_to_remove) |_| {
            _ = self.layout_stack.pop() orelse return error.InvalidStackState;
        }
    }

    // ===================================================================
    // STRUCTURED DEBUG TRACING SYSTEM
    // ===================================================================
    //
    // This system provides clean, hierarchical debug output that only prints
    // when both DEBUG_ENABLED is true AND a trace session is active.
    //
    // ## Usage Pattern:
    //
    // 1. Start a trace session:
    //    ```zig
    //    interpreter.startTrace("My Test Description");
    //    defer interpreter.endTrace(); // Always end the trace
    //    ```
    //
    // 2. Use trace methods throughout your code:
    //    ```zig
    //    self.traceEnter("METHOD_NAME(arg={})", .{arg_value});
    //    defer self.traceExit("METHOD_NAME completed");
    //
    //    self.tracePrint("General info: {}", .{value});
    //    self.traceInfo("Data: key={s}, count={}", .{key, count});
    //    self.traceWarn("Warning: {}", .{issue});
    //    self.traceError("Error occurred: {}", .{error_info});
    //    self.traceSuccess("Operation completed successfully");
    //    ```
    //
    // 3. Use specialized trace helpers:
    //    ```zig
    //    self.traceStackState("before_operation");
    //    self.traceLayout("return_type", layout);
    //    self.traceClosure("allocated", closure_ptr, has_captures);
    //    ```
    //
    // ## Output Format:
    // - 🔵 Function/method entry (with indentation)
    // - 🔴 Function/method exit (with indentation)
    // - ⚪ General trace messages
    // - ℹ️ Info messages (data/state)
    // - ⚠️ Warning messages
    // - ❌ Error messages
    // - ✅ Success messages
    // - 📊 Stack state info
    // - 📐 Layout info
    // - 🏗️ Closure info
    //
    // ## Testing:
    // Run tests with: `zig build test -Dtrace-eval`
    // Only tests with active trace sessions will produce debug output.
    //
    // ===================================================================

    /// Start a debug trace session with a given name and writer
    /// Only has effect if DEBUG_ENABLED is true
    pub fn startTrace(self: *Interpreter, writer: std.io.AnyWriter) void {
        if (!DEBUG_ENABLED) return;
        self.trace_indent = 0;
        self.trace_writer = writer;
        writer.print("\n...", .{}) catch {};
        writer.print("\n\n══ TRACE START ═══════════════════════════════════\n", .{}) catch {};
    }

    /// End the current debug trace session
    /// Only has effect if DEBUG_ENABLED is true
    pub fn endTrace(self: *Interpreter) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            writer.print("══ TRACE END ═════════════════════════════════════\n", .{}) catch {};
        }
        self.trace_indent = 0;
        self.trace_writer = null;
    }

    /// Print indentation for current trace level
    fn printTraceIndent(self: *const Interpreter) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            var i: u32 = 0;
            while (i < self.trace_indent) : (i += 1) {
                writer.writeAll("  ") catch {};
            }
        }
    }

    /// Enter a traced function/method with formatted message
    pub fn traceEnter(self: *Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("🔵 " ++ fmt ++ "\n", args) catch {};
            self.trace_indent += 1;
        }
    }

    /// Exit a traced function/method
    pub fn traceExit(self: *Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            if (self.trace_indent > 0) self.trace_indent -= 1;
            self.printTraceIndent();
            writer.print("🔴 " ++ fmt ++ "\n", args) catch {};
        }
    }

    /// Print a general trace message
    pub fn tracePrint(self: *const Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("⚪ " ++ fmt ++ "\n", args) catch {};
        }
    }

    /// Print trace information (data/state)
    pub fn traceInfo(self: *const Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("ℹ️  " ++ fmt ++ "\n", args) catch {};
        }
    }

    /// Print trace warning
    pub fn traceWarn(self: *const Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("⚠️  " ++ fmt ++ "\n", args) catch {};
        }
    }

    /// Print trace error
    pub fn traceError(self: *const Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("❌ " ++ fmt ++ "\n", args) catch {};
        }
    }

    /// Helper to pretty print a CIR.Expression in a trace
    pub fn traceExpression(self: *const Interpreter, expression_idx: CIR.Expr.Idx) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            const expression = self.cir.store.getExpr(expression_idx);

            var tree = SExprTree.init(self.cir.env.gpa);
            defer tree.deinit();

            expression.pushToSExprTree(self.cir, &tree, expression_idx) catch {};

            self.printTraceIndent();

            tree.toStringPretty(writer) catch {};

            writer.print("\n", .{}) catch {};
        }
    }

    /// Helper to pretty print a CIR.Pattern in a trace
    pub fn tracePattern(self: *const Interpreter, pattern_idx: CIR.Pattern.Idx) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            const pattern = self.cir.store.getPattern(pattern_idx);

            var tree = SExprTree.init(self.cir.env.gpa);
            defer tree.deinit();

            pattern.pushToSExprTree(self.cir, &tree, pattern_idx) catch {};

            self.printTraceIndent();

            tree.toStringPretty(writer) catch {};

            writer.print("\n", .{}) catch {};
        }
    }

    /// Print trace success
    pub fn traceSuccess(self: *const Interpreter, comptime fmt: []const u8, args: anytype) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("✅ " ++ fmt ++ "\n", args) catch {};
        }
    }

    /// Trace stack memory state
    pub fn traceStackState(self: *const Interpreter, label: []const u8) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("📊 STACK STATE ({s}): used={}, capacity={}, items_on_layout_stack={}\n", .{
                label,
                self.stack_memory.used,
                self.stack_memory.capacity,
                self.layout_stack.items.len,
            }) catch {};
        }
    }

    /// Trace layout information
    pub fn traceLayout(self: *const Interpreter, label: []const u8, layout_val: layout.Layout) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            const size = self.layout_cache.layoutSize(layout_val);
            writer.print("📐 LAYOUT ({s}): tag={s}, size={}\n", .{ label, @tagName(layout_val.tag), size }) catch {};
        }
    }

    /// Helper to print layout stack information
    pub fn traceLayoutStackSummary(self: *const Interpreter) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            writer.print("LAYOUT STACK items={}\n", .{self.layout_stack.items.len}) catch {};
        }
    }

    /// Trace closure information
    pub fn traceClosure(self: *Interpreter, closure: *const Closure, position: usize) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            const has_captures = closure.captures_count > 0;
            writer.print("🏗️  CLOSURE: pos={}, body={}, args_len={}, has_captures={}\n", .{
                position,
                @intFromEnum(closure.body_expr_idx),
                closure.args_pattern_span.span.len,
                has_captures,
            }) catch {};
        }
    }

    /// Verify that the stack memory usage matches the layout stack
    fn verifyStackInvariant(self: *Interpreter) void {
        if (!DEBUG_ENABLED) return;

        var calculated_size: u32 = 0;
        var pos: u32 = 0;

        for (self.layout_stack.items) |lay| {
            const size = self.layout_cache.layoutSize(lay);
            const alignment = lay.alignment(target.TargetUsize.native);

            // Align position
            pos = std.mem.alignForward(u32, pos, @intCast(alignment.toByteUnits()));
            calculated_size = pos + size;
            calculated_size = pos;
        }

        if (calculated_size != self.stack_memory.used) {
            self.traceError("Stack invariant violated: calculated={}, actual={}", .{
                calculated_size, self.stack_memory.used,
            });
            std.debug.panic("Stack invariant violated!", .{});
        }
    }

    /// Look up a captured variable from closure data
    // fn lookupCapturedVariable(
    //     self: *Interpreter,
    //     closure_ptr: [*]const u8,
    //     closure_size: u32,
    //     pattern_idx: CIR.Pattern.Idx,
    // ) ?VariableLookupResult {
    //     _ = self; // Mark as used
    //     if (closure_size <= Closure.HEADER_SIZE) {
    //         return null; // No captures
    //     }

    //     const closure = Closure.read(closure_ptr[0..Closure.HEADER_SIZE]);
    //     if (closure.captures_count == 0) {
    //         return null;
    //     }

    //     var offset: u32 = Closure.HEADER_SIZE;
    //     const end_offset = Closure.HEADER_SIZE + closure.captures_size;

    //     // Search through captured variables
    //     var capture_idx: u32 = 0;
    //     while (offset < end_offset and capture_idx < closure.captures_count) : (capture_idx += 1) {
    //         // Read pattern index
    //         const captured_pattern_idx = @as(CIR.Pattern.Idx, @enumFromInt(std.mem.readInt(u32, closure_ptr[offset..][0..4], .little)));
    //         offset += 4;

    //         // Read value size
    //         const value_size = std.mem.readInt(u32, closure_ptr[offset..][0..4], .little);
    //         offset += 4;

    //         if (captured_pattern_idx == pattern_idx) {
    //             // Found it! Determine layout from the captured value
    //             // For now, assume it's an integer (this should be stored or computed properly)
    //             const value_layout = layout.Layout{
    //                 .tag = .scalar,
    //                 .data = .{
    //                     .scalar = .{
    //                         .tag = .int,
    //                         .data = .{ .int = .i64 },
    //                     },
    //                 },
    //             };

    //             return VariableLookupResult{
    //                 .ptr = @as(*anyopaque, @ptrFromInt(@intFromPtr(closure_ptr) + offset)),
    //                 .layout = value_layout,
    //             };
    //         }

    //         // Skip to next capture (aligned to 8 bytes)
    //         offset = std.mem.alignForward(u32, offset + value_size, 8);
    //     }

    //     return null;
    // }

    // /// Look up a variable's current value for capture
    // fn lookupVariableForCapture(
    //     self: *Interpreter,
    //     pattern_idx: CIR.Pattern.Idx,
    // ) !VariableLookupResult {
    //     // First check parameter bindings
    //     // for (self.parameter_bindings.items) |binding| {
    //     //     if (binding.pattern_idx == pattern_idx) {
    //     //         return VariableLookupResult{
    //     //             .ptr = binding.value_ptr,
    //     //             .layout = binding.layout,
    //     //         };
    //     //     }
    //     // }

    //     // Finally check global definitions
    //     const defs = self.cir.store.sliceDefs(self.cir.all_defs);
    //     for (defs) |def_idx| {
    //         const def = self.cir.store.getDef(def_idx);
    //         if (@intFromEnum(def.pattern) == @intFromEnum(pattern_idx)) {
    //             // For global definitions, we need to evaluate them
    //             // This is a simplification - in reality we'd need to handle this properly
    //             return error.GlobalDefinitionNotSupported;
    //         }
    //     }

    //     return error.PatternNotFound;
    // }

    /// Contains both the type information (layout) and a pointer to the actual value
    /// in memory. The caller is responsible for interpreting the memory correctly
    /// based on the layout information.
    pub const StackValue = struct {
        /// Type and memory layout information for the result value
        layout: layout.Layout,
        /// Pointer to the actual value in stack memory
        ptr: ?*anyopaque,
    };

    /// Helper to push a value onto the stacks.
    ///
    /// Allocates memory on `stack_memory`, pushes the layout to `layout_stack`,
    /// and returns a pointer to the newly allocated memory.
    ///
    /// The caller is responsible for writing the actual value to the returned pointer.
    ///
    /// Returns null for zero-sized types.
    fn pushStackValue(self: *Interpreter, value_layout: Layout) !?*anyopaque {
        const value_size = self.layout_cache.layoutSize(value_layout);
        var value_ptr: ?*anyopaque = null;

        if (value_size > 0) {
            const value_alignment = value_layout.alignment(target_usize);
            value_ptr = try self.stack_memory.alloca(value_size, value_alignment);
        }

        try self.layout_stack.append(value_layout);

        self.tracePrint("pushStackValue {s}", .{@tagName(value_layout.tag)});

        return value_ptr;
    }

    /// Helper to pop a value from the stacks.
    ///
    /// Pops a layout from `layout_stack`, calculates the corresponding value's
    /// location on `stack_memory`, adjusts the stack pointer, and returns
    /// the layout and a pointer to the value's (now popped) location.
    fn popStackValue(self: *Interpreter) EvalError!StackValue {
        const value_layout = self.layout_stack.pop() orelse return error.InvalidStackState;
        const value_size = self.layout_cache.layoutSize(value_layout);

        if (value_size == 0) {
            return StackValue{ .layout = value_layout, .ptr = null };
        }

        // The value is at the top of the stack before we pop it.
        const value_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - value_size;
        self.stack_memory.used -= value_size;

        self.tracePrint("popStackValue {s}", .{@tagName(value_layout.tag)});

        return StackValue{ .layout = value_layout, .ptr = @as(*anyopaque, @ptrCast(value_ptr)) };
    }

    /// Helper to peek at the top value on the evaluation stacks without popping it.
    /// Returns the layout and a pointer to the value.
    fn peekTopStackValue(self: *Interpreter) !StackValue {
        const value_layout = self.layout_stack.items[self.layout_stack.items.len - 1];
        const value_size = self.layout_cache.layoutSize(value_layout);

        if (value_size == 0) {
            return StackValue{ .layout = value_layout, .ptr = null };
        }

        const ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - value_size;
        return StackValue{ .layout = value_layout, .ptr = @as(*anyopaque, @ptrCast(ptr)) };
    }
};

// Helper function to write an integer to memory with the correct precision
fn writeIntToMemory(ptr: [*]u8, value: i128, precision: types.Num.Int.Precision) void {
    switch (precision) {
        .u8 => @as(*u8, @ptrCast(@alignCast(ptr))).* = @as(u8, @intCast(value)),
        .u16 => @as(*u16, @ptrCast(@alignCast(ptr))).* = @as(u16, @intCast(value)),
        .u32 => @as(*u32, @ptrCast(@alignCast(ptr))).* = @as(u32, @intCast(value)),
        .u64 => @as(*u64, @ptrCast(@alignCast(ptr))).* = @as(u64, @intCast(value)),
        .u128 => @as(*u128, @ptrCast(@alignCast(ptr))).* = @as(u128, @intCast(value)),
        .i8 => @as(*i8, @ptrCast(@alignCast(ptr))).* = @as(i8, @intCast(value)),
        .i16 => @as(*i16, @ptrCast(@alignCast(ptr))).* = @as(i16, @intCast(value)),
        .i32 => @as(*i32, @ptrCast(@alignCast(ptr))).* = @as(i32, @intCast(value)),
        .i64 => @as(*i64, @ptrCast(@alignCast(ptr))).* = @as(i64, @intCast(value)),
        .i128 => @as(*i128, @ptrCast(@alignCast(ptr))).* = value,
    }
}

// Helper function to read an integer from memory with the correct precision
pub fn readIntFromMemory(ptr: [*]u8, precision: types.Num.Int.Precision) i128 {
    return switch (precision) {
        .u8 => @as(i128, @as(*u8, @ptrCast(@alignCast(ptr))).*),
        .u16 => @as(i128, @as(*u16, @ptrCast(@alignCast(ptr))).*),
        .u32 => @as(i128, @as(*u32, @ptrCast(@alignCast(ptr))).*),
        .u64 => @as(i128, @as(*u64, @ptrCast(@alignCast(ptr))).*),
        .u128 => @as(i128, @intCast(@as(*u128, @ptrCast(@alignCast(ptr))).*)),
        .i8 => @as(i128, @as(*i8, @ptrCast(@alignCast(ptr))).*),
        .i16 => @as(i128, @as(*i16, @ptrCast(@alignCast(ptr))).*),
        .i32 => @as(i128, @as(*i32, @ptrCast(@alignCast(ptr))).*),
        .i64 => @as(i128, @as(*i64, @ptrCast(@alignCast(ptr))).*),
        .i128 => @as(*i128, @ptrCast(@alignCast(ptr))).*,
    };
}

test {
    _ = @import("test/eval_test.zig");
}

test "stack-based binary operations" {
    // Test that the stack-based interpreter correctly evaluates binary operations
    const allocator = std.testing.allocator;

    // Create a simple stack for testing
    var eval_stack = try stack.Stack.initCapacity(allocator, 1024);
    defer eval_stack.deinit();

    // Track layouts
    // Create interpreter
    var interpreter = try Interpreter.init(allocator, undefined, &eval_stack, undefined, undefined);
    defer interpreter.deinit();

    // Test addition: 2 + 3 = 5
    {
        // Push 2
        const int_layout = layout.Layout{
            .tag = .scalar,
            .data = .{ .scalar = .{
                .tag = .int,
                .data = .{ .int = .i64 },
            } },
        };
        const size = @sizeOf(i64);
        const alignment: std.mem.Alignment = .@"8";

        const ptr1 = eval_stack.alloca(size, alignment) catch unreachable;
        @as(*i64, @ptrCast(@alignCast(ptr1))).* = 2;
        try interpreter.layout_stack.append(int_layout);

        // Push 3
        const ptr2 = eval_stack.alloca(size, alignment) catch unreachable;
        @as(*i64, @ptrCast(@alignCast(ptr2))).* = 3;
        try interpreter.layout_stack.append(int_layout);

        // Perform addition
        try interpreter.completeBinop(.w_binop_add);

        // Check result
        try std.testing.expectEqual(@as(usize, 1), interpreter.layout_stack.items.len);
        const result_ptr = @as([*]u8, @ptrCast(eval_stack.start)) + eval_stack.used - size;
        const result = @as(*i64, @ptrCast(@alignCast(result_ptr))).*;
        try std.testing.expectEqual(@as(i64, 5), result);
    }
}

test "stack-based comparisons" {
    // Test that comparisons produce boolean results
    const allocator = std.testing.allocator;

    // Create a simple stack for testing
    var eval_stack = try stack.Stack.initCapacity(allocator, 1024);
    defer eval_stack.deinit();

    // Create interpreter
    var interpreter = try Interpreter.init(allocator, undefined, &eval_stack, undefined, undefined);
    defer interpreter.deinit();

    // Test 5 > 3 = True (1)
    {
        // Push 5
        const int_layout = layout.Layout{
            .tag = .scalar,
            .data = .{ .scalar = .{
                .tag = .int,
                .data = .{ .int = .i64 },
            } },
        };
        const size = @sizeOf(i64);
        const alignment: std.mem.Alignment = .@"8";

        const ptr1 = eval_stack.alloca(size, alignment) catch unreachable;
        @as(*i64, @ptrCast(@alignCast(ptr1))).* = 5;
        try interpreter.layout_stack.append(int_layout);

        // Push 3
        const ptr2 = eval_stack.alloca(size, alignment) catch unreachable;
        @as(*i64, @ptrCast(@alignCast(ptr2))).* = 3;
        try interpreter.layout_stack.append(int_layout);

        // Perform comparison
        try interpreter.completeBinop(.w_binop_gt);

        // Check result - should be a u8 with value 1 (true)
        try std.testing.expectEqual(@as(usize, 1), interpreter.layout_stack.items.len);
        const bool_layout = interpreter.layout_stack.items[0];
        try std.testing.expect(bool_layout.tag == .scalar);
        try std.testing.expect(bool_layout.data.scalar.tag == .int);
        try std.testing.expect(bool_layout.data.scalar.data.int == .u8);

        const result_ptr = @as([*]u8, @ptrCast(eval_stack.start)) + eval_stack.used - 1;
        const result = result_ptr[0];
        try std.testing.expectEqual(@as(u8, 1), result);
    }
}
