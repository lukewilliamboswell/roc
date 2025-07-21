# Detailed Design - Lambda Evaluation [IMPLEMENTATION STATUS]

## Overview

This design supports evaluating functions in Roc, treating functions as values that can be stored, passed, and returned using a unified closure representation.

**Implementation Status**:
1. ✅ **Simple Lambdas**: IMPLEMENTED - Basic function calls with parameter binding
2. 🔧 **Currying Functions**: PLANNED - Functions that return other functions with partial application  
3. ❌ **True Closures**: BLOCKED - Capture analysis works, but execution timing issue identified
4. 🔧 **Recursive Functions**: PLANNED - Self-referencing functions with tail-call optimization

## 🎯 Current Implementation Status

### ✅ **COMPLETED AND VERIFIED**
- **ExecutionContext Stack**: ✅ IMPLEMENTED - Proper scope chain management with parent context traversal
- **Unified Closure Architecture**: ✅ IMPLEMENTED - `Closure` structure with `CapturedEnvironment` support
- **Capture Analysis Algorithm**: ✅ IMPLEMENTED - Correctly identifies variables to capture from nested scopes
- **Memory Management**: ✅ IMPLEMENTED - Single-block allocation strategy with proper alignment
- **Layout System Integration**: ✅ IMPLEMENTED - `ClosureLayout` with environment size tracking
- **Debug Tracing Infrastructure**: ✅ IMPLEMENTED - Comprehensive tracing with clear markers for all phases
- **Basic Lambda Support**: ✅ WORKING - Simple closures (`SimpleClosure`) execute correctly
- **Function Calling Convention**: ✅ WORKING - Complete 7-phase call sequence operational

### 🚧 **ROOT CAUSE IDENTIFIED - CRITICAL TIMING ISSUE**
- **Variable Capture Execution**: ❌ BLOCKED by fundamental timing problem
  - **Issue**: Capture analysis happens during lambda **creation** (parsing phase) when variables aren't bound yet
  - **Required**: Capture analysis must happen during lambda **execution** when execution context is available
  - **Current Behavior**: Inner lambda `|y| x + y` tries to capture `x` before outer lambda `|x| ...` has bound `x`
  - **Impact**: All nested closures fail with "pattern not found in parameter bindings or execution contexts"

### 🔧 **ARCHITECTURAL LESSONS LEARNED**

#### ❌ **FAILED APPROACH: Deferred Initialization**
- **Attempted**: Create closure structure immediately, defer environment initialization until execution
- **Result**: Bus errors and recursive panics due to complex memory management
- **Lesson**: Avoid deferred initialization - too complex and error-prone

#### ✅ **CORRECT APPROACH: Execution-Time Capture Analysis**
- **Strategy**: Move capture analysis from lambda creation to lambda execution
- **Location**: During `handleBindParameters` after outer lambda parameters are bound
- **Benefit**: Execution context is fully populated when inner lambdas need to capture variables

### 🔧 **PLANNED**
- **Multi-Parameter Currying**: `(|a| |b| a + b)(1)(2)` syntax support
- **Partial Application**: Automatic currying for under-applied functions
- **Recursive Functions**: Self-reference injection and tail-call optimization  
- **Multi-Level Nesting**: Deeply nested closures with complex scope chains

### 📊 **Test Coverage Status**
- ✅ Simple lambdas: `(|x| x + 1)(5)` → 6
- ✅ Multi-parameter: `(|x, y| x + y)(3, 4)` → 7  
- ✅ Capture analysis: `(|x| (|y| x + y))(42)` → correctly detects 1 captured variable
- ❌ End-to-end capture: `(|x| (|y| x + y))(5)` → blocked on timing issue
- ❌ Multi-parameter currying: `(|a| |b| a + b)(1)(2)` → not yet implemented
- ❌ Recursive functions: not yet implemented

## 🎯 Next Sprint - Immediate Priority

### **Sprint Goal: Complete True Closures**

**Objective**: Fix the timing issue to enable nested closures with variable capture.

#### **Task 1: Fix Capture Analysis Timing 🔥 CRITICAL**

