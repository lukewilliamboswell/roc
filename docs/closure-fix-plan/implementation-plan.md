# Closure Implementation Fix Plan (Call Frame Marker Approach)

## Overview

This document outlines the changes needed to fix the closure capture implementation in the Roc interpreter. The main issues are:

1. Using a stateful `last_closure_pos` field that causes incorrect closure lookups
2. Having two separate closure types (SimpleClosure and Closure) leading to complexity
3. Not properly tracking closure positions during function calls

## Solution Approach: Call Frame Markers

Instead of calculating closure positions dynamically by walking backwards through the stack, we'll use a simpler approach: explicitly store the function's position and layout in a "call frame marker" during call setup. This trades a small amount of stack space for much simpler and more robust code.

## Key Changes Summary

1. **Remove stateful closure tracking** - Delete `last_closure_pos` field
2. **Unify closure types** - Merge SimpleClosure and Closure into a single type
3. **Add call frame markers** - Store function position explicitly during calls
4. **Update all closure creation/reading code** - Use the unified type everywhere

## Detailed File Changes

### 1. `src/eval/interpreter.zig`

#### 1.1 Remove `last_closure_pos` field

```zig
// Line ~528: Remove this field from the Interpreter struct
pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    cir: *const CIR,
    stack_memory: stack.Stack,
    layout_cache: *layout_store.LayoutCache,
    type_store: *const types_store.TypeStore,
    work_stack: std.ArrayList(WorkItem),
    layout_stack: std.ArrayList(layout.Layout),
    parameter_bindings: std.ArrayList(ParameterBinding),
    execution_contexts: std.ArrayList(*ExecutionContext),
    current_context: ?*ExecutionContext,

    // For tracing
    trace_name: ?[]const u8 = null,
    trace_indent: u32 = 0,
    trace_writer: ?std.io.AnyWriter = null,
    // DELETE: last_closure_pos: u32 = 0,
```

#### 1.2 Add CallFrame struct

Add this new struct to track call information:

```zig
// Add after WorkItem struct (around line 140)
const CallFrame = struct {
    function_pos: u32,          // Stack position of the function closure
    function_layout: layout.Layout,  // Layout of the function
    return_layout_idx: u32,     // Index in layout_stack for return value
    arg_count: u32,             // Number of arguments for this call
    
    pub fn write(self: CallFrame, memory: []u8) void {
        std.debug.assert(memory.len >= @sizeOf(CallFrame));
        var offset: usize = 0;
        
        std.mem.writeInt(u32, memory[offset..][0..4], self.function_pos, .little);
        offset += 4;
        
        // Write layout tag and data (simplified - adapt to your layout serialization)
        memory[offset] = @intFromEnum(self.function_layout.tag);
        offset += 1;
        
        // Write env_size if it's a closure layout
        if (self.function_layout.tag == .closure) {
            std.mem.writeInt(u32, memory[offset..][0..4], self.function_layout.data.closure.env_size, .little);
            offset += 4;
        }
        
        std.mem.writeInt(u32, memory[offset..][0..4], self.return_layout_idx, .little);
        offset += 4;
        
        std.mem.writeInt(u32, memory[offset..][0..4], self.arg_count, .little);
    }
    
    pub fn read(memory: []const u8) CallFrame {
        var offset: usize = 0;
        
        const function_pos = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;
        
        // Read layout tag
        const layout_tag: layout.LayoutTag = @enumFromInt(memory[offset]);
        offset += 1;
        
        // Read layout data based on tag
        const function_layout = if (layout_tag == .closure) blk: {
            const env_size = std.mem.readInt(u32, memory[offset..][0..4], .little);
            offset += 4;
            break :blk layout.Layout{
                .tag = .closure,
                .data = .{ .closure = .{ .env_size = env_size } },
            };
        } else layout.Layout{ .tag = layout_tag, .data = undefined };
        
        offset += 4; // Skip padding if needed
        
        const return_layout_idx = std.mem.readInt(u32, memory[offset..][0..4], .little);
        offset += 4;
        
        const arg_count = std.mem.readInt(u32, memory[offset..][0..4], .little);
        
        return CallFrame{
            .function_pos = function_pos,
            .function_layout = function_layout,
            .return_layout_idx = return_layout_idx,
            .arg_count = arg_count,
        };
    }
    
    pub fn size() u32 {
        // Fixed size: pos(4) + tag(1) + env_size(4) + padding(3) + return_idx(4) + arg_count(4) = 20
        // Round up to 24 for alignment
        return 24;
    }
};
```

#### 1.3 Update WorkKind enum

Add a new work item type for pushing call frames:

```zig
// Update WorkKind enum (around line 87)
WorkKind = enum {
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
    
    // Call-related phases
    alloc_return_space,
    push_call_frame,        // NEW: Push call frame marker
    call_function,
    bind_parameters,
    eval_function_body,
    copy_result_to_return_space,
    cleanup_function,
};
```

#### 1.4 Keep Unified Closure Type

The unified Closure type from the original plan remains the same:

```zig
// Lines ~298-354: Already unified in your current code
pub const Closure = struct {
    body_expr_idx: CIR.ExprId,
    args_pattern_span: CIR.PatternSpan,
    captured_env: CapturedEnvironment,
    
    // ... existing methods ...
};
```

#### 1.5 Update `eval` method

Add handling for the new push_call_frame work item:

```zig
// In the eval method switch statement (around line 700)
.push_call_frame => try self.handlePushCallFrame(work.expr_idx),
```

#### 1.6 Update `handleCallFunction`

Modify to schedule call frame pushing:

```zig
// Around lines 1394-1458:
fn handleCallFunction(self: *Interpreter, call_expr_idx: CIR.ExprId) !void {
    const call_data = self.cir.exprs[call_expr_idx].e_call;
    
    if (DEBUG_ENABLED) {
        self.traceEnter("CALL FUNCTION (expr_idx={})", .{call_expr_idx});
    }
    
    // Determine if we need to evaluate the function first
    const function_expr = &self.cir.exprs[call_data.callee];
    
    switch (function_expr.*) {
        .e_lambda => {
            // Direct lambda call - we can push the call frame now
            try self.work_stack.append(.{
                .kind = .push_call_frame,
                .expr_idx = call_expr_idx,
            });
            
            // Schedule lambda evaluation
            try self.work_stack.append(.{
                .kind = .eval_expr,
                .expr_idx = call_data.callee,
            });
        },
        else => {
            // For other expressions (e.g., e_call returning a closure),
            // we need to evaluate the function first, then push call frame
            try self.work_stack.append(.{
                .kind = .push_call_frame,
                .expr_idx = call_expr_idx,
            });
            
            try self.work_stack.append(.{
                .kind = .eval_expr,
                .expr_idx = call_data.callee,
            });
        },
    }
    
    if (DEBUG_ENABLED) {
        self.traceExit("CALL FUNCTION scheduled");
    }
}
```

#### 1.7 Add `handlePushCallFrame`

New function to push the call frame marker:

```zig
// Add after handleCallFunction
fn handlePushCallFrame(self: *Interpreter, call_expr_idx: CIR.ExprId) !void {
    const call_data = self.cir.exprs[call_expr_idx].e_call;
    
    if (DEBUG_ENABLED) {
        self.traceEnter("PUSH CALL FRAME (expr_idx={})", .{call_expr_idx});
        self.traceStackState();
    }
    
    // At this point, the function has been evaluated and is on top of the stack
    // We need to capture its position before arguments are pushed
    
    // Get the function's layout (it's on top of layout_stack)
    const function_layout = self.layout_stack.items[self.layout_stack.items.len - 1];
    const function_size = function_layout.size(self.type_store, self.layout_cache);
    
    // Calculate function position (it's at the top of the stack)
    const function_pos = self.stack_memory.used - function_size;
    
    // The return space layout index will be determined later
    // For now, use a placeholder
    const return_layout_idx = self.layout_stack.items.len + @as(u32, @intCast(call_data.args.len));
    
    // Create call frame
    const call_frame = CallFrame{
        .function_pos = function_pos,
        .function_layout = function_layout,
        .return_layout_idx = return_layout_idx,
        .arg_count = @intCast(call_data.args.len),
    };
    
    // Allocate space for call frame
    const frame_size = CallFrame.size();
    const frame_pos = try self.stack_memory.alloc(frame_size, 8);
    
    // Write call frame to stack
    const frame_memory = self.stack_memory.getSlice(frame_pos, frame_size);
    call_frame.write(frame_memory);
    
    // Push a special layout marker for the call frame
    try self.layout_stack.append(layout.Layout{
        .tag = .scalar, // Use scalar tag with size matching CallFrame
        .data = .{ .scalar = .{ .size = frame_size } },
    });
    
    if (DEBUG_ENABLED) {
        self.traceInfo("Call frame pushed at position {}", .{frame_pos});
        self.traceInfo("  function_pos={}, arg_count={}", .{ function_pos, call_data.args.len });
        self.traceExit("PUSH CALL FRAME");
    }
    
    // Now schedule argument evaluation
    try self.work_stack.append(.{
        .kind = .bind_parameters,
        .expr_idx = call_expr_idx,
    });
    
    // Schedule arguments in reverse order (rightmost first)
    var i = call_data.args.len;
    while (i > 0) {
        i -= 1;
        try self.work_stack.append(.{
            .kind = .eval_expr,
            .expr_idx = call_data.args[i],
        });
    }
}
```

