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

const types_store = types.store;
const target = base.target;

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
    Crash,
    OutOfMemory,
    StackOverflow,
    LayoutError,
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
};

/// Result of evaluating an expression.
///
/// Contains both the type information (layout) and a pointer to the actual value
/// in memory. The caller is responsible for interpreting the memory correctly
/// based on the layout information.
///
/// # Memory Safety
/// The pointer is only valid while the associated stack frame remains alive.
/// The caller must not access the pointer after the interpreter's stack has
/// been modified or the interpreter has been deinitialized.
pub const EvalResult = struct {
    /// Type and memory layout information for the result value
    layout: layout.Layout,
    /// Pointer to the actual value in stack memory
    ptr: *anyopaque,
};

// Work item for the iterative evaluation stack
const WorkKind = enum {
    eval_expr,
    binop_add,
    binop_sub,
    binop_mul,
    binop_div,
    binop_eq,
    binop_ne,
    binop_gt,
    binop_lt,
    binop_ge,
    binop_le,
    unary_minus,
    if_check_condition,

    // **Function call work items**

    /// Allocate space for return value (landing pad)
    alloc_return_space,
    /// Orchestrate function call
    call_function,
    /// Bind arguments to parameters
    bind_parameters,
    /// Evaluate lambda body
    eval_function_body,
    /// Copy function result to return space
    copy_result_to_return_space,
    /// Clean up bindings
    cleanup_function,
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
pub const CapturedBinding = struct {
    pattern_idx: CIR.Pattern.Idx, // Pattern index of the captured variable
    value_data: [*]u8, // Pointer to the captured value data
    layout: layout.Layout, // Layout of the captured value

    pub fn validate(self: CapturedBinding) bool {
        _ = self; // Suppress unused parameter warning
        // Basic validation that the captured binding is well-formed
        return true; // [*]u8 pointers are never null in our context
    }
};

/// Environment of captured variables for a closure
pub const CapturedEnvironment = struct {
    bindings: []CapturedBinding, // Array of captured bindings
    parent_env: ?*CapturedEnvironment, // Parent environment for nested closures
    deferred_init: bool, // Flag indicating if environment needs deferred initialization

    pub fn validate(self: CapturedEnvironment) bool {
        // Validate all bindings in this environment
        for (self.bindings) |binding| {
            if (!binding.validate()) {
                return false;
            }
        }

        // Recursively validate parent environment
        if (self.parent_env) |parent| {
            return parent.validate();
        }

        return true;
    }

    pub fn findCapturedVariable(self: *const CapturedEnvironment, pattern_idx: CIR.Pattern.Idx) ?*CapturedBinding {
        // Search current environment
        for (self.bindings) |*binding| {
            if (binding.pattern_idx == pattern_idx) {
                return binding;
            }
        }

        // Search parent environments
        if (self.parent_env) |parent| {
            return parent.findCapturedVariable(pattern_idx);
        }

        return null;
    }
};

// /// Entry in the captured environments registry
// const CapturedEnvironmentEntry = struct {
//     position: usize,
//     env: *CapturedEnvironment,
// };

/// Enhanced closure structure with captured environment support
pub const Closure = struct {
    body_expr_idx: CIR.Expr.Idx, // What expression to execute
    args_pattern_span: CIR.Pattern.Span, // Parameters to bind
    captured_env: ?*CapturedEnvironment, // Captured variables from outer scopes
    layout: layout.Layout, // Layout information including capture count
};

/// Simple closure structure for backward compatibility
pub const SimpleClosure = struct {
    body_expr_idx: CIR.Expr.Idx, // What expression to execute
    args_pattern_span: CIR.Pattern.Span, // Parameters to bind
    layout: layout.Layout, // Layout information including capture count
};

/// Capture analysis result for a lambda expression
/// Analyzer for determining what variables a lambda needs to capture
/// Calculate the total size needed for a captured environment
fn calculateEnvironmentSize(
    layout_cache: *layout_store.Store,
    captured_vars: []const CIR.Pattern.Idx,
) !usize {
    var total_size: usize = 0;

    // Add size for the environment header
    total_size += @sizeOf(CapturedEnvironment);

    // Add size for the bindings array
    total_size += captured_vars.len * @sizeOf(CapturedBinding);

    // Add size for each captured value's data
    for (captured_vars) |pattern_idx| {
        // Get the type variable for this pattern
        const pattern_var = @as(types.Var, @enumFromInt(@intFromEnum(pattern_idx)));

        // Get layout and calculate size
        const layout_idx = layout_cache.addTypeVar(pattern_var) catch |err| switch (err) {
            error.ZeroSizedType => continue, // Skip zero-sized types
            else => return err,
        };
        const value_layout = layout_cache.getLayout(layout_idx);
        const value_size = layout_cache.layoutSize(value_layout);

        total_size += value_size;
    }

    return total_size;
}

/// Create a closure with captured variables
/// Initialize captured environment data structure
fn initializeCapturedEnvironment(
    self: *Interpreter,
    env_ptr: [*]u8,
    captured_vars: []const CIR.Pattern.Idx,
) !*CapturedEnvironment {
    self.traceInfo("INIT CAPTURE ENV: {} variables to capture", .{captured_vars.len});

    // Cast memory to environment structure
    const env = @as(*CapturedEnvironment, @ptrCast(@alignCast(env_ptr)));

    // Calculate positions for bindings array and value data
    const bindings_offset = @sizeOf(CapturedEnvironment);
    const bindings_ptr = env_ptr + bindings_offset;
    const bindings = @as([*]CapturedBinding, @ptrCast(@alignCast(bindings_ptr)))[0..captured_vars.len];

    // Initialize environment structure
    env.* = CapturedEnvironment{
        .bindings = bindings,
        .parent_env = null, // TODO: Support for nested environments
        .deferred_init = false, // Regular initialization, not deferred
    };

    // Initialize captured bindings
    var value_data_offset = bindings_offset + (captured_vars.len * @sizeOf(CapturedBinding));

    for (captured_vars, 0..) |pattern_idx, i| {
        // Find the current value of this variable from execution context chain
        var found_value: ?*u8 = null;
        var found_layout: ?layout.Layout = null;

        // First try current parameter bindings (backward compatibility)
        for (self.parameter_bindings.items) |binding| {
            if (binding.pattern_idx == pattern_idx) {
                found_value = @as(*u8, @ptrCast(binding.value_ptr));
                found_layout = binding.layout;
                break;
            }
        }

        // If not found, search through execution context chain
        if (found_value == null) {
            var context = self.current_context;
            while (context) |ctx| {
                if (ctx.findBinding(pattern_idx)) |binding| {
                    found_value = @as(*u8, @ptrCast(binding.value_ptr));
                    found_layout = binding.layout;
                    self.traceInfo("FOUND in execution context: pattern={}", .{@intFromEnum(pattern_idx)});
                    break;
                }
                context = ctx.parent_context;
            }
        }

        if (found_value == null) {
            // This should not happen if capture analysis is correct
            self.traceError("CAPTURE ERROR: pattern {} not found in parameter bindings or execution contexts", .{@intFromEnum(pattern_idx)});
            return error.CaptureError;
        }

        // Calculate size and copy value data
        const value_layout = found_layout.?;

        self.traceInfo("CAPTURING[{}]: pattern={}, size={} bytes", .{ i, @intFromEnum(pattern_idx), self.layout_cache.layoutSize(value_layout) });
        const value_size = self.layout_cache.layoutSize(value_layout);
        const value_ptr = env_ptr + value_data_offset;

        // Copy the captured value
        @memcpy(value_ptr[0..value_size], @as([*]u8, @ptrCast(found_value))[0..value_size]);

        // Initialize binding
        bindings[i] = CapturedBinding{
            .pattern_idx = pattern_idx,
            .value_data = value_ptr,
            .layout = value_layout,
        };

        value_data_offset += value_size;
    }

    return env;
}

/// Look up a variable in captured environment
fn lookupVariable(
    self: *Interpreter,
    pattern_idx: CIR.Pattern.Idx,
    env: ?*CapturedEnvironment,
) ?CapturedBinding {
    self.traceInfo("LOOKUP VAR: pattern={}, has_env={}", .{ @intFromEnum(pattern_idx), env != null });

    const result = self.searchCapturedEnvironment(pattern_idx, env);

    if (result) |binding| {
        self.traceSuccess("VAR FOUND: pattern={}, layout={s}", .{ @intFromEnum(binding.pattern_idx), @tagName(binding.layout.tag) });
    } else {
        self.traceWarn("VAR NOT FOUND: pattern={}", .{@intFromEnum(pattern_idx)});
    }

    return result;
}

/// Search for a variable in the captured environment chain
fn searchCapturedEnvironment(
    self: *Interpreter,
    pattern_idx: CIR.Pattern.Idx,
    env: ?*CapturedEnvironment,
) ?CapturedBinding {
    if (env == null) {
        self.traceInfo("SEARCH: no environment to search", .{});
        return null;
    }

    const current_env = env.?;

    self.traceInfo("SEARCH ENV: {} bindings, parent={}", .{ current_env.bindings.len, current_env.parent_env != null });

    // Search in current environment
    for (current_env.bindings, 0..) |binding, i| {
        self.traceInfo("[{:2}] checking pattern {} vs target {}", .{ i, @intFromEnum(binding.pattern_idx), @intFromEnum(pattern_idx) });

        if (binding.pattern_idx == pattern_idx) {
            self.traceSuccess("MATCH found at index {}", .{i});
            return binding;
        }
    }

    // Search in parent environment recursively
    if (current_env.parent_env != null) {
        self.traceInfo("SEARCH PARENT: continuing search", .{});
    }
    return self.searchCapturedEnvironment(pattern_idx, current_env.parent_env);
}

/// Binds a function parameter pattern to an argument value during function calls.
///
/// When a function is called, arguments are bound to parameters through
/// these binding structures. The binding associates a parameter pattern
/// with the memory location and type of the corresponding argument.
///
/// # Lifecycle
/// 1. Created during `bind_parameters` work phase
/// 2. Used during function body evaluation for variable lookups
/// 3. Cleaned up during `cleanup_function` work phase
///
/// # Memory Safety
/// The `value_ptr` points into the interpreter's stack memory and is only
/// valid while the function call is active. Must not be accessed after
/// the function call completes.
///
/// # Current Implementation
/// Uses a simple linear search for parameter lookups. Future optimizations
/// may use hash maps or other data structures for better performance.
const ParameterBinding = struct {
    /// Pattern index that this binding satisfies (for pattern matching)
    pattern_idx: CIR.Pattern.Idx,
    /// Pointer to the argument value in stack memory
    value_ptr: *anyopaque,
    /// Type and layout information for the argument value
    layout: layout.Layout,
};

/// Execution context for function calls, maintaining scope chain for variable lookup
const ExecutionContext = struct {
    /// Parameter bindings for this function call scope
    parameter_bindings: std.ArrayList(ParameterBinding),
    /// Parent context for nested function calls (scope chain)
    parent_context: ?*ExecutionContext,

    fn init(allocator: std.mem.Allocator, parent: ?*ExecutionContext) !ExecutionContext {
        return ExecutionContext{
            .parameter_bindings = try std.ArrayList(ParameterBinding).initCapacity(allocator, 16),
            .parent_context = parent,
        };
    }

    fn deinit(self: *ExecutionContext) void {
        self.parameter_bindings.deinit();
    }

    fn findBinding(self: *const ExecutionContext, pattern_idx: CIR.Pattern.Idx) ?ParameterBinding {
        // Search current context first
        for (self.parameter_bindings.items) |binding| {
            if (binding.pattern_idx == pattern_idx) {
                return binding;
            }
        }

        // Search parent contexts
        if (self.parent_context) |parent| {
            return parent.findBinding(pattern_idx);
        }

        return null;
    }
};

/// The Roc expression interpreter.
///
/// This evaluates Roc expressions using an iterative work queue
/// approach with stack-based memory management.
///
/// # Architecture
///
/// ## Work Queue System
/// Uses a LIFO work stack to break complex expressions into atomic operations.
/// This avoids recursion limits and provides better debugging visibility.
///
/// ## Memory Management
/// - **Stack Memory**: All values stored in a single stack for automatic cleanup
/// - **Layout Stack**: Tracks type information parallel to value stack
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
    /// Active parameter bindings for current function call(s)
    parameter_bindings: std.ArrayList(ParameterBinding),
    /// Execution context stack for scope chain management
    execution_contexts: std.ArrayList(ExecutionContext),
    /// Current active execution context (top of stack)
    current_context: ?*ExecutionContext,

    // Debug tracing state
    /// Name/identifier for the current trace session
    trace_name: ?[]const u8,
    /// Indentation level for nested debug output
    trace_indent: u32,
    /// Writer interface for trace output (null when no trace active)
    trace_writer: ?std.io.AnyWriter,
    pub fn init(
        allocator: std.mem.Allocator,
        cir: *const CIR,
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
            .parameter_bindings = std.ArrayList(ParameterBinding).init(allocator),
            .execution_contexts = std.ArrayList(ExecutionContext).init(allocator),
            .current_context = null,

            .trace_name = null,
            .trace_indent = 0,
            .trace_writer = null,
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.work_stack.deinit();
        self.layout_stack.deinit();
        self.parameter_bindings.deinit();

        for (self.execution_contexts.items) |*context| {
            context.deinit();
        }
        self.execution_contexts.deinit();
    }

    /// Evaluates a CIR expression and returns the result.
    ///
    /// This is the main entry point for expression evaluation. Uses an iterative
    /// work queue approach to evaluate complex expressions without recursion.
    pub fn eval(self: *Interpreter, expr_idx: CIR.Expr.Idx) EvalError!EvalResult {
        // Ensure work_stack and layout_stack are empty before we start. (stack_memory might not be, and that's fine!)
        std.debug.assert(self.work_stack.items.len == 0);
        std.debug.assert(self.layout_stack.items.len == 0);
        errdefer self.layout_stack.clearRetainingCapacity();

        // We'll calculate the result pointer at the end based on the final layout

        // Push initial work item
        try self.work_stack.append(.{
            .kind = .eval_expr,
            .expr_idx = expr_idx,
        });

        // Main evaluation loop
        while (self.work_stack.pop()) |work| {
            switch (work.kind) {
                .eval_expr => try self.evalExpr(work.expr_idx),
                .binop_add, .binop_sub, .binop_mul, .binop_div, .binop_eq, .binop_ne, .binop_gt, .binop_lt, .binop_ge, .binop_le => {
                    try self.completeBinop(work.kind);
                },
                .unary_minus => {
                    try self.completeUnaryMinus();
                },
                .if_check_condition => {
                    // The expr_idx encodes both the if expression and the branch index
                    // Lower 16 bits: if expression index
                    // Upper 16 bits: branch index
                    const if_expr_idx: CIR.Expr.Idx = @enumFromInt(@intFromEnum(work.expr_idx) & 0xFFFF);
                    const branch_index: u16 = @intCast((@intFromEnum(work.expr_idx) >> 16) & 0xFFFF);
                    try self.checkIfCondition(if_expr_idx, branch_index);
                },

                // Function call work items

                .alloc_return_space => try self.handleAllocReturnSpace(work.expr_idx),
                .call_function => try self.handleCallFunction(work.expr_idx),
                .bind_parameters => try self.handleBindParameters(work.expr_idx),
                .eval_function_body => try self.handleEvalFunctionBody(work.expr_idx),
                .copy_result_to_return_space => try self.handleCopyResultToReturnSpace(work.expr_idx),
                .cleanup_function => try self.handleCleanupFunction(work.expr_idx),
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

        return EvalResult{
            .layout = final_layout,
            .ptr = @as(*anyopaque, @ptrCast(result_ptr)),
        };
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

        // Check for runtime errors first
        switch (expr) {
            .e_runtime_error => return error.Crash,
            else => {},
        }

        // Get the type variable for this expression
        const expr_var = @as(types.Var, @enumFromInt(@intFromEnum(expr_idx)));

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
                const ptr = self.stack_memory.alloca(size, alignment) catch |err| switch (err) {
                    error.StackOverflow => return error.StackOverflow,
                };

                if (expr_layout.tag == .scalar and expr_layout.data.scalar.tag == .int) {
                    const precision = expr_layout.data.scalar.data.int;
                    writeIntToMemory(@as([*]u8, @ptrCast(ptr)), int_lit.value.toI128(), precision);
                } else {
                    return error.LayoutError;
                }

                try self.layout_stack.append(expr_layout);
            },

            .e_frac_f64 => |float_lit| {
                const ptr = self.stack_memory.alloca(size, alignment) catch |err| switch (err) {
                    error.StackOverflow => return error.StackOverflow,
                };

                const typed_ptr = @as(*f64, @ptrCast(@alignCast(ptr)));
                typed_ptr.* = float_lit.value;

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
                    .add => .binop_add,
                    .sub => .binop_sub,
                    .mul => .binop_mul,
                    .div => .binop_div,
                    .eq => .binop_eq,
                    .ne => .binop_ne,
                    .gt => .binop_gt,
                    .lt => .binop_lt,
                    .ge => .binop_ge,
                    .le => .binop_le,
                    else => return error.Crash,
                };

                try self.work_stack.append(.{
                    .kind = binop_kind,
                    .expr_idx = expr_idx,
                });

                // Push operands in reverse order (right, then left)
                try self.work_stack.append(.{
                    .kind = .eval_expr,
                    .expr_idx = binop.rhs,
                });

                try self.work_stack.append(.{
                    .kind = .eval_expr,
                    .expr_idx = binop.lhs,
                });
            },

            // If expressions
            .e_if => |if_expr| {
                if (if_expr.branches.span.len > 0) {
                    // Push work to check condition after it's evaluated
                    // Encode branch index (0) in upper 16 bits
                    const encoded_idx: CIR.Expr.Idx = @enumFromInt(@intFromEnum(expr_idx));
                    try self.work_stack.append(.{
                        .kind = .if_check_condition,
                        .expr_idx = encoded_idx,
                    });

                    // Push work to evaluate the first condition
                    const branches = self.cir.store.sliceIfBranches(if_expr.branches);
                    const branch = self.cir.store.getIfBranch(branches[0]);

                    try self.work_stack.append(.{
                        .kind = .eval_expr,
                        .expr_idx = branch.cond,
                    });
                } else {
                    // No branches, evaluate final_else directly
                    try self.work_stack.append(.{
                        .kind = .eval_expr,
                        .expr_idx = if_expr.final_else,
                    });
                }
            },

            // Pattern lookup
            .e_lookup_local => |lookup| {
                // First, check parameter bindings (most recent function call)
                for (self.parameter_bindings.items) |binding| {
                    // Check if this binding matches the pattern we're looking for
                    if (binding.pattern_idx == lookup.pattern_idx) {
                        // Found matching parameter binding - copy value to stack
                        const binding_size = self.layout_cache.layoutSize(binding.layout);
                        const binding_alignment = binding.layout.alignment(target.TargetUsize.native);

                        const ptr = self.stack_memory.alloca(binding_size, binding_alignment) catch |err| switch (err) {
                            error.StackOverflow => return error.StackOverflow,
                        };

                        // Copy the parameter value
                        @memcpy(@as([*]u8, @ptrCast(ptr))[0..binding_size], @as([*]u8, @ptrCast(binding.value_ptr))[0..binding_size]);

                        // Debug: check what value we're retrieving
                        self.traceInfo("Retrieved parameter value from binding (pattern {})", .{@intFromEnum(lookup.pattern_idx)});
                        if (binding.layout.tag == .scalar and binding.layout.data.scalar.tag == .int) {
                            const precision = binding.layout.data.scalar.data.int;
                            const retrieved_value = readIntFromMemory(@as([*]u8, @ptrCast(ptr)), precision);
                            self.traceInfo("Retrieved parameter value = {}", .{retrieved_value});
                        }

                        try self.layout_stack.append(binding.layout);
                        return;
                    }
                }

                // If not found in parameters, fall back to global definitions lookup
                const defs = self.cir.store.sliceDefs(self.cir.all_defs);
                for (defs) |def_idx| {
                    const def = self.cir.store.getDef(def_idx);
                    if (@intFromEnum(def.pattern) == @intFromEnum(lookup.pattern_idx)) {
                        // Found the definition, evaluate its expression
                        try self.work_stack.append(.{
                            .kind = .eval_expr,
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
                    .kind = .eval_expr,
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
                // Stack layout: [return_space, function, arg1, arg2, ...]

                // 1. First, clean up after function call completes
                try self.work_stack.append(.{
                    .kind = .cleanup_function,
                    .expr_idx = expr_idx,
                });

                // 2. Then evaluate the function body (writes result to return space)
                try self.work_stack.append(.{
                    .kind = .eval_function_body,
                    .expr_idx = expr_idx,
                });

                // 3. Then bind parameters to arguments
                try self.work_stack.append(.{
                    .kind = .bind_parameters,
                    .expr_idx = expr_idx,
                });

                // 4. Then orchestrate the call (after function and args are evaluated)
                try self.work_stack.append(.{
                    .kind = .call_function,
                    .expr_idx = expr_idx,
                });

                // 5. Evaluate arguments in reverse order (right to left)
                var i = arg_exprs.len;
                while (i > 0) {
                    i -= 1;
                    try self.work_stack.append(.{
                        .kind = .eval_expr,
                        .expr_idx = arg_exprs[i],
                    });
                }

                // 6. Then evaluate the function expression
                try self.work_stack.append(.{
                    .kind = .eval_expr,
                    .expr_idx = function_expr,
                });

                // 7. Finally, allocate return value space (landing pad) first
                try self.work_stack.append(.{
                    .kind = .alloc_return_space,
                    .expr_idx = expr_idx,
                });
            },

            // Unary minus operation
            .e_unary_minus => |unary| {
                // Push work to complete unary minus after operand is evaluated
                try self.work_stack.append(.{
                    .kind = .unary_minus,
                    .expr_idx = expr_idx,
                });

                // Evaluate the operand expression
                try self.work_stack.append(.{
                    .kind = .eval_expr,
                    .expr_idx = unary.expr,
                });
            },

            // Not yet implemented
            .e_str, .e_str_segment, .e_list, .e_tuple, .e_record, .e_dot_access, .e_block, .e_lookup_external, .e_match, .e_frac_dec, .e_dec_small, .e_crash, .e_dbg, .e_expect, .e_ellipsis => {
                return error.LayoutError;
            },

            .e_lambda => |lambda_expr| {
                self.traceEnter("LAMBDA CREATION (expr_idx={})", .{@intFromEnum(expr_idx)});

                // Add detailed debug information about lambda expression
                self.traceInfo("LAMBDA EXPR DETAILS: expr={}, captures.captured_vars.len={}", .{ @intFromEnum(expr_idx), lambda_expr.captures.captured_vars.len });
                self.traceInfo("LAMBDA BODY: body_expr={}", .{@intFromEnum(lambda_expr.body)});

                // NEW APPROACH: Use capture information from canonicalization
                const has_captures = lambda_expr.captures.captured_vars.len > 0;

                self.traceInfo("CAPTURE CALCULATION: len={}, has_captures={}", .{ lambda_expr.captures.captured_vars.len, has_captures });

                // Show lambda type and capture details
                if (has_captures) {
                    self.traceInfo("Lambda WITH captures: {} variables", .{lambda_expr.captures.captured_vars.len});
                    for (lambda_expr.captures.captured_vars, 0..) |capture_var, i| {
                        const name = self.cir.env.idents.getText(capture_var.name);
                        self.traceInfo("CAPTURE VAR[{}]: {s}", .{ i, name });
                    }
                } else {
                    self.traceInfo("Simple lambda: no captures", .{});
                }

                self.traceInfo("Body expr_idx={}, has_captures={}", .{ @intFromEnum(lambda_expr.body), has_captures });

                // Debug capture detection details
                if (lambda_expr.captures.captured_vars.len > 0) {
                    self.tracePrint("Capture analysis: {} variables", .{lambda_expr.captures.captured_vars.len});
                    for (lambda_expr.captures.captured_vars, 0..) |capture_var, i| {
                        self.traceInfo("Capture[{}]: name={s}", .{ i, self.cir.env.idents.getText(capture_var.name) });
                    }
                }

                // Debug the body expression to see what it contains
                const body_expr = self.cir.store.getExpr(lambda_expr.body);
                self.traceInfo("Body expression type: {s}", .{@tagName(body_expr)});
                if (body_expr == .e_lambda) {
                    const inner_lambda = body_expr.e_lambda;
                    self.traceInfo("Inner lambda has {} captures", .{inner_lambda.captures.captured_vars.len});
                    for (inner_lambda.captures.captured_vars, 0..) |capture_var, i| {
                        self.traceInfo("Inner Capture[{}]: name={s}", .{ i, self.cir.env.idents.getText(capture_var.name) });
                    }
                }

                // Create and push closure layout with capture info for later use
                const env_size: u16 = if (has_captures) @intCast(lambda_expr.captures.captured_vars.len) else 0;

                self.traceInfo("LAMBDA LAYOUT CREATION: has_captures={}, captured_vars.len={}, env_size={}", .{ has_captures, lambda_expr.captures.captured_vars.len, env_size });

                const closure_layout = layout.Layout{
                    .tag = .closure,
                    .data = .{ .closure = .{ .env_size = env_size } },
                };
                try self.layout_stack.append(closure_layout);

                self.traceInfo("LAYOUT PUSHED: expr_idx={}, tag={s}, env_size={}", .{ @intFromEnum(expr_idx), @tagName(closure_layout.tag), closure_layout.data.closure.env_size });

                // Detailed closure layout tracking
                self.traceInfo("CLOSURE LAYOUT CREATED: expr={}, env_size={}, stack_depth={}", .{ @intFromEnum(expr_idx), closure_layout.data.closure.env_size, self.layout_stack.items.len });

                self.traceExit("LAMBDA CREATION completed for expr_idx={}", .{@intFromEnum(expr_idx)});
            },
        }
    }

    fn completeBinop(self: *Interpreter, kind: WorkKind) EvalError!void {
        // Pop two layouts (right, then left)
        const right_layout = self.layout_stack.pop() orelse return error.InvalidStackState;
        const left_layout = self.layout_stack.pop() orelse return error.InvalidStackState;

        // For now, only support integer operations
        if (left_layout.tag != .scalar or right_layout.tag != .scalar) {
            return error.LayoutError;
        }

        const lhs_scalar = left_layout.data.scalar;
        const rhs_scalar = right_layout.data.scalar;

        if (lhs_scalar.tag != .int or rhs_scalar.tag != .int) {
            return error.LayoutError;
        }

        // The values are on the stack in order: left, then right
        // We need to calculate where they are based on their layouts
        const right_size = self.layout_cache.layoutSize(right_layout);
        const left_size = self.layout_cache.layoutSize(left_layout);

        // Get pointers to the values
        const rhs_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - right_size;
        const left_ptr = rhs_ptr - left_size;

        // Debug: Stack position calculations
        self.traceInfo("completeBinop stack analysis\n", .{});
        self.traceInfo("stack.used = {}, right_size = {}, left_size = {}\n", .{ self.stack_memory.used, right_size, left_size });
        self.traceInfo("rhs_ptr offset = {}, left_ptr offset = {}\n", .{ self.stack_memory.used - right_size, self.stack_memory.used - right_size - left_size });

        // Read the values
        const lhs_val = readIntFromMemory(@as([*]u8, @ptrCast(left_ptr)), lhs_scalar.data.int);
        const rhs_val = readIntFromMemory(@as([*]u8, @ptrCast(rhs_ptr)), rhs_scalar.data.int);

        // Debug: Values read from memory
        self.traceInfo("Read values - left = {}, right = {}\n", .{ lhs_val, rhs_val });
        self.traceInfo("Left layout: tag={}, precision={}\n", .{ left_layout.tag, lhs_scalar.data.int });
        self.traceInfo("Right layout: tag={}, precision={}\n", .{ right_layout.tag, rhs_scalar.data.int });

        // Pop the operands from the stack
        self.stack_memory.used -= @as(u32, @intCast(left_size + right_size));

        // Determine result layout
        const result_layout = switch (kind) {
            .binop_add, .binop_sub, .binop_mul, .binop_div => left_layout, // Numeric result
            .binop_eq, .binop_ne, .binop_gt, .binop_lt, .binop_ge, .binop_le => blk: {
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

        // Allocate space for result
        const result_size = self.layout_cache.layoutSize(result_layout);
        const result_alignment = result_layout.alignment(target.TargetUsize.native);
        const result_ptr = self.stack_memory.alloca(result_size, result_alignment) catch |err| switch (err) {
            error.StackOverflow => return error.StackOverflow,
        };

        // Perform the operation
        switch (kind) {
            .binop_add => {
                const result_val: i128 = lhs_val + rhs_val;
                self.traceInfo("Addition operation: {} + {} = {}\n", .{ lhs_val, rhs_val, result_val });
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_scalar.data.int);

                {
                    // Debug: Verify what was written to memory
                    const verification = readIntFromMemory(@as([*]u8, @ptrCast(result_ptr)), lhs_scalar.data.int);
                    self.traceInfo("Verification read from result memory = {}\n", .{verification});
                }
            },
            .binop_sub => {
                const result_val: i128 = lhs_val - rhs_val;
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_scalar.data.int);
            },
            .binop_mul => {
                const result_val: i128 = lhs_val * rhs_val;
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_scalar.data.int);
            },
            .binop_div => {
                if (rhs_val == 0) {
                    return error.DivisionByZero;
                }
                const result_val: i128 = @divTrunc(lhs_val, rhs_val);
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_scalar.data.int);
            },
            .binop_eq => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val == rhs_val) 1 else 0;
            },
            .binop_ne => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val != rhs_val) 1 else 0;
            },
            .binop_gt => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val > rhs_val) 1 else 0;
            },
            .binop_lt => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val < rhs_val) 1 else 0;
            },
            .binop_ge => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val >= rhs_val) 1 else 0;
            },
            .binop_le => {
                const bool_ptr = @as(*u8, @ptrCast(@alignCast(result_ptr)));
                bool_ptr.* = if (lhs_val <= rhs_val) 1 else 0;
            },
            else => unreachable,
        }

        // Push result layout
        try self.layout_stack.append(result_layout);
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

        self.traceInfo("Unary minus operation: -{} = {}\n", .{ operand_val, -operand_val });

        // Negate the value and write it back to the same location
        const result_val: i128 = -operand_val;
        writeIntToMemory(@as([*]u8, @ptrCast(operand_ptr)), result_val, operand_scalar.data.int);

        // Push result layout (same as operand layout)
        try self.layout_stack.append(operand_layout);
    }

    fn checkIfCondition(self: *Interpreter, expr_idx: CIR.Expr.Idx, branch_index: u16) EvalError!void {
        // Pop the condition layout
        _ = self.layout_stack.pop() orelse return error.InvalidStackState; // Remove condition layout

        // Read the condition value
        const cond_size = 1; // Boolean is u8
        const cond_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - cond_size;
        const cond_val = @as(*u8, @ptrCast(@alignCast(cond_ptr))).*;

        // Pop the condition from the stack
        self.stack_memory.used -= cond_size;

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

        if (cond_val == 1) {
            // Condition is true, evaluate this branch's body
            try self.work_stack.append(.{
                .kind = .eval_expr,
                .expr_idx = branch.body,
            });
        } else {
            // Condition is false, check if there's another branch
            if (branch_index + 1 < branches.len) {
                // Evaluate the next branch
                const next_branch_idx = branch_index + 1;
                const next_branch = self.cir.store.getIfBranch(branches[next_branch_idx]);

                // Push work to check next condition after it's evaluated
                // Encode branch index in upper 16 bits
                const encoded_idx: CIR.Expr.Idx = @enumFromInt(@intFromEnum(expr_idx) | (@as(u32, next_branch_idx) << 16));
                try self.work_stack.append(.{
                    .kind = .if_check_condition,
                    .expr_idx = encoded_idx,
                });

                // Push work to evaluate the next condition
                try self.work_stack.append(.{
                    .kind = .eval_expr,
                    .expr_idx = next_branch.cond,
                });
            } else {
                // No more branches, evaluate final_else
                try self.work_stack.append(.{
                    .kind = .eval_expr,
                    .expr_idx = if_expr.final_else,
                });
            }
        }
    }

    /// Allocates appropriately-sized and aligned memory for the function's return value
    /// before any arguments or the function itself are evaluated.
    ///
    /// # Purpose
    /// - Provides a stable location for the return value
    /// - Ensures correct memory alignment for the return type
    /// - Establishes the base of the function call frame
    ///
    /// # Stack Effects
    /// - Allocates `return_size` bytes on `stack_memory`
    /// - Pushes return layout onto `layout_stack`
    /// - Memory is properly aligned for the return type
    ///
    /// # Call Frame Layout
    /// After this step: `[return_space]`
    /// Eventually becomes: `[return_space, function, arg1, arg2, ...]`
    fn handleAllocReturnSpace(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        // Allocate space for the return value (landing pad)
        // At this point, we need to know the return type to allocate the right amount of space

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
        try self.layout_stack.append(return_layout);

        self.traceLayout("return_space", return_layout);
        self.traceSuccess("Allocated return space: {} bytes", .{return_size});
    }

    fn handleCallFunction(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.traceEnter("CALL FUNCTION (expr_idx={})", .{@intFromEnum(call_expr_idx)});
        defer self.traceExit("CALL FUNCTION completed", .{});

        self.traceStackState("call_function_entry");

        // Get the call expression to find argument count
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => {
                self.traceError("Invalid call expression type: {s}", .{@tagName(call_expr)});
                return error.LayoutError;
            },
        };

        // LANDING PAD: Allocate closure space now, during call setup
        // Get function expression to determine closure requirements
        const all_exprs_for_closure = self.cir.store.sliceExpr(call.args);
        const function_expr = self.cir.store.getExpr(all_exprs_for_closure[0]);

        self.traceInfo("CALL FUNCTION: checking expr type for LANDING PAD decision: {s}", .{@tagName(function_expr)});

        self.traceInfo("FUNCTION EXPR TYPE: {s} for call_expr={}", .{ @tagName(function_expr), @intFromEnum(call_expr_idx) });

        if (function_expr == .e_lambda) {
            self.tracePrint("LANDING PAD: Allocating closure space for lambda function", .{});
            const lambda_expr = function_expr.e_lambda;
            const has_captures = lambda_expr.captures.captured_vars.len > 0;

            // Allocate closure space using the same pattern as return space
            const closure_size: usize = if (has_captures) @sizeOf(Closure) else @sizeOf(SimpleClosure);
            const closure_alignment: std.mem.Alignment = .@"8";

            // Debug closure sizes with layout embedding
            const old_closure_size = 16; // body_expr_idx (4) + args_pattern_span (8) + captured_env (8)
            const old_simple_size = 12; // body_expr_idx (4) + args_pattern_span (8)
            const layout_size = @sizeOf(layout.Layout);

            self.traceInfo("SIZE CHECK: Closure={} (was ~{}), SimpleClosure={} (was ~{}), Layout={}", .{ @sizeOf(Closure), old_closure_size, @sizeOf(SimpleClosure), old_simple_size, layout_size });
            self.traceInfo("Allocating {} bytes for {s} closure", .{ closure_size, if (has_captures) "full" else "simple" });

            const closure_ptr = self.stack_memory.alloca(@intCast(closure_size), closure_alignment) catch |err| switch (err) {
                error.StackOverflow => return error.StackOverflow,
            };

            // Create and store closure layout with capture info
            const closure_layout = layout.Layout{
                .tag = .closure,
                .data = .{ .closure = .{ .env_size = @intCast(lambda_expr.captures.captured_vars.len) } },
            };
            self.traceInfo("Created closure_layout with env_size={}", .{closure_layout.data.closure.env_size});

            // Initialize the closure at the allocated position
            if (has_captures) {
                const closure = @as(*Closure, @ptrCast(@alignCast(closure_ptr)));
                closure.* = Closure{
                    .body_expr_idx = lambda_expr.body,
                    .args_pattern_span = lambda_expr.args,
                    .captured_env = null,
                    .layout = closure_layout,
                };
                self.traceInfo("Initialized full Closure with embedded layout env_size={}", .{closure.layout.data.closure.env_size});
                self.traceClosure("allocated full", closure_ptr, true);
            } else {
                const closure = @as(*SimpleClosure, @ptrCast(@alignCast(closure_ptr)));
                closure.* = SimpleClosure{
                    .body_expr_idx = lambda_expr.body,
                    .args_pattern_span = lambda_expr.args,
                    .layout = closure_layout,
                };
                self.traceInfo("Initialized SimpleClosure with embedded layout env_size={}", .{closure.layout.data.closure.env_size});
                self.traceClosure("allocated simple", closure_ptr, false);
            }

            self.traceSuccess("LANDING PAD: Closure allocated with embedded layout (env_size={})", .{closure_layout.data.closure.env_size});
        } else if (function_expr == .e_call) {
            // This is calling a closure that was returned from another function call
            // Layout information is embedded in the closure, so no special handling needed
            self.traceInfo("DETECTED e_call CASE: calling returned closure for call_expr={}", .{@intFromEnum(call_expr_idx)});
            self.traceInfo("Layout information will be read from embedded closure data", .{});
        }

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        // Check that we have enough items on the layout stack
        if (self.layout_stack.items.len < arg_count + 1) {
            self.traceError("Insufficient layout items: have {}, need {}", .{ self.layout_stack.items.len, arg_count + 1 });
            return error.InvalidStackState;
        }

        // Layout stack validation
        if (DEBUG_ENABLED and self.layout_stack.items.len != arg_count + 1) {
            self.traceInfo("Layout stack mismatch in call_function_validation: expected={}, actual={}\n", .{ arg_count + 1, self.layout_stack.items.len });
        }

        // Access the function layout (it's at the bottom of our function call portion)
        const function_layout_idx = self.layout_stack.items.len - arg_count - 1;
        const function_layout = self.layout_stack.items[function_layout_idx];

        // Verify it's a closure
        if (function_layout.tag != .closure) {
            self.traceError("Expected closure but got: {s}", .{@tagName(function_layout.tag)});
            return error.Crash; // "Not a function" error
        }

        // Check if function has captures and add capture record as hidden argument
        self.traceInfo("📞 ABOUT TO HANDLE CAPTURE ARGUMENTS for expr={}\n", .{@intFromEnum(call_expr_idx)});

        try self.handleCaptureArguments(call_expr_idx, function_layout_idx);

        self.traceInfo("📞 FINISHED HANDLING CAPTURE ARGUMENTS for expr={}\n", .{@intFromEnum(call_expr_idx)});

        self.tracePrint("⚪ 📍 PHASE: call_ready_for_binding (expr_idx={})", .{@intFromEnum(call_expr_idx)});

        // The function and arguments are now ready for parameter binding
        // Nothing else to do here - the next work item will handle binding
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

        // Calculate closure position on stack
        var stack_pos = self.stack_memory.used;
        for (0..function_layout_idx) |i| {
            const layout_idx = self.layout_stack.items.len - 1 - i;
            const layout_item = self.layout_stack.items[layout_idx];
            const item_size = self.layout_cache.layoutSize(layout_item);
            stack_pos -= item_size;
        }

        // Cast to closure and read embedded layout information
        const closure_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + stack_pos;
        self.traceInfo("Reading closure at stack_pos={}, function_layout.env_size={}", .{ stack_pos, function_layout.data.closure.env_size });

        const embedded_layout = if (function_layout.data.closure.env_size > 0) blk: {
            const full_closure = @as(*Closure, @ptrCast(@alignCast(closure_ptr)));
            self.traceInfo("Reading full Closure: body_expr={}, embedded_env_size={}", .{ @intFromEnum(full_closure.body_expr_idx), full_closure.layout.data.closure.env_size });
            break :blk full_closure.layout;
        } else blk: {
            const simple_closure = @as(*SimpleClosure, @ptrCast(@alignCast(closure_ptr)));
            self.traceInfo("Reading SimpleClosure: body_expr={}, embedded_env_size={}", .{ @intFromEnum(simple_closure.body_expr_idx), simple_closure.layout.data.closure.env_size });
            break :blk simple_closure.layout;
        };

        self.traceInfo("CAPTURE CHECK: tag={s}, env_size={}", .{ @tagName(embedded_layout.tag), embedded_layout.data.closure.env_size });

        if (embedded_layout.data.closure.env_size == 0) {
            self.traceInfo("EARLY RETURN: Closure has no captures (env_size=0)", .{});
            return;
        }

        self.traceInfo("ADDING CAPTURE RECORD: env_size={}, call_expr={}", .{ embedded_layout.data.closure.env_size, @intFromEnum(call_expr_idx) });

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
                self.traceInfo("🎯 CLOSURE CALL WITH CAPTURES: env_size={}\n", .{function_layout.data.closure.env_size});

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
                const capture_layout = layout.Layout{
                    .tag = .scalar,
                    .data = .{ .scalar = .{ .tag = .int, .data = .{ .int = .i64 } } },
                };
                try self.layout_stack.append(capture_layout);

                self.traceInfo("✅ CLOSURE CAPTURE RECORD PUSHED: {} vars\n", .{num_captures});

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
        const capture_layout = layout.Layout{
            .tag = .scalar,
            .data = .{ .scalar = .{ .tag = .int, .data = .{ .int = .i64 } } },
        };
        try self.layout_stack.append(capture_layout);

        self.traceInfo("✅ CAPTURE RECORD PUSHED: {} vars\n", .{lambda_captures.captured_vars.len});
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
    ///
    /// Creates parameter bindings that map argument values to parameter patterns,
    /// enabling variable lookup during function body evaluation.
    ///
    /// # Process
    /// 1. Extract argument layouts and stack positions
    /// 2. Create ParameterBinding for each argument-parameter pair
    /// 3. Store bindings for use during variable lookup
    ///
    /// # Current Limitations
    /// - Only single-parameter functions supported
    /// - Simple pattern matching (no destructuring)
    /// - Linear search for parameter lookups
    ///
    /// # Stack State
    /// At entry: `[return_space, function, args...]`
    /// No stack changes - only creates bindings in `parameter_bindings`
    ///
    /// # Future Enhancements
    /// - Multi-parameter support
    /// - Pattern destructuring (tuples, records)
    /// - Optimized parameter lookup (hash maps)
    fn handleBindParameters(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.traceEnter("handleBindParameters(expr_idx={})", .{@intFromEnum(call_expr_idx)});
        defer self.traceExit("handleBindParameters", .{});

        // Get the call expression to determine argument count
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => {
                self.traceError("Invalid call expression in bind_parameters: {s}", .{@tagName(call_expr)});
                return error.LayoutError;
            },
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        if (self.layout_stack.items.len < arg_count + 1) {
            self.traceError("Layout stack underflow: have {}, need {}", .{ self.layout_stack.items.len, arg_count + 1 });
            return error.InvalidStackState;
        }

        // Layout stack validation
        if (DEBUG_ENABLED and self.layout_stack.items.len != arg_count + 1) {
            self.traceInfo("Layout stack mismatch in bind_parameters_entry: expected={}, actual={}\n", .{ arg_count + 1, self.layout_stack.items.len });
        }

        self.traceStackState("bind_parameters_start");
        self.traceInfo("Argument count: {}", .{arg_count});

        // Calculate function position on stack using layout positions
        // Stack layout: [return_space, function, arg1, arg2, ...]

        // Function position is calculated by summing sizes of all items that come after it
        // Layout stack is ordered with function at index: len - 1 - arg_count
        const function_layout_idx = self.layout_stack.items.len - 1 - arg_count;

        // Get the function layout
        const function_layout = self.layout_stack.items[function_layout_idx];

        // LANDING PAD APPROACH: Calculate closure position and read embedded layout
        var stack_pos = self.stack_memory.used;
        for (0..function_layout_idx) |i| {
            const layout_idx = self.layout_stack.items.len - 1 - i;
            const layout_item = self.layout_stack.items[layout_idx];
            const item_size = self.layout_cache.layoutSize(layout_item);
            stack_pos -= item_size;
        }

        const closure_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + stack_pos;

        // Read layout information directly from closure
        const embedded_layout = if (function_layout.tag == .closure and function_layout.data.closure.env_size > 0) blk: {
            const full_closure = @as(*Closure, @ptrCast(@alignCast(closure_ptr)));
            break :blk full_closure.layout;
        } else blk: {
            const simple_closure = @as(*SimpleClosure, @ptrCast(@alignCast(closure_ptr)));
            break :blk simple_closure.layout;
        };

        self.traceInfo("USING EMBEDDED CLOSURE LAYOUT: env_size={}", .{embedded_layout.data.closure.env_size});

        const function_stack_pos = @intFromPtr(closure_ptr) - @intFromPtr(self.stack_memory.start);
        self.tracePrint("LANDING PAD: Using stored closure pointer at position {}", .{function_stack_pos});

        if (function_layout.tag == .closure) {
            self.tracePrint("⚪ 📍 PHASE: function_position_located (expr_idx={})", .{@intFromEnum(call_expr_idx)});
        }

        // Assert position is valid
        std.debug.assert(function_stack_pos >= 0);

        // Get the function closure from the stack
        if (function_layout.tag != .closure) {
            return error.LayoutError; // Function must be a closure
        }

        // Handle both SimpleClosure and Closure types based on captures
        const has_captures = function_layout.data.closure.env_size > 0;

        const closure_body_expr_idx: CIR.Expr.Idx = if (has_captures) blk: {
            const full_closure_ptr = @as(*Closure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            self.traceClosure("reading full", full_closure_ptr, true);
            break :blk full_closure_ptr.body_expr_idx;
        } else blk: {
            const simple_closure_ptr = @as(*SimpleClosure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            self.traceClosure("reading simple", simple_closure_ptr, false);
            break :blk simple_closure_ptr.body_expr_idx;
        };

        const closure_args_pattern_span: CIR.Pattern.Span = if (has_captures) blk: {
            const full_closure_ptr = @as(*Closure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            break :blk full_closure_ptr.args_pattern_span;
        } else blk: {
            const simple_closure_ptr = @as(*SimpleClosure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            break :blk simple_closure_ptr.args_pattern_span;
        };

        // Enhanced debugging for position calculation
        self.traceInfo("📍 STACK POSITION CALCULATION:\n", .{});
        self.traceInfo("function_layout_idx={}, arg_count={}\n", .{ function_layout_idx, arg_count });
        self.traceInfo("layout_stack.len={}\n", .{self.layout_stack.items.len});
        self.traceInfo("calculated function_stack_pos={}\n", .{function_stack_pos});
        self.traceInfo("stack_memory.start={}\n", .{@intFromPtr(self.stack_memory.start)});
        self.traceInfo("function_stack_pos={}\n", .{function_stack_pos});

        // Show the layout items being summed for position calculation
        self.traceInfo("Items after function (summed for position):\n", .{});
        for (self.layout_stack.items[function_layout_idx + 1 ..], function_layout_idx + 1..) |item_layout, i| {
            const item_size = self.layout_cache.layoutSize(item_layout);
            self.traceInfo("  [{d}] {s} size={}\n", .{ i, @tagName(item_layout.tag), item_size });
        }

        // Debug: Verify our calculated position
        self.traceInfo("🔍 POSITION CHECK: pos={}, body={}, span_len={}\n", .{ function_stack_pos, @intFromEnum(closure_body_expr_idx), closure_args_pattern_span.span.len });

        // Verify closure integrity
        if (has_captures) {
            const full_closure_ptr = @as(*Closure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            self.traceClosure("verified full", full_closure_ptr, true);
        } else {
            const simple_closure_ptr = @as(*SimpleClosure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            self.traceClosure("verified simple", simple_closure_ptr, false);
        }

        self.traceInfo("🔍 VALIDATING CLOSURE BODY: body_expr_idx={}\n", .{@intFromEnum(closure_body_expr_idx)});
        self.traceInfo("🔍 CLOSURE PTR: body={}, args_span_len={}\n", .{ @intFromEnum(closure_body_expr_idx), closure_args_pattern_span.span.len });

        self.traceInfo("🎯 PARAMETER BINDING: closure with {} args\n", .{closure_args_pattern_span.span.len});

        const parameter_patterns = self.cir.store.slicePatterns(closure_args_pattern_span);

        // For closures with captures, we expect one extra argument (the capture record)
        const expected_args = if (has_captures) parameter_patterns.len + 1 else parameter_patterns.len;

        if (expected_args != arg_count) {
            // FORCE DEBUG: Always show arity mismatch details
            self.traceInfo("🚨 ARITY MISMATCH DETAILS:\n", .{});
            self.traceInfo(" Expected: {} (pattern_params={}, has_captures={})\n", .{ expected_args, parameter_patterns.len, has_captures });
            self.traceInfo(" Actual:   {}\n", .{arg_count});
            self.traceInfo(" Function layout env_size: {}\n", .{function_layout.data.closure.env_size});
            self.traceInfo(" Function body expr: {}\n", .{@intFromEnum(closure_body_expr_idx)});
            return error.ArityMismatch;
        }

        // Bind regular parameters (ignore capture record for now)

        // Multi-parameter binding: handle any number of parameters
        // Arguments are on the stack in order, with the last argument at the top

        // Calculate starting position for arguments by working backwards from stack top
        var current_stack_pos = self.stack_memory.used;

        // Create bindings for each parameter in reverse order (since stack grows upward)
        for (0..arg_count) |i| {
            const arg_idx = arg_count - 1 - i; // Process arguments in reverse order
            const arg_layout = self.layout_stack.items[self.layout_stack.items.len - 1 - i];
            const arg_size = self.layout_cache.layoutSize(arg_layout);

            // Move to the position of this argument
            current_stack_pos -= arg_size;

            // Use the actual parameter pattern from the lambda
            const parameter_pattern_idx = parameter_patterns[arg_idx];

            const binding = ParameterBinding{
                .pattern_idx = parameter_pattern_idx,
                .value_ptr = @as(*anyopaque, @ptrCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + current_stack_pos)),
                .layout = arg_layout,
            };

            // Trace parameter binding
            self.traceInfo("BIND param[{}] pattern={} at pos={} ({s})\n", .{ arg_idx, @intFromEnum(parameter_pattern_idx), current_stack_pos, @tagName(arg_layout.tag) });

            try self.parameter_bindings.append(binding);
        }

        // Push new execution context with current parameter bindings
        var new_context = try ExecutionContext.init(self.allocator, self.current_context);

        // Copy current parameter bindings to the new context
        try new_context.parameter_bindings.appendSlice(self.parameter_bindings.items);

        // Add context to stack and make it current
        try self.execution_contexts.append(new_context);
        self.current_context = &self.execution_contexts.items[self.execution_contexts.items.len - 1];

        // Final state verification and summary
        self.traceInfo("BIND SUMMARY: {} parameters bound, stack_used={}\n", .{ arg_count, self.stack_memory.used });
        self.traceInfo("CONTEXT STACK: {} contexts deep\n", .{self.execution_contexts.items.len});
        self.traceInfo("bind_parameters_complete: stack={d:.1}B/{d:.1}KB ({d:.1}%), layouts={}, bindings={}, work={}\n", .{
            @as(f64, @floatFromInt(self.stack_memory.used)),
            @as(f64, @floatFromInt(self.stack_memory.capacity)) / 1024.0,
            @as(f64, @floatFromInt(self.stack_memory.used)) / @as(f64, @floatFromInt(self.stack_memory.capacity)) * 100.0,
            self.layout_stack.items.len,
            self.parameter_bindings.items.len,
            self.work_stack.items.len,
        });
    }

    fn handleEvalFunctionBody(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.traceEnter("EVAL FUNCTION BODY (expr_idx={})", .{@intFromEnum(call_expr_idx)});
        defer self.traceExit("EVAL FUNCTION BODY completed", .{});

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

        // Extract the lambda body from the function expression
        const lambda_body = switch (function_expr) {
            .e_lambda => |lambda| lambda.body,
            else => return error.Crash, // Called non-lambda
        };

        // Add work to copy result to return space after body evaluation
        try self.work_stack.append(.{
            .kind = .copy_result_to_return_space,
            .expr_idx = call_expr_idx,
        });

        // Push work to evaluate the lambda's body expression
        try self.work_stack.append(.{
            .kind = .eval_expr,
            .expr_idx = lambda_body,
        });
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

        self.traceInfo("=== COPY RESULT TO RETURN SPACE ===\n", .{});
        self.traceInfo("Initial stack.used = {}\n", .{self.stack_memory.used});
        self.traceInfo("Layout stack size = {}\n", .{self.layout_stack.items.len});

        // The body result is at the top of the stack
        const body_result_layout = self.layout_stack.pop() orelse return error.InvalidStackState;
        const body_result_size = self.layout_cache.layoutSize(body_result_layout);

        // Detailed closure layout tracking during result copy
        if (body_result_layout.tag == .closure) {
            self.traceInfo("POPPING RESULT LAYOUT: tag=closure, env_size={}, remaining_stack_depth={}", .{ body_result_layout.data.closure.env_size, self.layout_stack.items.len });
        }

        // Calculate position of body result
        const body_result_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - body_result_size;

        self.traceInfo("Body result layout = {}, size = {}\n", .{ body_result_layout.tag, body_result_size });
        self.traceInfo("Body result at stack position = {}\n", .{self.stack_memory.used - body_result_size});

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

        // Calculate stack positions working backwards from current position
        // Stack layout: [return_space, function, arg1, arg2, ..., body_result]
        var stack_pos = self.stack_memory.used;

        self.traceInfo("Starting stack position calculation from {}\n", .{stack_pos});

        // Skip the body result we just calculated
        stack_pos -= body_result_size;

        self.traceInfo("After skipping body result: stack_pos = {}\n", .{stack_pos});

        // Skip the arguments
        for (0..arg_count) |i| {
            const layout_idx = self.layout_stack.items.len - 1 - i;
            const arg_layout = self.layout_stack.items[layout_idx];
            const arg_size = self.layout_cache.layoutSize(arg_layout);
            stack_pos -= arg_size;

            self.traceInfo("After skipping arg {}: layout={}, size={}, stack_pos = {}\n", .{ i, arg_layout.tag, arg_size, stack_pos });
        }

        // Skip the function
        const function_layout = self.layout_stack.items[self.layout_stack.items.len - arg_count - 1];
        const function_size = self.layout_cache.layoutSize(function_layout);
        stack_pos -= function_size;

        self.traceInfo("After skipping function: layout={}, size={}, stack_pos = {}\n", .{ function_layout.tag, function_size, stack_pos });

        // Now we're at the return space
        const return_space_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + stack_pos;

        if (DEBUG_ENABLED) {
            self.traceInfo("Final return space position = {}\n", .{stack_pos});
            self.traceInfo("Copying {} bytes from {} to {}\n", .{ body_result_size, self.stack_memory.used - body_result_size, stack_pos });

            // Verify the copy source data before copying
            const source_bytes = @as([*]u8, @ptrCast(body_result_ptr));
            self.traceInfo("Source bytes: ", .{});
            for (0..@min(body_result_size, 16)) |i| {
                self.traceInfo("{x:0>2} ", .{source_bytes[i]});
            }
            self.traceInfo("\n", .{});
        }

        // Copy the result
        @memcpy(return_space_ptr[0..body_result_size], body_result_ptr[0..body_result_size]);

        // Verify the copy destination data after copying
        if (DEBUG_ENABLED) {
            const dest_bytes = @as([*]u8, @ptrCast(return_space_ptr));
            self.traceInfo("Dest bytes after copy: ", .{});
            for (0..@min(body_result_size, 16)) |i| {
                self.traceInfo("{x:0>2} ", .{dest_bytes[i]});
            }
            self.traceInfo("\n", .{});
        }

        // Pop the body result from stack
        self.stack_memory.used -= @as(u32, @intCast(body_result_size));

        if (DEBUG_ENABLED) {
            self.traceInfo("After popping body result: stack.used = {}\n", .{self.stack_memory.used});

            // Don't push the layout - the return space layout is already on the stack
            self.traceInfo("=== END COPY RESULT TO RETURN SPACE ===\n", .{});
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
        self.traceEnter("CLEANUP FUNCTION (expr_idx={})", .{@intFromEnum(call_expr_idx)});

        // No longer need to manage closure_info_stack since layout is embedded in closures
        self.tracePrint("Cleanup: closure layout information is embedded in closure data", .{});

        // Remove parameter bindings that were added for this function call
        self.parameter_bindings.clearRetainingCapacity();

        // Pop execution context from stack
        if (self.execution_contexts.items.len > 0) {
            // Call deinit on the last context before removing it
            self.execution_contexts.items[self.execution_contexts.items.len - 1].deinit();
            _ = self.execution_contexts.pop();

            // Update current context to parent (or null if stack is empty)
            self.current_context = if (self.execution_contexts.items.len > 0)
                &self.execution_contexts.items[self.execution_contexts.items.len - 1]
            else
                null;

            self.traceInfo("CONTEXT STACK: {} contexts remaining after cleanup\n", .{self.execution_contexts.items.len});
        }

        if (DEBUG_ENABLED) {
            self.traceInfo("=== CLEANUP FUNCTION ===\n", .{});
            self.traceInfo("Before cleanup: stack.used = {}, layout_stack.len = {}\n", .{ self.stack_memory.used, self.layout_stack.items.len });
        }

        // Get call information
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        // Layout stack currently has: [return_layout, function_layout, arg_layouts...]
        if (self.layout_stack.items.len < arg_count + 2) {
            return error.InvalidStackState;
        }

        // Get the return layout (at bottom of call frame)
        const return_layout = self.layout_stack.items[self.layout_stack.items.len - arg_count - 2];
        const return_size = self.layout_cache.layoutSize(return_layout);

        // Calculate total size of function and arguments to remove
        var cleanup_size: u32 = 0;

        // Function size
        const function_layout = self.layout_stack.items[self.layout_stack.items.len - arg_count - 1];
        cleanup_size += @as(u32, @intCast(self.layout_cache.layoutSize(function_layout)));

        // Argument sizes
        for (0..arg_count) |i| {
            const arg_layout = self.layout_stack.items[self.layout_stack.items.len - 1 - i];
            cleanup_size += @as(u32, @intCast(self.layout_cache.layoutSize(arg_layout)));
        }

        if (DEBUG_ENABLED) {
            self.traceInfo("Return size = {}, cleanup size = {}\n", .{ return_size, cleanup_size });
        }

        // Calculate where the return value currently is (same as copy operation)
        // Stack layout after copy: [return_value@landing_pad, function, args...]
        var current_stack_pos = self.stack_memory.used;

        // Skip arguments (working backwards)
        for (0..arg_count) |i| {
            const arg_layout = self.layout_stack.items[self.layout_stack.items.len - 1 - i];
            const arg_size = self.layout_cache.layoutSize(arg_layout);
            current_stack_pos -= arg_size;
        }

        // Skip function
        current_stack_pos -= self.layout_cache.layoutSize(function_layout);

        // Now current_stack_pos points to the return value
        const return_value_current_pos = current_stack_pos;

        if (DEBUG_ENABLED) {
            self.traceInfo("Moving return value from {} to 0, size={}\n", .{ return_value_current_pos, return_size });
        }

        // Move return value from current position to position 0
        const source_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + return_value_current_pos;
        const dest_ptr = @as([*]u8, @ptrCast(self.stack_memory.start));
        std.mem.copyForwards(u8, dest_ptr[0..return_size], source_ptr[0..return_size]);

        // Update stack to contain only the return value
        self.stack_memory.used = @as(u32, @intCast(return_size));

        if (DEBUG_ENABLED) {
            self.traceInfo("After cleanup: stack.used = {}\n", .{self.stack_memory.used});
        }

        // Clean up layout stack: remove all call-related layouts except return
        const layouts_to_remove = arg_count + 1; // function + arguments

        // Remove function and argument layouts (but keep return layout)
        for (0..layouts_to_remove) |_| {
            _ = self.layout_stack.pop() orelse return error.InvalidStackState;
        }

        // The return layout should now be at the top of layout stack
        if (DEBUG_ENABLED) {
            self.traceInfo("After layout cleanup: layout_stack.len = {}\n", .{self.layout_stack.items.len});
            self.traceInfo("=== END CLEANUP FUNCTION ===\n", .{});
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
    pub fn startTrace(self: *Interpreter, trace_name: []const u8, writer: std.io.AnyWriter) void {
        if (!DEBUG_ENABLED) return;
        self.trace_name = trace_name;
        self.trace_indent = 0;
        self.trace_writer = writer;
        writer.print("\n🚀 TRACE START: {s}\n", .{trace_name}) catch {};
        writer.print("═══════════════════════════════════════\n", .{}) catch {};
    }

    /// End the current debug trace session
    /// Only has effect if DEBUG_ENABLED is true
    pub fn endTrace(self: *Interpreter) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            writer.print("═══════════════════════════════════════\n", .{}) catch {};
            if (self.trace_name) |name| {
                writer.print("✅ TRACE END: {s}\n\n", .{name}) catch {};
            } else {
                writer.print("✅ TRACE END\n\n", .{}) catch {};
            }
        }
        self.trace_name = null;
        self.trace_indent = 0;
        self.trace_writer = null;
    }

    /// Print indentation for current trace level
    fn printTraceIndent(self: *const Interpreter) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            var i: u32 = 0;
            while (i < self.trace_indent) : (i += 1) {
                writer.print("", .{}) catch {};
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

    /// Trace closure information
    pub fn traceClosure(self: *const Interpreter, label: []const u8, closure_ptr: anytype, has_captures: bool) void {
        if (!DEBUG_ENABLED) return;
        if (self.trace_writer) |writer| {
            self.printTraceIndent();
            const pos = @intFromPtr(closure_ptr) - @intFromPtr(self.stack_memory.start);
            if (has_captures) {
                const closure = @as(*Closure, @ptrCast(@alignCast(closure_ptr)));
                writer.print("🏗️  CLOSURE ({s}): pos={}, body={}, args_len={}, has_captures=true\n", .{
                    label,
                    pos,
                    @intFromEnum(closure.body_expr_idx),
                    closure.args_pattern_span.span.len,
                }) catch {};
            } else {
                const closure = @as(*SimpleClosure, @ptrCast(@alignCast(closure_ptr)));
                writer.print("🏗️  CLOSURE ({s}): pos={}, body={}, args_len={}, has_captures=false\n", .{
                    label,
                    pos,
                    @intFromEnum(closure.body_expr_idx),
                    closure.args_pattern_span.span.len,
                }) catch {};
            }
        }
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
    _ = @import("eval_test.zig");
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
        try interpreter.completeBinop(.binop_add);

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
        try interpreter.completeBinop(.binop_gt);

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
