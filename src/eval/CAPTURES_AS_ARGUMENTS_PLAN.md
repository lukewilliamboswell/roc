# Lambda Captures as Function Arguments - Implementation Plan

## Overview

Based on guidance from Richard Feldman, this plan implements lambda captures by transforming closures to include captured variables as a hidden record argument. This approach reuses existing function call machinery and avoids complex memory management.

## 🎯 **Current Implementation Status**

**MAJOR MILESTONE ACHIEVED**: ✅ **PHASE 1 COMPLETE - CANONICALIZATION CAPTURE DETECTION**
- **Capture Detection**: ✅ IMPLEMENTED - Function context tracking identifies captured variables during canonicalization
- **CIR Integration**: ✅ IMPLEMENTED - Lambda expressions enhanced with capture information  
- **Old Code Removal**: ✅ COMPLETED - All execution-time capture analysis eliminated
- **Compilation**: ✅ VERIFIED - All code compiles and basic functionality maintained
- **Debug Validation**: ✅ WORKING - Capture information visible in snapshot test output

**NEXT PHASE**: 📋 **COMPREHENSIVE TESTING BEFORE FINAL IMPLEMENTATION**

## Core Concept: Captures as Hidden Arguments

### The Transform

**User writes:**
```roc
outer = |x| 
    inner = |y| x + y  # 'x' is captured
    inner
```

**Interpreter sees (conceptually):**
```roc
outer = |x|
    inner = |y, captures| captures.x + y  # 'x' comes from captures record
    inner
```

**When calling:**
```roc
my_fn = outer(5)
result = my_fn(3)  # Interpreter automatically passes {x: 5}
```

### Key Principles

1. **Invisible to Users**: Capture arguments never appear in type errors or signatures
2. **Record-Based**: All captures bundled into a single record argument  
3. **Automatic**: Interpreter handles capture record creation and passing
4. **Reuses Infrastructure**: Leverage existing parameter binding and record systems

## Revised Implementation Plan

### ✅ Phase 1: Canonicalization Capture Detection [COMPLETED]

#### ✅ 1.1 Track Current Function Context [IMPLEMENTED]
**File**: `roc/src/check/canonicalize.zig`

**STATUS**: ✅ COMPLETE - Function context stack successfully implemented
```zig
/// Context for tracking captures during canonicalization
const FunctionContext = struct {
    depth: u32,
    captures: std.ArrayList(CapturedVariable),
    // ... implementation complete
};

/// Stack of function contexts for nested lambdas  
function_contexts: std.ArrayListUnmanaged(FunctionContext),
```

#### ✅ 1.2 Capture Detection During Variable Resolution [IMPLEMENTED]

**STATUS**: ✅ COMPLETE - Integrated into existing variable lookup logic
```zig
// In canonicalizeExpr, within variable lookup:
// Check if this is a capture (variable from outer function context)
const variable_function_context = self.getPatternFunctionContext(pattern_idx);
const current_function_context = self.getCurrentFunctionDepth();

if (variable_function_context < current_function_context) {
    // This is a capture! Record it for current function
    try self.recordCapture(ident, pattern_idx, variable_function_context);
}
```

**KEY INSIGHT DISCOVERED**: Pattern function context depth (not scope depth) is the correct comparison for capture detection.

fn recordCapture(self: *Self, name: base.Ident, pattern_idx: CIR.Pattern.Idx, source_depth: u32) !void {
    const current_context = &self.function_contexts.items[self.function_contexts.items.len - 1];
    
    // Avoid duplicate captures
    for (current_context.captures.items) |existing| {
        if (existing.pattern_idx == pattern_idx) return;
    }
    
    try current_context.captures.append(CapturedVariable{
        .name = name,
        .pattern_idx = pattern_idx, 
        .source_scope_depth = source_depth,
    });
}
```

#### 1.3 Function Context Management
```zig
/// Enter a new function context when processing lambda
fn enterFunctionContext(self: *Self) !void {
    try self.function_contexts.append(FunctionContext{
        .depth = self.function_contexts.items.len,
        .captures = std.ArrayList(CapturedVariable).init(self.gpa),
    });
}

/// Exit function context and return captured variables
fn exitFunctionContext(self: *Self) FunctionContext {
    return self.function_contexts.pop();
}
```

### ✅ Phase 2: Enhanced CIR Structure [COMPLETED]

#### ✅ 2.1 Extended Lambda Expression [IMPLEMENTED] 
**File**: `roc/src/check/canonicalize/Expression.zig`

**STATUS**: ✅ COMPLETE - CIR successfully enhanced with capture information
```zig
pub const Expr = union(enum) {
    // ... existing expressions ...
    
    e_lambda: struct {
        args: Pattern.Span,
        body: Expr.Idx,
        captures: CaptureInfo,  // ✅ IMPLEMENTED: Capture information
    },
};