#### 1.8 Simplified `handleBindParameters`

Update to use the call frame instead of calculating position:

```zig
// Around lines 1611-1784:
fn handleBindParameters(self: *Interpreter, call_expr_idx: CIR.ExprId) !void {
    const call_data = self.cir.exprs[call_expr_idx].e_call;
    
    if (DEBUG_ENABLED) {
        self.traceEnter("handleBindParameters(expr_idx={})", .{call_expr_idx});
    }
    
    // Find the call frame on the stack
    // It should be below the arguments in the stack
    // Stack layout: [function] [call_frame] [arg0] [arg1] ... [argN] [return_space]
    
    // Calculate call frame position
    var frame_pos = self.stack_memory.used;
    
    // Skip return space
    const return_layout = self.layout_stack.items[self.layout_stack.items.len - 1];
    frame_pos -= return_layout.size(self.type_store, self.layout_cache);
    
    // Skip arguments
    var i: u32 = 0;
    while (i < call_data.args.len) : (i += 1) {
        const arg_idx = self.layout_stack.items.len - 2 - i;
        const arg_layout = self.layout_stack.items[arg_idx];
        frame_pos -= arg_layout.size(self.type_store, self.layout_cache);
    }
    
    // Skip call frame itself
    frame_pos -= CallFrame.size();
    
    // Read call frame
    const frame_memory = self.stack_memory.getSlice(frame_pos, CallFrame.size());
    const call_frame = CallFrame.read(frame_memory);
    
    if (DEBUG_ENABLED) {
        self.traceInfo("Read call frame: function_pos={}, arg_count={}", .{
            call_frame.function_pos, call_frame.arg_count,
        });
    }
    
    // Read the closure from the position stored in call frame
    const closure_memory = self.stack_memory.getSlice(
        call_frame.function_pos,
        @sizeOf(Closure),
    );
    const closure = Closure.read(closure_memory);
    
    if (DEBUG_ENABLED) {
        self.traceInfo("Found closure: body={}, args_len={}", .{
            closure.body_expr_idx, closure.args_pattern_span.len,
        });
    }
    
    // Verify arity
    if (closure.args_pattern_span.len != call_frame.arg_count) {
        if (DEBUG_ENABLED) {
            self.traceError("ARITY MISMATCH: expected={}, actual={}", .{
                closure.args_pattern_span.len, call_frame.arg_count,
            });
        }
        return error.ArityMismatch;
    }
    
    // Create new execution context
    const new_context = try self.allocator.create(ExecutionContext);
    new_context.* = ExecutionContext.init(self.allocator, self.current_context);
    try self.execution_contexts.append(new_context);
    self.current_context = new_context;
    
    // Bind parameters
    const patterns = self.cir.patterns[closure.args_pattern_span.offset..][0..closure.args_pattern_span.len];
    
    // Arguments are on the stack in order, starting after the call frame
    var arg_pos = frame_pos + CallFrame.size();
    
    for (patterns, 0..) |pattern_idx, arg_idx| {
        const arg_layout = self.layout_stack.items[
            self.layout_stack.items.len - call_frame.arg_count + arg_idx
        ];
        const arg_size = arg_layout.size(self.type_store, self.layout_cache);
        
        // Create binding
        const binding = ParameterBinding{
            .pattern_idx = pattern_idx,
            .value_ptr = self.stack_memory.getPtr(arg_pos),
            .layout = arg_layout,
        };
        
        try new_context.parameter_bindings.append(binding);
        arg_pos += arg_size;
        
        if (DEBUG_ENABLED) {
            self.traceInfo("Bound parameter {} at position {}", .{ arg_idx, arg_pos - arg_size });
        }
    }
    
    // Schedule function body evaluation
    try self.work_stack.append(.{
        .kind = .copy_result_to_return_space,
        .expr_idx = call_expr_idx,
    });
    
    try self.work_stack.append(.{
        .kind = .eval_function_body,
        .expr_idx = call_expr_idx,
    });
    
    if (DEBUG_ENABLED) {
        self.traceExit("handleBindParameters");
    }
}
```

#### 1.9 Update `handleCleanupFunction`

Clean up the call frame along with other data:

```zig
// In handleCleanupFunction, ensure we account for the call frame when cleaning up
fn handleCleanupFunction(self: *Interpreter, call_expr_idx: CIR.ExprId) !void {
    const call_data = self.cir.exprs[call_expr_idx].e_call;
    
    if (DEBUG_ENABLED) {
        self.traceEnter("CLEANUP FUNCTION (expr_idx={})", .{call_expr_idx});
    }
    
    // Pop execution context
    if (self.current_context) |ctx| {
        ctx.deinit();
        _ = self.execution_contexts.pop();
        self.current_context = if (self.execution_contexts.items.len > 0)
            self.execution_contexts.items[self.execution_contexts.items.len - 1]
        else
            null;
    }
    
    // Calculate total cleanup size
    // We need to clean up: function + call_frame + arguments
    var cleanup_size: u32 = 0;
    
    // Add function size
    const function_layout_idx = self.layout_stack.items.len - 
        2 - call_data.args.len - 1; // -1 for call frame
    const function_layout = self.layout_stack.items[function_layout_idx];
    cleanup_size += function_layout.size(self.type_store, self.layout_cache);
    
    // Add call frame size
    cleanup_size += CallFrame.size();
    
    // Add argument sizes
    var i: u32 = 0;
    while (i < call_data.args.len) : (i += 1) {
        const arg_layout_idx = self.layout_stack.items.len - 2 - call_data.args.len + i;
        const arg_layout = self.layout_stack.items[arg_layout_idx];
        cleanup_size += arg_layout.size(self.type_store, self.layout_cache);
    }
    
    // Get return value info
    const return_layout = self.layout_stack.items[self.layout_stack.items.len - 1];
    const return_size = return_layout.size(self.type_store, self.layout_cache);
    
    // Move return value to the beginning of cleaned area
    const return_src = self.stack_memory.used - return_size;
    const return_dst = self.stack_memory.used - cleanup_size - return_size;
    
    if (return_src != return_dst) {
        const return_data = self.stack_memory.getSlice(return_src, return_size);
        std.mem.copyForwards(u8, self.stack_memory.getSlice(return_dst, return_size), return_data);
    }
    
    // Update stack pointer
    self.stack_memory.used = return_dst + return_size;
    
    // Clean up layout stack
    // Remove: function + call_frame + args + return, then add back return
    const layouts_to_remove = 2 + call_data.args.len + 1;
    self.layout_stack.items.len -= layouts_to_remove;
    try self.layout_stack.append(return_layout);
    
    if (DEBUG_ENABLED) {
        self.traceInfo("Cleaned up {} bytes", .{cleanup_size});
        self.traceStackState();
        self.traceExit("CLEANUP FUNCTION");
    }
}
```

#### 1.10 Remove calculateClosurePosition

Delete the complex calculateClosurePosition function entirely - we don't need it anymore!

```zig
// DELETE lines 2282-2367 - the entire calculateClosurePosition function
```

## Testing Strategy

### 1. Existing Tests

All the failing tests should pass with these changes:
- `lambda expressions comprehensive`
- `lambda variable capture - multiple variables`  
- `lambda variable capture - nested closures`
- `lambda capture analysis - simple closure should use SimpleClosure`
- `lambda capture - conditional expressions with captures`
- `lambda variable capture - advanced multiple variables`

### 2. New Tests to Add

```zig
test "call frame marker correctly tracks function position" {
    // Test that call frames properly store and retrieve function positions
    // even with multiple nested calls
}

test "call cleanup properly handles call frames" {
    // Verify that cleanup correctly accounts for call frame size
}

test "arity mismatch detected with call frames" {
    // Ensure arity checking still works with the new system
}
```

## Implementation Order

1. **Phase 1: Add CallFrame struct**
   - Define CallFrame with serialization methods
   - Add to WorkKind enum

2. **Phase 2: Update Call Handling**
   - Modify handleCallFunction to use push_call_frame
   - Implement handlePushCallFrame
   - Update eval to handle new work item

3. **Phase 3: Simplify Parameter Binding**
   - Update handleBindParameters to read call frame
   - Remove calculateClosurePosition entirely

4. **Phase 4: Update Cleanup**
   - Ensure handleCleanupFunction accounts for call frames
   - Verify stack and layout stack stay synchronized

5. **Phase 5: Testing**
   - Run existing tests with trace enabled
   - Add new tests for call frame functionality

## Key Advantages of This Approach

1. **Simplicity**: No complex backward calculation or alignment handling
2. **Robustness**: Function position is explicitly stored, can't get out of sync
3. **Debuggability**: Call frames make it easy to see what's happening
4. **Performance**: Minimal overhead (24 bytes per call)
5. **Extensibility**: Call frames can store additional metadata if needed

## Debugging Tips

1. **Trace Call Frames**: Add tracing to show call frame contents
2. **Stack Dumps**: Print stack contents before/after call frame operations
3. **Assertions**: Verify call frame positions are within valid stack bounds
4. **Visual Stack**: Draw ASCII diagrams of stack layout in traces

The call frame approach is much simpler and more reliable than dynamic calculation. It's a common pattern in interpreters and virtual machines for good reason!