**Problem**: 
```roc
(|x| (|y| x + y))(5)
#    ^^^^^^^^^^ inner lambda created during outer lambda creation
#    at this point, x is not bound yet, so capture fails
```

**Solution**: Move capture analysis to execution time in `handleBindParameters`:

```zig
fn handleBindParameters(self: *Interpreter, call_expr_idx: CIR.Expr.Idx) EvalError!void {
    // ... existing parameter binding code ...
    
    // AFTER parameters are bound, check if closure body needs capture analysis
    if (closure_requires_nested_lambdas(closure_ptr.body_expr_idx)) {
        // NOW execution context has bound variables available
        try self.analyzeAndInitializeNestedCaptures(closure_ptr);
    }
}
```

#### **Task 2: Test-Driven Development Sequence**

1. **Simple Nested**: `(|x| (|y| x + y))(5)` → should return closure that captures x=5
2. **Execute Nested**: `((|x| (|y| x + y))(5))(3)` → should return 8 (5+3)
3. **Multi-Level**: `(|a| (|b| (|c| a + b + c)))(1)` → three-level nesting
4. **Multi-Parameter Currying**: `(|a| |b| a + b)(1)(2)` → should return 3

#### **Task 3: Multi-Parameter Currying Support**

**Roc Syntax**:
```roc
(|a| |b| a + b)        # equivalent to (|a| (|b| a + b))
(|a| |b| a + b)(1)     # partial application → (|b| 1 + b)  
(|a| |b| a + b)(1)(2)  # full application → 3
```

**Implementation**: Detect consecutive lambda parameters and create nested structure:
- Parse `|a| |b| body` as `|a| (|b| body)`
- Ensure capture analysis works for this nested structure
- Test currying chain: `f(1)(2)` where `f = |a| |b| a + b`

## 🏗️ Implementation Architecture

### ✅ **ExecutionContext Stack (WORKING)**

```zig
const ExecutionContext = struct {
    parameter_bindings: std.ArrayList(ParameterBinding),
    parent_context: ?*ExecutionContext,
    
    fn findBinding(self: *const ExecutionContext, pattern_idx: CIR.Pattern.Idx) ?ParameterBinding {
        // Search current context
        for (self.parameter_bindings.items) |binding| {
            if (binding.pattern_idx == pattern_idx) return binding;
        }
        // Search parent contexts
        if (self.parent_context) |parent| {
            return parent.findBinding(pattern_idx);
        }
        return null;
    }
};
```

**Status**: ✅ Implemented and working. Scope chain traversal correctly finds variables from parent contexts.

### 🔧 **Execution-Time Capture Analysis (NEXT TASK)**

```zig
fn analyzeAndInitializeNestedCaptures(self: *Interpreter, closure: *SimpleClosure) !void {
    // Check if closure body contains nested lambdas that need capture
    const needs_capture = try self.detectNestedLambdas(closure.body_expr_idx);
    if (!needs_capture) return;
    
    // NOW we can do capture analysis with full execution context
    var capture_analysis = CaptureAnalysis.analyzeLambdaBody(
        self.allocator, self.cir, closure.body_expr_idx, closure.args_pattern_span
    );
    defer capture_analysis.deinit();
    
    if (capture_analysis.captured_vars.items.len > 0) {
        // Convert SimpleClosure to enhanced Closure at execution time
        try self.enhanceClosureWithCaptures(closure, capture_analysis);
    }
}
```

### ✅ **Unified Closure Architecture (WORKING)**

```zig
pub const Closure = struct {
    body_expr_idx: CIR.Expr.Idx,
    args_pattern_span: CIR.Pattern.Span,
    captured_env: ?*CapturedEnvironment,  // null for simple closures
};

const CapturedEnvironment = struct {
    bindings: []CapturedBinding,
    parent_env: ?*CapturedEnvironment,    // for nested scope chains
    
    fn findCapturedVariable(self: *const CapturedEnvironment, pattern_idx: CIR.Pattern.Idx) ?*CapturedBinding {
        // Search current environment
        for (self.bindings) |*binding| {
            if (binding.pattern_idx == pattern_idx) return binding;
        }
        // Search parent environments
        if (self.parent_env) |parent| {
            return parent.findCapturedVariable(pattern_idx);
        }
        return null;
    }
};
```