/// ✅ IMPLEMENTED: Capture information structures
pub const CaptureInfo = struct {
    captured_vars: []const CapturedVar,
    capture_pattern_idx: ?Pattern.Idx,
    
    pub const empty = CaptureInfo{
        .captured_vars = &[_]CapturedVar{},
        .capture_pattern_idx = null,
    };
};
```

pub const CaptureInfo = struct {
    /// Variables captured by this lambda
    captured_vars: []const CapturedVar,
    /// Pre-computed record pattern for captures (optimization)
    capture_pattern_idx: ?Pattern.Idx,
};

pub const CapturedVar = struct {
    name: base.Ident,
    pattern_idx: Pattern.Idx,
    scope_depth: u32,
};
```

#### 2.2 Lambda Canonicalization With Captures
```zig
/// Canonicalize lambda with capture detection
fn canonicalizeLambda(self: *Self, lambda: ast.Lambda, region: Region) !CIR.Expr.Idx {
    // Enter function context
    try self.enterFunctionContext();
    defer {
        // Clean up context after processing
        var context = self.exitFunctionContext();
        context.captures.deinit();
    }
    
    // Canonicalize lambda parameters normally
    const args_pattern_span = try self.canonicalizePatternSpan(lambda.args);
    
    // Canonicalize body (this will detect and record captures)
    const body_expr_idx = try self.canonicalizeExpr(lambda.body);
    
    // Get captures from context
    const context = &self.function_contexts.items[self.function_contexts.items.len - 1];
    
    // Create capture info
    const capture_info = if (context.captures.items.len > 0) blk: {
        // Build capture record pattern if needed
        const capture_pattern_idx = try self.createCaptureRecordPattern(context.captures.items);
        
        // Store captures in arena for CIR
        const captured_vars = try self.arena.dupe(CapturedVar, context.captures.items);
        
        break :blk CaptureInfo{
            .captured_vars = captured_vars,
            .capture_pattern_idx = capture_pattern_idx,
        };
    } else CaptureInfo{
        .captured_vars = &[_]CapturedVar{},
        .capture_pattern_idx = null,
    };
    
    return try self.can_ir.addExprAndTypeVar(CIR.Expr{
        .e_lambda = .{
            .args = args_pattern_span,
            .body = body_expr_idx, 
            .captures = capture_info,
        }
    }, lambda_type, region);
}
```

### ✅ Phase 3: NodeStore Integration [COMPLETED]

#### ✅ 3.1 Storage for Enhanced Lambdas [IMPLEMENTED]
**File**: `roc/src/check/canonicalize/NodeStore.zig`

**STATUS**: ✅ COMPLETE - Capture information storage and retrieval working

```zig
/// Store lambda with capture information
.expr_lambda_with_captures => {
    node.tag = .expr_lambda_with_captures;
    node.data_1 = extra_data_start;
    
    // Store in extra_data:
    // [0] = args.start
    // [1] = args.len
    // [2] = body_expr_idx  
    // [3] = captures_start (index into captures array)
    // [4] = captures_len
},

/// Arrays for capture storage
captured_vars: std.ArrayListUnmanaged(CapturedVar) = .{},
capture_infos: std.ArrayListUnmanaged(CaptureInfo) = .{},
```

### 🔄 Phase 4: Interpreter Argument Transformation [IN PROGRESS]

#### 🔄 4.1 Lambda Creation with Effective Arguments [PARTIALLY IMPLEMENTED]
**File**: `roc/src/eval/interpreter.zig`

**STATUS**: 🔄 PARTIAL - Basic framework implemented, needs completion

```zig
.e_lambda => |lambda_expr| {
    // Create effective arguments (original + capture record if needed)
    const original_patterns = self.cir.store.slicePatterns(lambda_expr.args);
    const has_captures = lambda_expr.captures.captured_vars.len > 0;
    
    if (has_captures) {
        // Create new pattern span with capture record as last argument
        const effective_args = try self.createEffectiveArgs(original_patterns, lambda_expr.captures);
        
        const closure = SimpleClosure{
            .body_expr_idx = lambda_expr.body,
            .args_pattern_span = effective_args,
        };
        
        // Store original capture info for call site processing
        try self.lambda_capture_info.put(lambda_expr.body, lambda_expr.captures);
    } else {
        // No captures - create simple closure normally  
        const closure = SimpleClosure{
            .body_expr_idx = lambda_expr.body,
            .args_pattern_span = lambda_expr.args,
        };
    }
    
    // ... rest of closure creation ...
}

fn createEffectiveArgs(self: *Interpreter, original_args: []Pattern.Idx, captures: CaptureInfo) !Pattern.Span {
    // Build new pattern list with capture record appended
    var effective_patterns = std.ArrayList(Pattern.Idx).init(self.allocator);
    defer effective_patterns.deinit();
    
    try effective_patterns.appendSlice(original_args);
    
    if (captures.capture_pattern_idx) |pattern_idx| {
        try effective_patterns.append(pattern_idx);
    }
    
    return self.cir.store.addPatternSpan(effective_patterns.items);
}
```

