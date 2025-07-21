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

/// Entry in the captured environments registry
const CapturedEnvironmentEntry = struct {
    position: usize,
    env: *CapturedEnvironment,
};

/// Enhanced closure structure with captured environment support
pub const Closure = struct {
    body_expr_idx: CIR.Expr.Idx, // What expression to execute
    args_pattern_span: CIR.Pattern.Span, // Parameters to bind
    captured_env: ?*CapturedEnvironment, // Captured variables from outer scopes
};

/// Simple closure structure for backward compatibility
pub const SimpleClosure = struct {
    body_expr_idx: CIR.Expr.Idx, // What expression to execute
    args_pattern_span: CIR.Pattern.Span, // Parameters to bind
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
    if (DEBUG_ENABLED) {
        std.debug.print("🏗️  INIT CAPTURE ENV: {} variables to capture\n", .{captured_vars.len});
    }
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
                    if (DEBUG_ENABLED) {
                        std.debug.print("🔍 FOUND in execution context: pattern={}\n", .{@intFromEnum(pattern_idx)});
                    }
                    break;
                }
                context = ctx.parent_context;
            }
        }

        if (found_value == null) {
            // This should not happen if capture analysis is correct
            if (DEBUG_ENABLED) {
                std.debug.print("❌ CAPTURE ERROR: pattern {} not found in parameter bindings or execution contexts\n", .{@intFromEnum(pattern_idx)});
            }
            return error.CaptureError;
        }

        // Calculate size and copy value data
        const value_layout = found_layout.?;

        if (DEBUG_ENABLED) {
            std.debug.print("  📦 CAPTURING[{}]: pattern={}, size={} bytes\n", .{ i, @intFromEnum(pattern_idx), self.layout_cache.layoutSize(value_layout) });
        }
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
    if (DEBUG_ENABLED) {
        std.debug.print("🔍 LOOKUP VAR: pattern={}, has_env={}\n", .{ @intFromEnum(pattern_idx), env != null });
    }

    const result = self.searchCapturedEnvironment(pattern_idx, env);

    if (DEBUG_ENABLED) {
        if (result) |binding| {
            std.debug.print("✅ VAR FOUND: pattern={}, layout={s}\n", .{ @intFromEnum(binding.pattern_idx), @tagName(binding.layout.tag) });
        } else {
            std.debug.print("❌ VAR NOT FOUND: pattern={}\n", .{@intFromEnum(pattern_idx)});
        }
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
        if (DEBUG_ENABLED) {
            std.debug.print("  🔍 SEARCH: no environment to search\n", .{});
        }
        return null;
    }

    const current_env = env.?;

    if (DEBUG_ENABLED) {
        std.debug.print("  🔍 SEARCH ENV: {} bindings, parent={}\n", .{ current_env.bindings.len, current_env.parent_env != null });
    }

    // Search in current environment
    for (current_env.bindings, 0..) |binding, i| {
        if (DEBUG_ENABLED) {
            std.debug.print("    [{:2}] checking pattern {} vs target {}\n", .{ i, @intFromEnum(binding.pattern_idx), @intFromEnum(pattern_idx) });
        }

        if (binding.pattern_idx == pattern_idx) {
            if (DEBUG_ENABLED) {
                std.debug.print("    ✅ MATCH found at index {}\n", .{i});
            }
            return binding;
        }
    }

    // Search in parent environment recursively
    if (DEBUG_ENABLED and current_env.parent_env != null) {
        std.debug.print("  🔄 SEARCH PARENT: continuing search\n", .{});
    }
    return self.searchCapturedEnvironment(pattern_idx, current_env.parent_env);
}

// Debug configuration
const DEBUG_ENABLED = build_options.trace_eval;
const TEST_FILTER = "basic single variable"; // Filter for specific test debugging

// Verify debug flag is working at compile time
comptime {
    if (DEBUG_ENABLED) {
        @compileLog("🔧 TRACE_EVAL DEBUG ENABLED");
    }
}