## 📋 Test Cases for Next Sprint

### **Primary Test Cases (Must Pass)**

```zig
test "nested closure with capture - execution timing fix" {
    const src = "(|x| (|y| x + y))(5)";
    // Should create closure that captures x=5, not fail with "pattern not found"
    const result = try interpreter.eval(resources.expr_idx);
    try testing.expect(result.layout.tag == .closure);
}

test "nested closure end-to-end execution" {
    const src = "((|x| (|y| x + y))(5))(3)";
    // Should return 8 (5 + 3)
    const result = try interpreter.eval(resources.expr_idx);
    try testing.expectEqual(@as(i64, 8), extractInt(result));
}

test "multi-parameter currying syntax" {
    const sources = [_][]const u8{
        "(|a| |b| a + b)",           // equivalent to (|a| (|b| a + b))
        "(|a| (|b| a + b))",         // explicit nesting
    };
    
    for (sources) |src| {
        const result = try interpreter.eval(parseExpr(src));
        try testing.expect(result.layout.tag == .closure);
        // Both should create identical closure structures
    }
}

test "multi-parameter currying application" {
    const test_cases = [_]struct { src: []const u8, expected: i64 }{
        .{ .src = "(|a| |b| a + b)(1)(2)", .expected = 3 },           // full application
        .{ .src = "(|a| |b| |c| a + b + c)(1)(2)(3)", .expected = 6 }, // three-level currying
    };
    
    for (test_cases) |case| {
        const result = try interpreter.eval(parseExpr(case.src));
        try testing.expectEqual(case.expected, extractInt(result));
    }
}

test "partial application currying" {
    const src = "(|a| |b| a + b)(10)";  
    // Should return closure equivalent to (|b| 10 + b)
    const partial = try interpreter.eval(parseExpr(src));
    try testing.expect(partial.layout.tag == .closure);
    
    // Apply remaining argument
    const final_src = "((|a| |b| a + b)(10))(5)";
    const result = try interpreter.eval(parseExpr(final_src));
    try testing.expectEqual(@as(i64, 15), extractInt(result));
}
```

### **Secondary Test Cases (Nice to Have)**

```zig
test "deeply nested closures with multiple captures" {
    const src = "(|a| (|b| (|c| a + b + c)))(1)";
    // Should handle three levels of nesting correctly
}

test "nested closures with mixed capture patterns" {
    const src = 
        \\(|x, y|
        \\    inner1 = |z| x + z
        \\    inner2 = |w| y + w  
        \\    |a| inner1(a) + inner2(a)
        \\)(10, 20)
    ;
    // Multiple inner closures with different capture patterns
}
```

## 🚨 Critical Implementation Notes

### **DO NOT ATTEMPT**
- ❌ **Deferred Initialization**: Causes crashes and memory corruption
- ❌ **Complex Memory Management**: Single-block allocation is sufficient
- ❌ **Capture Analysis During Parsing**: Wrong timing - variables not bound yet

### **PROVEN WORKING PATTERNS**
- ✅ **ExecutionContext Stack**: Reliable scope chain management
- ✅ **Single-Block Allocation**: Clean memory management for closures  
- ✅ **7-Phase Calling Convention**: Robust function call handling
- ✅ **Debug Tracing with Emojis**: Essential for debugging complex capture flows

### **KEY INSIGHT FOR SUCCESS**
> **The timing of capture analysis is everything.** Variables must be bound in the execution context before inner lambdas can capture them. Move capture analysis from lambda creation to lambda execution.

## 🎯 Success Criteria for Next Sprint

1. ✅ **Fix Timing Issue**: `(|x| (|y| x + y))(5)` creates closure successfully
2. ✅ **End-to-End Capture**: `((|x| (|y| x + y))(5))(3)` returns 8
3. ✅ **Currying Syntax**: `(|a| |b| a + b)` parsed as nested lambdas
4. ✅ **Currying Execution**: `(|a| |b| a + b)(1)(2)` returns 3
5. ✅ **Partial Application**: `(|a| |b| a + b)(1)` returns curried closure

**When these pass, true closures and currying will be complete in Roc! 🚀**