#### 4.2 Function Calls with Automatic Capture Passing
```zig
.e_call => |call_expr| {
    // ... existing call setup ...
    
    // Check if function being called has captures
    const function_expr = self.cir.store.getExpr(call.function);
    
    if (function_expr == .e_lambda) {
        const lambda = function_expr.e_lambda;
        
        if (lambda.captures.captured_vars.len > 0) {
            // Build capture record from current execution context
            const capture_record = try self.buildCaptureRecord(lambda.captures);
            
            // Push capture record as additional argument
            try self.pushCaptureRecord(capture_record);
            
            // Update argument count for parameter binding
            self.adjustArgumentCountForCaptures(1);
        }
    }
    
    // ... continue with normal call processing ...
}

fn buildCaptureRecord(self: *Interpreter, captures: CaptureInfo) !*anyopaque {
    // Create record with captured variable values
    const record_size = self.calculateCaptureRecordSize(captures);
    const record_ptr = try self.stack_memory.alloca(record_size, @alignOf(u64));
    
    // Initialize record fields with current variable values
    var field_offset: usize = 0;
    for (captures.captured_vars) |captured_var| {
        // Look up current value of captured variable
        const current_value = self.lookupCurrentValue(captured_var.pattern_idx);
        
        // Copy value into record field
        const field_size = self.getVariableSize(captured_var.pattern_idx);
        @memcpy(
            @as([*]u8, @ptrCast(record_ptr)) + field_offset,
            @as([*]const u8, @ptrCast(current_value)),
            field_size
        );
        
        field_offset += field_size;
    }
    
    return record_ptr;
}
```

### ✅ Phase 5: Variable Lookup Simplification [COMPLETED]

#### ✅ 5.1 Remove Complex Captured Environment Logic [IMPLEMENTED]

**STATUS**: ✅ COMPLETE - All old execution-time analysis removed
```zig
// OLD complex approach (DELETE):
// - CapturedEnvironment structures
// - searchCapturedEnvironment functions  
// - enhanceClosureWithCaptures logic
// - Complex registry management

// NEW simple approach:
.e_lookup_local => |lookup| {
    // Just use normal parameter binding - captured variables come through
    // as record fields in the capture argument
    
    for (self.parameter_bindings.items) |binding| {
        if (binding.pattern_idx == lookup.pattern_idx) {
            // Found in parameters (including capture record fields)
            return self.createValueFromBinding(binding);
        }
    }
    
    // Fall back to global definitions
    return self.lookupGlobalDefinition(lookup.pattern_idx);
}
```

## 📋 **CRITICAL NEXT PHASE: COMPREHENSIVE TESTING**

### **Testing Strategy Before Final Implementation**

**PRIORITY**: Develop comprehensive snapshot test suite to validate capture detection before completing interpreter implementation.

#### **Test Categories Required**:

1. **Basic Capture Scenarios**
   ```roc
   # Single capture
   |x| |y| x + y
   
   # Multiple captures  
   |a, b| |c| a + b + c
   ```

2. **Complex Nesting Scenarios**
   ```roc
   # Three-level nesting
   |outer| |middle| |inner| outer + middle + inner
   
   # Mixed capture patterns
   |a| {
       simple = |x| x + 1,    # No captures
       capture = |y| a + y    # Captures 'a'
       { simple, capture }
   }
   ```

3. **Edge Cases & Regression Prevention**
   ```roc
   # No captures (regression test)
   |x| x + 1
   
   # Partial application scenarios
   |x| |y| |z| x + y + z
   ```

4. **Compiler Pipeline Validation**
   - Verify PARSE stage handles nested lambdas correctly
   - Confirm CANONICALIZE shows capture information in debug output
   - Ensure TYPES stage processes captures without errors
   - Validate capture information survives all compilation phases

#### **Success Criteria for Testing Phase**:
- [ ] Comprehensive test matrix covering all capture scenarios
- [ ] All tests show correct capture information in canonicalized output  
- [ ] Edge cases documented and validated
- [ ] Regression tests confirm existing lambda functionality maintained
- [ ] Clear debugging output for capture analysis validation

