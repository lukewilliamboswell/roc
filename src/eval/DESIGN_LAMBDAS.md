# Lambda Captures - Debugging Plan & Current Status

## 🎯 Current Status: Bug Identified, Ready for Focused Debugging

### ✅ **What's Working**
- **Capture Detection**: Canonicalization perfectly identifies captured variables
- **Lambda Creation**: Lambdas with captures are created correctly (`env_size=1`)
- **Basic Infrastructure**: Stack-based interpreter, layout system, parameter binding all functional
- **Test Infrastructure**: Comprehensive test suite with proper debug instrumentation

### ❌ **The Bug: Layout Information Lost During Function Returns**
**Root Cause**: Closures with captures are created correctly but layout information (`env_size`) is corrupted/lost when returned from function calls.

## 🔍 **Evidence of the Bug**

### **During Lambda Creation** (✅ Works)
```
DEBUG: 🎯 LAMBDA WITH CAPTURES: 1 variables
DEBUG: 📐 LAMBDA LAYOUT CREATION: has_captures=true, captured_vars.len=1, env_size=1
DEBUG: 📐 LAYOUT PUSHED: tag=closure, env_size=1
```

### **During Subsequent Calls** (❌ Broken)
```
DEBUG: 🔍 CAPTURE CHECK: tag=closure, env_size=0
DEBUG: 🚫 EARLY RETURN: Not a closure with captures
```

### **The Problem**
In test case `((|x| |y| x + y)(42))(10)`:
1. ✅ First call `(|x| |y| x + y)(42)`: Creates inner lambda with `env_size=1`
2. ❌ Second call `((inner_lambda))(10)`: Layout shows `env_size=0`

**Conclusion**: The capture record approach is sound. The bug is in stack/layout management during function returns.

## 🎯 **Focused Debugging Plan**

### **Phase 1: Single Test Case Deep Dive**
**Target Test**: `lambda variable capture - basic single variable`
**Source**: `((|x| |y| x + y)(42))(10)`
**Expected Result**: `52` (42 + 10)

### **Debugging Strategy**
1. **Add test-specific debug filter** to trace only our target test
2. **Follow the complete execution path** step by step
3. **Identify exactly where layout information is lost**
4. **Fix the specific issue** without changing the overall approach
5. **Verify the fix works** for the target test
6. **Move to next test case**

### **Key Questions to Answer**
1. **When** does `env_size` change from `1` to `0`?
2. **Where** in the call/return mechanism is layout information lost?
3. **How** should layout information be preserved across function returns?

## 📋 **Implementation Plan**

### **Step 1: Add Test-Specific Tracing**
```zig
const TEST_FILTER = "basic single variable";
if (std.mem.indexOf(u8, debug_context, TEST_FILTER)) |_| {
    std.debug.print("TRACE[{}]: {}\n", .{TEST_FILTER, debug_message});
}
```

### **Step 2: Trace Critical Points**
- Lambda creation with captures
- Layout stack operations
- Function call setup
- Function return handling  
- Layout information retrieval

### **Step 3: Identify Root Cause**
Focus on the transition between:
- Creating closure with `env_size=1`
- Calling closure that shows `env_size=0`

### **Step 4: Implement Targeted Fix**
- Preserve layout information during returns
- Ensure closure metadata survives stack operations
- Verify capture record is added correctly

## 🧪 **Test Case Focus**

### **Primary Test Case**
```roc
((|x| |y| x + y)(42))(10)
```

**Expected Flow**:
1. **Parse**: Nested lambda structure with captures detected
2. **Canonicalize**: Inner lambda shows `(captures (capture (name "x")))`
3. **Create Outer Lambda**: `|x|` (no captures)
4. **Call Outer Lambda**: `(outer_lambda)(42)` 
5. **Execute Outer Lambda**: Creates inner lambda `|y| x + y` with `env_size=1`
6. **Return Inner Lambda**: Layout preserved with `env_size=1`
7. **Call Inner Lambda**: `(inner_lambda)(10)` detects `env_size=1`
8. **Add Capture Record**: Automatically append captured `x=42`
9. **Bind Parameters**: `y=10`, `capture_record={x: 42}`
10. **Execute Body**: `x + y` → `42 + 10 = 52`

**Current Failure Point**: Step 7 - Inner lambda shows `env_size=0` instead of `env_size=1`

### **Debug Commands**
```bash
# Run with tracing and filter for our test
zig build test -Dtrace-eval 2>&1 | grep -A 5 -B 5 "basic single variable"

# Focus on layout information
zig build test -Dtrace-eval 2>&1 | grep -E "env_size|LAMBDA WITH CAPTURES|CAPTURE CHECK"

# Track the specific expressions in our test
zig build test -Dtrace-eval 2>&1 | grep -E "expr=(81|79)" | head -20
```

## 🔧 **Technical Approach**

### **The Capture Record Strategy** (Confirmed Correct)
1. **Detection**: Canonicalization identifies captures ✅
2. **Creation**: Lambda with captures uses `Closure` struct ✅  
3. **Calling**: `handleCaptureArguments` adds capture record as extra argument
4. **Binding**: Parameters include regular args + capture record
5. **Execution**: Body has access to captured variables

### **The Bug Location** (Stack/Layout Management)
- **Not** in capture detection
- **Not** in the fundamental approach
- **Likely** in function return mechanism
- **Likely** in layout stack preservation

### **Minimal Fix Strategy**
1. **Preserve** layout information across function returns
2. **Ensure** returned closures maintain their `env_size` 
3. **Verify** layout stack operations don't corrupt closure metadata

## 📊 **Success Criteria**

### **Immediate Success**
```bash
# This should work
zig build test 2>&1 | grep "lambda variable capture - basic single variable"
# Should show: PASSED

# Debug output should show
DEBUG: 🔍 CAPTURE CHECK: tag=closure, env_size=1  # Not env_size=0
DEBUG: 🎯 ADDING CAPTURE RECORD: env_size=1       # Actually adding record
DEBUG: Result: 52                                  # Correct computation
```

### **Secondary Tests** (Once Primary Works)
1. `lambda variable capture - multiple variables`
2. `lambda variable capture - nested closures`
3. `lambda capture - conditional expressions with captures`

### **Final Success**
- All capture tests pass
- No regression in non-capture tests
- Clean debug output showing capture flow working correctly

## 🔍 **Next Session Workflow**

### **Step 1**: Add test-specific debug filtering
### **Step 2**: Trace the failing test case end-to-end
### **Step 3**: Identify where `env_size=1` becomes `env_size=0`
### **Step 4**: Fix the layout preservation issue
### **Step 5**: Verify fix and move to next test

### **Key Files to Focus On**
- `src/eval/interpreter.zig` - Main execution logic
- `src/eval/eval_test.zig` - Test cases and verification
- Layout stack operations in function calls/returns

---

**Bottom Line**: The capture detection and approach are correct. We have a specific, debuggable stack management bug. The focused debugging approach should quickly identify and fix the issue, leading to working lambda captures.