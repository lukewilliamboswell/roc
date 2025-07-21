# Lambda Capture Implementation - Next Session Plan

## Current Status (End of Session)

### ✅ Completed
1. **Code Cleanup**: DONE
2. **Architecture Decision**: Implemented embedding layout information directly in closure structures
3. **Struct Updates**: Added `layout: layout.Layout` field to both `SimpleClosure` and `Closure`
4. **LANDING PAD Implementation**: Modified LANDING PAD allocation to initialize closures with embedded layout info
5. **Capture Detection Logic**: Updated `handleCaptureArguments` to read layout from embedded closure data

### ❌ Core Issue Remains
**Lambda captures still fail with `env_size=0` instead of expected capture counts**

## Root Cause Analysis

### What's Working ✅
- **Canonicalization**: Correctly detects captures (e.g., `(capture (name "a"))`, `(capture (name "b"))`, etc.)
- **Some Lambda Creation**: We see traces like `📋 COPY RESULT: layout.tag=closure, env_size=3`
- **Basic Lambda Infrastructure**: Simple lambdas without captures work fine

### What's Failing ❌
- **Capture Argument Handling**: Shows `🔍 CAPTURE CHECK: tag=closure, env_size=0` instead of expected counts
- **Memory Corruption**: Large garbage numbers like `148873535527910577783673135168705527884` in arithmetic
- **Closure Size**: Still shows 12 bytes (old size) instead of larger size with embedded layout

### Key Insight 🔍
**The closures being called are NOT going through our modified LANDING PAD code path**
- LANDING PAD handles direct `e_lambda` calls
- But closures returned from function calls (e_call case) use a different creation path
- Our embedded layout modifications only affect LANDING PAD path

## Critical Next Steps

### 1. **Find All Closure Creation Paths** (HIGHEST PRIORITY)
The LANDING PAD is not the only place closures are created. Need to audit:

**Search Tasks:**
```bash
grep -r "SimpleClosure\|Closure.*=" src/eval/
grep -r "\.body_expr_idx.*=" src/eval/
grep -r "@sizeOf.*Closure" src/eval/
```

**Likely Additional Paths:**
- Closure copying during function returns
- Closure creation in expression evaluation outside LANDING PAD
- Layout cache closure size calculations
- Stack memory closure allocation

### 2. **Fix Layout Size Calculations**
The layout cache needs to know about the new closure sizes:

**Files to Check:**
- `src/layout/store.zig` - layout size calculations
- `src/layout/layout.zig` - closure layout definitions
- Any `layoutSize()` method that handles closures

**Expected Changes:**
- `SimpleClosure` size should increase from ~12 to ~12+sizeof(Layout)
- `Closure` size should increase from ~16 to ~16+sizeof(Layout)

### 3. **Trace Complete Closure Lifecycle**
Need to understand the full flow:

**Add Tracing To:**
- All closure allocation points (not just LANDING PAD)
- Closure copying operations
- Layout stack operations involving closures
- Memory corruption detection in arithmetic operations

### 4. **Fix Memory Corruption**
The large garbage numbers suggest:
- Wrong memory alignment
- Incorrect pointer calculations
- Stack corruption during closure operations

### 5. **Test-Driven Development**
**Focus Tests:**
- `(|a, b, c| |x| a + b + c + x)(10, 20, 5)(7)` → should equal 42
- Enable tracing on ONE test only to avoid output confusion

## Architecture Validation

### The Embedded Layout Approach is Sound ✅
- Layout information travels with closure automatically
- No complex coordination between separate tracking systems
- Eliminates the closure pointer stack complexity

### Implementation Gap ❌
- Only LANDING PAD path updated
- Other closure creation paths still use old structures
- Layout cache doesn't account for new sizes

## Debugging Strategy

### Systematic Approach:
1. **Single Test Focus**: Use only the advanced multiple variables test with tracing
2. **Size Verification**: Confirm all closure allocations use new sizes
3. **Memory Tracking**: Add corruption detection to arithmetic operations
4. **Path Coverage**: Ensure all closure creation paths use embedded layout

### Success Criteria:
- `🔍 CAPTURE CHECK: tag=closure, env_size=3` (not 0)
- `🎯 ADDING CAPTURE RECORD: env_size=3` (actually executed)
- Arithmetic operations with normal numbers (not garbage)
- Test result: `42` for `(|a, b, c| |x| a + b + c + x)(10, 20, 5)(7)`

## Files That Need Attention

### High Priority:
- `src/eval/interpreter.zig` - Find all closure creation paths
- `src/layout/store.zig` - Update size calculations
- `src/layout/layout.zig` - Verify closure layout definitions

### Medium Priority:
- Memory alignment and corruption detection
- Stack management during closure operations
- Test isolation and tracing cleanup

## Risk Assessment

### Low Risk:
- Architecture is sound
- Code cleanup was successful
- Basic infrastructure works

### High Risk:
- Memory corruption suggests deeper issues
- Multiple closure creation paths may exist
- Stack/layout management complexity

## Estimated Effort

**Next Session Focus**: 2-3 hours
1. Find all closure creation paths (30 min)
2. Update layout size calculations (30 min)
3. Fix memory corruption (60-90 min)
4. Verify with focused test (30 min)

**Success Probability**: High - we have good understanding of the issue and clear next steps.