/// Helper function for filtered debug output - only prints if test name matches filter
fn debugFiltered(comptime format: []const u8, args: anytype, test_context: []const u8) void {
    if (!DEBUG_ENABLED) return;

    if (std.mem.indexOf(u8, test_context, TEST_FILTER) != null) {
        std.debug.print("TRACE[{}]: " ++ format ++ "\n", .{TEST_FILTER} ++ args);
    }
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
        if (DEBUG_ENABLED and self.layout_stack.items.len > 0) {
            std.debug.print("DEBUG: Layout stack not empty! {} items remaining:\n", .{self.layout_stack.items.len});
            for (self.layout_stack.items, 0..) |item_layout, i| {
                std.debug.print("  [{}]: tag = {}\n", .{ i, item_layout.tag });
            }
        }

        // Ensure both stacks are empty at the end - if not, it's a bug!
        std.debug.assert(self.work_stack.items.len == 0);
        std.debug.assert(self.layout_stack.items.len == 0);

        // With proper calling convention, after cleanup the result is at the start of the stack
        const result_ptr = @as([*]u8, @ptrCast(self.stack_memory.start));

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Final result at stack pos 0 (calling convention)\n", .{});
        }

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
                        if (DEBUG_ENABLED) {
                            std.debug.print("DEBUG: Retrieved parameter value from binding (pattern {})\n", .{@intFromEnum(lookup.pattern_idx)});
                            if (binding.layout.tag == .scalar and binding.layout.data.scalar.tag == .int) {
                                const precision = binding.layout.data.scalar.data.int;
                                const retrieved_value = readIntFromMemory(@as([*]u8, @ptrCast(ptr)), precision);
                                std.debug.print("DEBUG: Retrieved parameter value = {}\n", .{retrieved_value});
                            }
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
                // NEW APPROACH: Use capture information from canonicalization
                const has_captures = lambda_expr.captures.captured_vars.len > 0;

                // FORCE DEBUG: Always show lambda creation details
                if (has_captures) {
                    std.debug.print("DEBUG: 🎯 LAMBDA WITH CAPTURES: {} variables\n", .{lambda_expr.captures.captured_vars.len});
                    debugFiltered("🎯 LAMBDA WITH CAPTURES: {} variables", .{lambda_expr.captures.captured_vars.len}, "basic single variable");
                } else {
                    std.debug.print("DEBUG: 🎯 SIMPLE LAMBDA: no captures\n", .{});
                    debugFiltered("🎯 SIMPLE LAMBDA: no captures", .{}, "basic single variable");
                }

                // Additional debug info
                std.debug.print("DEBUG: 🔍 LAMBDA DETAILS: body_expr={}, args_span.len=?, has_captures={}\n", .{ @intFromEnum(lambda_expr.body), has_captures });

                if (has_captures) {
                    // Use full Closure struct for lambdas with captures
                    const closure_size = @sizeOf(Closure);
                    const closure_alignment: std.mem.Alignment = .@"8"; // Use safe 8-byte alignment

                    if (DEBUG_ENABLED) {
                        std.debug.print("DEBUG: CLOSURE ALIGNMENT CHECK: @alignOf(Closure)={}, using_alignment={}, max_roc_alignment.toByteUnits()={}\n", .{ @alignOf(Closure), closure_alignment.toByteUnits(), collections.max_roc_alignment.toByteUnits() });
                        debugFiltered("CLOSURE ALIGNMENT: requested={}, max_allowed={}", .{ closure_alignment.toByteUnits(), collections.max_roc_alignment.toByteUnits() }, "basic single variable");
                    }

                    // Allocate closure on stack
                    const closure_ptr = self.stack_memory.alloca(closure_size, closure_alignment) catch |err| switch (err) {
                        error.StackOverflow => return error.StackOverflow,
                    };

                    // Initialize closure with capture info
                    const closure = @as(*Closure, @ptrCast(@alignCast(closure_ptr)));
                    closure.* = Closure{
                        .body_expr_idx = lambda_expr.body,
                        .args_pattern_span = lambda_expr.args,
                        .captured_env = null, // We'll store capture info differently
                    };

                    // Store capture information directly in closure for later retrieval
                    // For now, we'll rely on the original lambda_expr.captures during calls
                } else {
                    // Use SimpleClosure for lambdas without captures
                    const closure_size = @sizeOf(SimpleClosure);
                    const closure_alignment: std.mem.Alignment = .@"8"; // Use safe 8-byte alignment

                    // Allocate closure on stack
                    const closure_ptr = self.stack_memory.alloca(closure_size, closure_alignment) catch |err| switch (err) {
                        error.StackOverflow => return error.StackOverflow,
                    };

                    // Initialize closure
                    const closure = @as(*SimpleClosure, @ptrCast(@alignCast(closure_ptr)));
                    closure.* = SimpleClosure{
                        .body_expr_idx = lambda_expr.body,
                        .args_pattern_span = lambda_expr.args,
                    };
                }

                // Create and push closure layout with capture info for later use
                const env_size: u16 = if (has_captures) @intCast(lambda_expr.captures.captured_vars.len) else 0;

                // FORCE DEBUG: Always show layout creation details
                std.debug.print("DEBUG: 📐 LAMBDA LAYOUT CREATION: has_captures={}, captured_vars.len={}, env_size={}\n", .{ has_captures, lambda_expr.captures.captured_vars.len, env_size });
                debugFiltered("📐 LAMBDA LAYOUT CREATION: has_captures={}, captured_vars.len={}, env_size={}", .{ has_captures, lambda_expr.captures.captured_vars.len, env_size }, "basic single variable");

                const closure_layout = layout.Layout{
                    .tag = .closure,
                    .data = .{ .closure = .{ .env_size = env_size } },
                };
                try self.layout_stack.append(closure_layout);

                // FORCE DEBUG: Always show layout push details
                std.debug.print("DEBUG: 📐 LAYOUT PUSHED: tag={s}, env_size={}\n", .{ @tagName(closure_layout.tag), closure_layout.data.closure.env_size });
                debugFiltered("📐 LAYOUT PUSHED: tag={s}, env_size={}", .{ @tagName(closure_layout.tag), closure_layout.data.closure.env_size }, "basic single variable");
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
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: completeBinop stack analysis\n", .{});
            std.debug.print("DEBUG: stack.used = {}, right_size = {}, left_size = {}\n", .{ self.stack_memory.used, right_size, left_size });
            std.debug.print("DEBUG: rhs_ptr offset = {}, left_ptr offset = {}\n", .{ self.stack_memory.used - right_size, self.stack_memory.used - right_size - left_size });
        }

        // Read the values
        const lhs_val = readIntFromMemory(@as([*]u8, @ptrCast(left_ptr)), lhs_scalar.data.int);
        const rhs_val = readIntFromMemory(@as([*]u8, @ptrCast(rhs_ptr)), rhs_scalar.data.int);

        // Debug: Values read from memory
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Read values - left = {}, right = {}\n", .{ lhs_val, rhs_val });
            std.debug.print("DEBUG: Left layout: tag={}, precision={}\n", .{ left_layout.tag, lhs_scalar.data.int });
            std.debug.print("DEBUG: Right layout: tag={}, precision={}\n", .{ right_layout.tag, rhs_scalar.data.int });
        }

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
                if (DEBUG_ENABLED) {
                    std.debug.print("DEBUG: Addition operation: {} + {} = {}\n", .{ lhs_val, rhs_val, result_val });
                }
                writeIntToMemory(@as([*]u8, @ptrCast(result_ptr)), result_val, lhs_scalar.data.int);

                // Debug: Verify what was written to memory
                if (DEBUG_ENABLED) {
                    const verification = readIntFromMemory(@as([*]u8, @ptrCast(result_ptr)), lhs_scalar.data.int);
                    std.debug.print("DEBUG: Verification read from result memory = {}\n", .{verification});
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

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Unary minus operation: -{} = {}\n", .{ operand_val, -operand_val });
        }

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

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Allocated return space: size={}, layout={}\n", .{ return_size, return_layout.tag });
        }
    }

    fn handleCallFunction(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
        self.debugTraceCall("handleCallFunction", call_expr_idx);
        defer self.debugTraceCallExit("handleCallFunction");

        // At this point, the stack should have:
        // Bottom: [function, arg1, arg2, ..., argN] Top
        self.debugInspectState("call_function_entry");
        self.debugTracePhase("call_validation", call_expr_idx);

        // Get the call expression to find argument count
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => {
                self.debugError("invalid_call_expr", call_expr_idx, "call_function");
                return error.LayoutError;
            },
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        // Check that we have enough items on the layout stack
        if (self.layout_stack.items.len < arg_count + 1) {
            self.debugError("insufficient_layout_items", call_expr_idx, "call_function");
            return error.InvalidStackState;
        }

        // Validate layout stack consistency
        self.debugValidateLayoutStack(arg_count + 1, "call_function_validation");

        // Access the function layout (it's at the bottom of our function call portion)
        const function_layout_idx = self.layout_stack.items.len - arg_count - 1;
        const function_layout = self.layout_stack.items[function_layout_idx];

        // Verify it's a closure
        if (function_layout.tag != .closure) {
            self.debugError("not_a_function", call_expr_idx, "call_function");
            return error.Crash; // "Not a function" error
        }

        // Check if function has captures and add capture record as hidden argument
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 📞 ABOUT TO HANDLE CAPTURE ARGUMENTS for expr={}\n", .{@intFromEnum(call_expr_idx)});
        }
        try self.handleCaptureArguments(call_expr_idx, function_layout_idx);
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 📞 FINISHED HANDLING CAPTURE ARGUMENTS for expr={}\n", .{@intFromEnum(call_expr_idx)});
        }

        self.debugTracePhase("call_ready_for_binding", call_expr_idx);
        self.debugInspectState("call_function_complete");

        // The function and arguments are now ready for parameter binding
        // Nothing else to do here - the next work item will handle binding
    }

    /// Handle capture arguments for functions that capture variables from outer scopes.
    /// Creates capture records and pushes them as hidden arguments.
    fn handleCaptureArguments(self: *Interpreter, call_expr_idx: CIR.Expr.Idx, function_layout_idx: usize) EvalError!void {
        // Check function layout to see if this closure has captures
        const function_layout = self.layout_stack.items[function_layout_idx];

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 🔍 CAPTURE CHECK: tag={s}, env_size={}\n", .{ @tagName(function_layout.tag), if (function_layout.tag == .closure) function_layout.data.closure.env_size else 0 });
            debugFiltered("🔍 CAPTURE CHECK: tag={s}, env_size={}", .{ @tagName(function_layout.tag), if (function_layout.tag == .closure) function_layout.data.closure.env_size else 0 }, "basic single variable");
        }

        if (function_layout.tag != .closure or function_layout.data.closure.env_size == 0) {
            if (DEBUG_ENABLED) {
                std.debug.print("DEBUG: 🚫 EARLY RETURN: Not a closure with captures\n", .{});
                debugFiltered("🚫 EARLY RETURN: Not a closure with captures", .{}, "basic single variable");
            }
            return; // Not a closure with captures
        }

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 🎯 ADDING CAPTURE RECORD: env_size={}, call_expr={}\n", .{ function_layout.data.closure.env_size, @intFromEnum(call_expr_idx) });
            debugFiltered("🎯 ADDING CAPTURE RECORD: env_size={}, call_expr={}", .{ function_layout.data.closure.env_size, @intFromEnum(call_expr_idx) }, "basic single variable");
        }

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
                if (DEBUG_ENABLED) {
                    std.debug.print("DEBUG: 🎯 CLOSURE CALL WITH CAPTURES: env_size={}\n", .{function_layout.data.closure.env_size});
                }

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

                if (DEBUG_ENABLED) {
                    std.debug.print("DEBUG: ✅ CLOSURE CAPTURE RECORD PUSHED: {} vars\n", .{num_captures});
                }
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

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: ✅ CAPTURE RECORD PUSHED: {} vars\n", .{lambda_captures.captured_vars.len});
        }
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
        self.debugTraceCall("handleBindParameters", call_expr_idx);
        defer self.debugTraceCallExit("handleBindParameters");

        // Get the call expression to determine argument count
        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => {
                self.debugError("invalid_call_expr", call_expr_idx, "bind_parameters");
                return error.LayoutError;
            },
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function itself

        if (self.layout_stack.items.len < arg_count + 1) {
            self.debugError("layout_stack_underflow", call_expr_idx, "bind_parameters");
            return error.InvalidStackState;
        }

        // Validate layout stack consistency
        self.debugValidateLayoutStack(arg_count + 1, "bind_parameters_entry");

        self.debugInspectState("bind_parameters_start");
        self.debugTracePhase("parameter_binding_calculation", call_expr_idx);

        // Calculate function position on stack using layout positions
        // Stack layout: [return_space, function, arg1, arg2, ...]

        // Function position is calculated by summing sizes of all items that come after it
        // Layout stack is ordered with function at index: len - 1 - arg_count
        const function_layout_idx = self.layout_stack.items.len - 1 - arg_count;

        // Get the function layout
        const function_layout = self.layout_stack.items[function_layout_idx];

        // TEMPORARY FIX: Use the absolute position where closures are actually created
        // All closures in debug output show they are created at pos=16, regardless of stack layout
        // TODO: Implement proper stack position tracking that accounts for closure creation time
        const function_stack_pos: usize = 16;

        if (function_layout.tag == .closure) {
            self.debugTracePhase("function_position_located", call_expr_idx);
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
            break :blk full_closure_ptr.body_expr_idx;
        } else blk: {
            const simple_closure_ptr = @as(*SimpleClosure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
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
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 📍 STACK POSITION CALCULATION:\n", .{});
            std.debug.print("  function_layout_idx={}, arg_count={}\n", .{ function_layout_idx, arg_count });
            std.debug.print("  layout_stack.len={}\n", .{self.layout_stack.items.len});
            std.debug.print("  calculated function_stack_pos={}\n", .{function_stack_pos});
            std.debug.print("  stack_memory.start={}\n", .{@intFromPtr(self.stack_memory.start)});
            std.debug.print("  function_stack_pos={}\n", .{function_stack_pos});

            // Show the layout items being summed for position calculation
            std.debug.print("  Items after function (summed for position):\n", .{});
            for (self.layout_stack.items[function_layout_idx + 1 ..], function_layout_idx + 1..) |item_layout, i| {
                const item_size = self.layout_cache.layoutSize(item_layout);
                std.debug.print("    [{d}] {s} size={}\n", .{ i, @tagName(item_layout.tag), item_size });
            }
        }

        // Debug: Verify our calculated position
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 🔍 VERIFYING CALCULATED POSITION:\n", .{});
            std.debug.print("  calculated pos={}: body={}, span_len={}\n", .{ function_stack_pos, @intFromEnum(closure_body_expr_idx), closure_args_pattern_span.span.len });
        }

        // Verify closure integrity - handle both types
        if (has_captures) {
            const full_closure_ptr = @as(*Closure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            if (DEBUG_ENABLED) {
                std.debug.print("🔬 Full Closure parameter_binding: body={} span_len={} addr={}\n", .{ @intFromEnum(full_closure_ptr.body_expr_idx), full_closure_ptr.args_pattern_span.span.len, @intFromPtr(full_closure_ptr) });
            }
        } else {
            const simple_closure_ptr = @as(*SimpleClosure, @ptrCast(@alignCast(@as([*]u8, @ptrCast(self.stack_memory.start)) + function_stack_pos)));
            self.debugVerifyClosure(simple_closure_ptr, "parameter_binding");
        }

        // EXECUTION-TIME CAPTURE ANALYSIS: Check if closure body contains nested lambdas
        // This is the correct timing - after outer parameters are bound and execution context is populated

        // Debug: Validate closure body before nested lambda detection
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 🔍 VALIDATING CLOSURE BODY: body_expr_idx={}\n", .{@intFromEnum(closure_body_expr_idx)});
            std.debug.print("DEBUG: 🔍 CLOSURE PTR: body={}, args_span_len={}\n", .{ @intFromEnum(closure_body_expr_idx), closure_args_pattern_span.span.len });
        }

        // NEW APPROACH: Captures are now passed as regular function arguments
        // No execution-time capture analysis needed - everything is handled at canonicalization time
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: 🎯 PARAMETER BINDING: closure with {} args\n", .{closure_args_pattern_span.span.len});
        }

        const parameter_patterns = self.cir.store.slicePatterns(closure_args_pattern_span);

        // For closures with captures, we expect one extra argument (the capture record)
        const expected_args = if (has_captures) parameter_patterns.len + 1 else parameter_patterns.len;

        if (expected_args != arg_count) {
            // FORCE DEBUG: Always show arity mismatch details
            std.debug.print("DEBUG: 🚨 ARITY MISMATCH DETAILS:\n", .{});
            std.debug.print("   Expected: {} (pattern_params={}, has_captures={})\n", .{ expected_args, parameter_patterns.len, has_captures });
            std.debug.print("   Actual:   {}\n", .{arg_count});
            std.debug.print("   Function layout env_size: {}\n", .{function_layout.data.closure.env_size});
            std.debug.print("   Function body expr: {}\n", .{@intFromEnum(closure_body_expr_idx)});
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
            if (DEBUG_ENABLED) {
                std.debug.print("DEBUG: BIND param[{}] pattern={} at pos={} ({s})\n", .{ arg_idx, @intFromEnum(parameter_pattern_idx), current_stack_pos, @tagName(arg_layout.tag) });
            }

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
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: BIND SUMMARY: {} parameters bound, stack_used={}\n", .{ arg_count, self.stack_memory.used });
            std.debug.print("DEBUG: CONTEXT STACK: {} contexts deep\n", .{self.execution_contexts.items.len});
        }
        self.debugInspectState("bind_parameters_complete");
        self.debugTracePhase("parameter_binding_complete", call_expr_idx);
    }

    fn handleEvalFunctionBody(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
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

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: === COPY RESULT TO RETURN SPACE ===\n", .{});
            std.debug.print("DEBUG: Initial stack.used = {}\n", .{self.stack_memory.used});
            std.debug.print("DEBUG: Layout stack size = {}\n", .{self.layout_stack.items.len});
        }

        // The body result is at the top of the stack
        const body_result_layout = self.layout_stack.pop() orelse return error.InvalidStackState;
        const body_result_size = self.layout_cache.layoutSize(body_result_layout);

        // Calculate position of body result
        const body_result_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + self.stack_memory.used - body_result_size;

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Body result layout = {}, size = {}\n", .{ body_result_layout.tag, body_result_size });
            std.debug.print("DEBUG: Body result at stack position = {}\n", .{self.stack_memory.used - body_result_size});
            debugFiltered("📋 COPY RESULT: layout.tag={s}, env_size={}", .{ @tagName(body_result_layout.tag), if (body_result_layout.tag == .closure) body_result_layout.data.closure.env_size else 0 }, "basic single variable");
        }

        // Find the return space - it should be at the bottom of our call frame
        // We need to find how many items are in our call frame to calculate the return space position

        const call_expr = self.cir.store.getExpr(call_expr_idx);
        const call = switch (call_expr) {
            .e_call => |c| c,
            else => return error.LayoutError,
        };

        const all_exprs = self.cir.store.sliceExpr(call.args);
        const arg_count = all_exprs.len - 1; // Subtract 1 for the function

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Call has {} arguments\n", .{arg_count});
        }

        // Calculate stack positions working backwards from current position
        // Stack layout: [return_space, function, arg1, arg2, ..., body_result]
        var stack_pos = self.stack_memory.used;
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Starting stack position calculation from {}\n", .{stack_pos});
        }

        // Skip the body result we just calculated
        stack_pos -= body_result_size;
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: After skipping body result: stack_pos = {}\n", .{stack_pos});
        }

        // Skip the arguments
        for (0..arg_count) |i| {
            const layout_idx = self.layout_stack.items.len - 1 - i;
            const arg_layout = self.layout_stack.items[layout_idx];
            const arg_size = self.layout_cache.layoutSize(arg_layout);
            stack_pos -= arg_size;
            if (DEBUG_ENABLED) {
                std.debug.print("DEBUG: After skipping arg {}: layout={}, size={}, stack_pos = {}\n", .{ i, arg_layout.tag, arg_size, stack_pos });
            }
        }

        // Skip the function
        const function_layout = self.layout_stack.items[self.layout_stack.items.len - arg_count - 1];
        const function_size = self.layout_cache.layoutSize(function_layout);
        stack_pos -= function_size;
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: After skipping function: layout={}, size={}, stack_pos = {}\n", .{ function_layout.tag, function_size, stack_pos });
        }

        // Now we're at the return space
        const return_space_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + stack_pos;

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: Final return space position = {}\n", .{stack_pos});
            std.debug.print("DEBUG: Copying {} bytes from {} to {}\n", .{ body_result_size, self.stack_memory.used - body_result_size, stack_pos });

            // Verify the copy source data before copying
            const source_bytes = @as([*]u8, @ptrCast(body_result_ptr));
            std.debug.print("DEBUG: Source bytes: ", .{});
            for (0..@min(body_result_size, 16)) |i| {
                std.debug.print("{x:0>2} ", .{source_bytes[i]});
            }
            std.debug.print("\n", .{});
        }

        // Copy the result
        @memcpy(return_space_ptr[0..body_result_size], body_result_ptr[0..body_result_size]);

        // Verify the copy destination data after copying
        if (DEBUG_ENABLED) {
            const dest_bytes = @as([*]u8, @ptrCast(return_space_ptr));
            std.debug.print("DEBUG: Dest bytes after copy: ", .{});
            for (0..@min(body_result_size, 16)) |i| {
                std.debug.print("{x:0>2} ", .{dest_bytes[i]});
            }
            std.debug.print("\n", .{});
        }

        // Pop the body result from stack
        self.stack_memory.used -= @as(u32, @intCast(body_result_size));
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: After popping body result: stack.used = {}\n", .{self.stack_memory.used});

            // Don't push the layout - the return space layout is already on the stack
            std.debug.print("DEBUG: === END COPY RESULT TO RETURN SPACE ===\n", .{});
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

            if (DEBUG_ENABLED) {
                std.debug.print("DEBUG: CONTEXT STACK: {} contexts remaining after cleanup\n", .{self.execution_contexts.items.len});
            }
        }

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: === CLEANUP FUNCTION ===\n", .{});
            std.debug.print("DEBUG: Before cleanup: stack.used = {}, layout_stack.len = {}\n", .{ self.stack_memory.used, self.layout_stack.items.len });
            debugFiltered("🧹 CLEANUP START: stack.used={}, layout_stack.len={}", .{ self.stack_memory.used, self.layout_stack.items.len }, "basic single variable");
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
            std.debug.print("DEBUG: Return size = {}, cleanup size = {}\n", .{ return_size, cleanup_size });
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
            std.debug.print("DEBUG: Moving return value from {} to 0, size={}\n", .{ return_value_current_pos, return_size });
        }

        // Move return value from current position to position 0
        const source_ptr = @as([*]u8, @ptrCast(self.stack_memory.start)) + return_value_current_pos;
        const dest_ptr = @as([*]u8, @ptrCast(self.stack_memory.start));
        std.mem.copyForwards(u8, dest_ptr[0..return_size], source_ptr[0..return_size]);

        // Update stack to contain only the return value
        self.stack_memory.used = @as(u32, @intCast(return_size));

        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: After cleanup: stack.used = {}\n", .{self.stack_memory.used});
        }

        // Clean up layout stack: remove all call-related layouts except return
        const layouts_to_remove = arg_count + 1; // function + arguments

        // Remove function and argument layouts (but keep return layout)
        for (0..layouts_to_remove) |_| {
            const popped_layout = self.layout_stack.pop() orelse return error.InvalidStackState;
            if (DEBUG_ENABLED) {
                debugFiltered("🧹 LAYOUT POPPED: tag={s}, env_size={}", .{ @tagName(popped_layout.tag), if (popped_layout.tag == .closure) popped_layout.data.closure.env_size else 0 }, "basic single variable");
            }
        }

        // The return layout should now be at the top of layout stack
        if (DEBUG_ENABLED) {
            std.debug.print("DEBUG: After layout cleanup: layout_stack.len = {}\n", .{self.layout_stack.items.len});
            std.debug.print("DEBUG: === END CLEANUP FUNCTION ===\n", .{});
            if (self.layout_stack.items.len > 0) {
                const top_layout = self.layout_stack.items[self.layout_stack.items.len - 1];
                debugFiltered("🧹 CLEANUP END: top_layout.tag={s}, env_size={}", .{ @tagName(top_layout.tag), if (top_layout.tag == .closure) top_layout.data.closure.env_size else 0 }, "basic single variable");
            }
        }
    }

    fn debugTraceCall(self: *const Interpreter, function_name: []const u8, expr_idx: CIR.Expr.Idx) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("DEBUG: ENTER {s} (expr={})\n", .{ function_name, @intFromEnum(expr_idx) });
    }

    fn debugTraceCallExit(self: *const Interpreter, function_name: []const u8) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("DEBUG: EXIT  {s}\n", .{function_name});
    }

    fn debugTracePhase(self: *const Interpreter, phase_name: []const u8, expr_idx: CIR.Expr.Idx) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("DEBUG:  {s} (expr={})\n", .{ phase_name, @intFromEnum(expr_idx) });
    }

    fn debugInspectState(self: *const Interpreter, label: []const u8) void {
        if (!DEBUG_ENABLED) return;

        const SizeInfo = struct { value: f64, unit: []const u8 };

        const stack_size: SizeInfo = if (self.stack_memory.used < 1024)
            .{ .value = @as(f64, @floatFromInt(self.stack_memory.used)), .unit = "B" }
        else if (self.stack_memory.used < 1024 * 1024)
            .{ .value = @as(f64, @floatFromInt(self.stack_memory.used)) / 1024.0, .unit = "KB" }
        else
            .{ .value = @as(f64, @floatFromInt(self.stack_memory.used)) / (1024.0 * 1024.0), .unit = "MB" };

        const stack_cap: SizeInfo = if (self.stack_memory.capacity < 1024)
            .{ .value = @as(f64, @floatFromInt(self.stack_memory.capacity)), .unit = "B" }
        else if (self.stack_memory.capacity < 1024 * 1024)
            .{ .value = @as(f64, @floatFromInt(self.stack_memory.capacity)) / 1024.0, .unit = "KB" }
        else
            .{ .value = @as(f64, @floatFromInt(self.stack_memory.capacity)) / (1024.0 * 1024.0), .unit = "MB" };

        const pct = @as(f64, @floatFromInt(self.stack_memory.used)) / @as(f64, @floatFromInt(self.stack_memory.capacity)) * 100.0;

        std.debug.print("\nDEBUG: {s}: stack={d:.1}{s}/{d:.1}{s} ({d:.1}%), layouts={}, bindings={}, work={}\n", .{
            label,
            stack_size.value,
            stack_size.unit,
            stack_cap.value,
            stack_cap.unit,
            pct,
            self.layout_stack.items.len,
            self.parameter_bindings.items.len,
            self.work_stack.items.len,
        });
    }

    fn debugError(self: *const Interpreter, error_type: []const u8, expr_idx: CIR.Expr.Idx, context: []const u8) void {
        if (!DEBUG_ENABLED) return;
        std.debug.print("❌ {s} in {s}: expr={}, stack_used={}\n", .{ error_type, context, @intFromEnum(expr_idx), self.stack_memory.used });
    }

    fn debugValidateLayoutStack(self: *const Interpreter, expected_count: usize, context: []const u8) void {
        if (!DEBUG_ENABLED) return;

        const actual_count = self.layout_stack.items.len;
        if (actual_count != expected_count) {
            std.debug.print("DEBUG:  Layout stack mismatch in {s}: expected={}, actual={}\n", .{ context, expected_count, actual_count });

            std.debug.print("\nDEBUG: Layout stack ({s}): {} items, stack_used={}\n", .{ context, self.layout_stack.items.len, self.stack_memory.used });
            var pos = self.stack_memory.used;
            for (self.layout_stack.items, 0..) |item, i| {
                const size = self.layout_cache.layoutSize(item);
                pos -= @intCast(size);
                std.debug.print("  [{:2}] {s:<12} size={:3} pos={:3}\n", .{ i, @tagName(item.tag), size, pos });
            }
        }
    }

    fn debugVerifyClosure(self: *const Interpreter, closure_ptr: *SimpleClosure, label: []const u8) void {
        _ = self;
        if (!DEBUG_ENABLED) return;

        const body_idx: u32 = @intFromEnum(closure_ptr.body_expr_idx);
        const span_len = closure_ptr.args_pattern_span.span.len;

        std.debug.print("🔬 Closure {s}: body={} span_len={} addr={}\n", .{ label, body_idx, span_len, @intFromPtr(closure_ptr) });

        // Show actual closure data for debugging
        const raw_bytes = @as([*]const u8, @ptrCast(closure_ptr))[0..@sizeOf(SimpleClosure)];
        std.debug.print("DEBUG: Closure data: body={}, span_len={}\n", .{ std.mem.readInt(u32, raw_bytes[0..4], std.builtin.Endian.little), std.mem.readInt(u32, raw_bytes[8..12], std.builtin.Endian.little) });

        // Basic sanity checks
        if (body_idx == 0 or body_idx > 1000000) {
            std.debug.print("DEBUG: ❌ SUSPICIOUS body_expr_idx: {}\n", .{body_idx});
        }
        if (span_len > 100) {
            std.debug.print("DEBUG: ❌ SUSPICIOUS span length: {}\n", .{span_len});
        }
    }

    fn debugTraceCapture(self: *const Interpreter, phase: []const u8, expr_idx: CIR.Expr.Idx) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("🔍 CAPTURE {s}: expr={}\n", .{ phase, @intFromEnum(expr_idx) });
    }

    fn debugTraceCaptureResult(self: *const Interpreter, captured_count: usize, env_size: usize) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("📊 CAPTURE ANALYSIS: found {} variables, env_size={} bytes\n", .{ captured_count, env_size });
    }

    fn debugInspectCapturedVar(self: *const Interpreter, pattern_idx: CIR.Pattern.Idx, index: usize) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("  📌 Captured[{}]: pattern_idx={}\n", .{ index, @intFromEnum(pattern_idx) });
    }

    fn debugTraceEnhancedClosure(self: *const Interpreter, closure: *const Closure, env_size: usize) void {
        if (!DEBUG_ENABLED) return;
        const stack_pos = @intFromPtr(closure) - @intFromPtr(self.stack_memory.start);
        std.debug.print("🏗️  ENHANCED CLOSURE: size={}, env_size={}, pos={}, has_env={}\n", .{ @sizeOf(Closure), env_size, stack_pos, closure.captured_env != null });
    }

    fn debugInspectCaptureEnvironment(self: *const Interpreter, env: *const CapturedEnvironment, label: []const u8) void {
        _ = self;
        if (!DEBUG_ENABLED) return;
        std.debug.print("🗂️  CAPTURE ENV {s}: {} bindings, parent={}\n", .{ label, env.bindings.len, env.parent_env != null });

        for (env.bindings, 0..) |binding, i| {
            std.debug.print("    [{:2}] pattern={}, layout={s}, addr={}\n", .{ i, @intFromEnum(binding.pattern_idx), @tagName(binding.layout.tag), @intFromPtr(binding.value_data) });
        }
    }

    /// Initialize the deferred captured environment for a closure
    fn initializeDeferredCapturedEnvironment(self: *Interpreter, closure: *Closure) !void {
        const env = closure.captured_env orelse return; // No environment to initialize

        if (DEBUG_ENABLED) {
            std.debug.print("🏗️  INIT DEFERRED CAPTURE ENV: {} variables to capture\n", .{env.bindings.len});
        }

        // Calculate value data offset (after environment and bindings)
        const memory_block = @as([*]u8, @ptrCast(closure));
        var value_data_offset = @sizeOf(Closure) + @sizeOf(CapturedEnvironment) +
            (env.bindings.len * @sizeOf(CapturedBinding));

        // Initialize each binding with actual captured values
        for (env.bindings) |*binding| {
            const pattern_idx = binding.pattern_idx;

            // Find the current value of this variable from parameter bindings or execution context
            var found_value: ?*u8 = null;
            var found_layout: ?layout.Layout = null;

            // First try current parameter bindings
            for (self.parameter_bindings.items) |param_binding| {
                if (param_binding.pattern_idx == pattern_idx) {
                    found_value = @as(*u8, @ptrCast(param_binding.value_ptr));
                    found_layout = param_binding.layout;
                    break;
                }
            }

            // If not found, search through execution context chain
            if (found_value == null) {
                var context = self.current_context;
                while (context) |ctx| {
                    if (ctx.findBinding(pattern_idx)) |ctx_binding| {
                        found_value = @as(*u8, @ptrCast(ctx_binding.value_ptr));
                        found_layout = ctx_binding.layout;
                        if (DEBUG_ENABLED) {
                            std.debug.print("🔍 FOUND DEFERRED in execution context: pattern={}\n", .{@intFromEnum(pattern_idx)});
                        }
                        break;
                    }
                    context = ctx.parent_context;
                }
            }

            if (found_value == null) {
                if (DEBUG_ENABLED) {
                    std.debug.print("❌ DEFERRED CAPTURE ERROR: pattern {} not found\n", .{@intFromEnum(pattern_idx)});
                }
                return error.LayoutError;
            }

            // Calculate value size and copy value data
            const value_layout = found_layout.?;
            const value_size = self.layout_cache.layoutSize(value_layout);
            const value_ptr = memory_block + value_data_offset;

            if (DEBUG_ENABLED) {
                std.debug.print("  📦 DEFERRED CAPTURING: pattern={}, size={} bytes\n", .{ @intFromEnum(pattern_idx), value_size });
            }

            // Copy the captured value
            @memcpy(value_ptr[0..value_size], @as([*]u8, @ptrCast(found_value))[0..value_size]);

            // Update binding with actual data
            binding.* = CapturedBinding{
                .pattern_idx = pattern_idx,
                .value_data = value_ptr,
                .layout = value_layout,
            };

            value_data_offset += value_size;
        }

        // Mark environment as initialized
        if (closure.captured_env) |captured_env| {
            @constCast(captured_env).deferred_init = false;
        }
    }

    // Removed createCapturedEnvironment - using record approach instead
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
fn readIntFromMemory(ptr: [*]u8, precision: types.Num.Int.Precision) i128 {
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