## Benefits of This Approach

### 1. **Reuses Existing Infrastructure**
- ✅ Parameter binding handles captures automatically
- ✅ Record system handles capture grouping  
- ✅ Type system works normally with record types
- ✅ No special memory management needed

### 2. **Fixes Current Issues**
- ✅ **Stack Position Bug**: Captures are just more arguments - no special positioning
- ✅ **Timing Issues**: No execution-time analysis needed
- ✅ **Memory Corruption**: No complex pointer management
- ✅ **Arity Mismatches**: Clear argument accounting

### 3. **Cleaner Architecture**
- ✅ **Single Responsibility**: Each phase has clear role
- ✅ **Type Safety**: Captures properly typed like other values  
- ✅ **Error Messages**: Natural error reporting for capture issues
- ✅ **Debugging**: Standard argument debugging applies

### 4. **Performance Benefits**
- ✅ **No Runtime Analysis**: All capture info computed statically at canonicalization time
- ✅ **Efficient Calls**: Standard function call overhead (when fully implemented)
- ✅ **Memory Locality**: Captures passed by value in records (framework ready)
- ✅ **Optimization Ready**: Standard function optimizations apply (cleaner than execution-time analysis)

## Migration Strategy

### Phase 1: Implement Alongside Current System
- Add new capture detection to canonicalization  
- Keep existing interpreter logic working
- Feature flag for new approach

### Phase 2: Test and Validate
- Comprehensive test suite with both approaches
- Performance benchmarking
- Edge case validation

### Phase 3: Switch Over
- Enable new approach by default
- Remove old execution-time capture analysis
- Clean up unused code

### Phase 4: Polish and Optimize
- Refine capture record layout
- Optimize argument passing 
- Add advanced features (partial application, etc.)

## 📊 **Current Test Results & Validation**

### ✅ Capture Detection Validated
**Test**: `lambda_capture_debug.md`
```roc
|outer_var| |inner_param| outer_var + inner_param
```
**Result**: ✅ SUCCESS - Canonicalized output shows:
```clojure
(captures
    (capture (name "outer_var")))
```

### ✅ Complex Nesting Validated  
**Test**: `lambda_capture_comprehensive.md`
```roc
{
    basic: |x| |y| x + y,
    multi: |a, b| |c| a + b + c,
    nested: |outer| |middle| |inner| outer + middle + inner,
}
```
**Results**: ✅ SUCCESS - All capture scenarios correctly detected and displayed

### Test Cases for Final Implementation

### Multiple Captures  
```roc
outer = |x, y|
    inner = |z| x + y + z  # Captures both 'x' and 'y'  
    inner

result = outer(1, 2)(3)  # Should be 6
```

### Nested Captures
```roc
level1 = |a|
    level2 = |b|
        level3 = |c| a + b + c  # Captures 'a' and 'b'
        level3
    level2

result = level1(1)(2)(3)  # Should be 6  
```

### No Captures (Regression Test)
```roc
simple = |x| x + 1  # No captures
result = simple(5)  # Should be 6
```

## 🗓️ **Revised Implementation Timeline**

### ✅ **COMPLETED** (Previous Sessions)
- **✅ Week 1-2**: Canonicalization capture detection & CIR enhancements
- **✅ Week 3**: NodeStore integration & old system cleanup  
- **✅ Week 4**: Basic interpreter framework setup

### 📋 **CURRENT PHASE** (Next Session)
- **📋 Week 5**: Comprehensive snapshot test development
  - Develop systematic test matrix for all capture scenarios
  - Validate PARSE → CANONICALIZE → TYPES pipeline
  - Document edge cases and regression tests
  - Ensure robust debugging and validation infrastructure

### 🔄 **REMAINING WORK** (Future Sessions)  
- **🔄 Week 6**: Complete interpreter argument transformation
- **🔄 Week 7**: End-to-end integration testing and validation
- **🔄 Week 8**: Performance optimization and final polish

## 🎯 **Key Lessons Learned**

1. **Timing Is Critical**: Capture analysis must happen when both definitions and references are available (canonicalization time)
2. **Function Context vs Scope**: Variables are captured based on function context depth, not general scope depth  
3. **Test-Driven Validation**: Snapshot tests provide reliable validation of each compiler phase independently
4. **Incremental Approach Works**: Systematic refactoring maintains functionality while evolving architecture
5. **Debug Output Essential**: Rich debugging with visual indicators (🎯) crucial for complex compiler features

This methodical approach has successfully moved capture analysis to canonicalization time, providing a much simpler and more maintainable foundation for lambda captures.