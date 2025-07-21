# Next Session Plan: Lambda Capture Testing & Final Implementation

## 🎯 **Session Objective**
Develop comprehensive snapshot test suite to validate capture detection before completing the interpreter implementation.

## ✅ **Current Status Summary**
- **MAJOR MILESTONE**: Capture analysis successfully moved to canonicalization
- **Architecture Complete**: Captures-as-arguments framework implemented
- **Code Cleanup**: All old execution-time analysis removed
- **Compilation**: Everything compiles and basic functionality maintained
- **Validation**: Basic capture detection working and visible in debug output

## 📋 **PRIORITY 1: Comprehensive Snapshot Test Development** [IMMEDIATE]

### **Testing Strategy**
**Goal**: Validate capture detection accuracy before any further interpreter changes.

**Why Testing First**: 
- Ensures capture detection logic is rock-solid before building on it
- Provides regression safety net for complex compiler features
- Validates each compiler phase (PARSE → CANONICALIZE → TYPES) independently

### **Required Test Matrix**

#### **1. Basic Capture Scenarios**
```roc
# Test: lambda_capture_single.md
|x| |y| x + y

# Test: lambda_capture_multiple.md  
|a, b| |c| a + b + c
```

#### **2. Complex Nesting Scenarios**
```roc
# Test: lambda_capture_three_levels.md
|outer| |middle| |inner| outer + middle + inner

# Test: lambda_capture_mixed_patterns.md
|base| {
    simple = |x| x + 1,      # No captures
    withCapture = |y| base + y # Captures 'base'
}
```

#### **3. Edge Cases & Regression Prevention**
```roc
# Test: lambda_no_captures.md (regression)
|x| x + 1

# Test: lambda_partial_application.md
|x| |y| |z| x + y + z

# Test: lambda_complex_expressions.md
|outer| |inner| if outer > 0 then outer + inner else inner
```

#### **4. Error Handling & Boundary Conditions**
```roc
# Test: lambda_invalid_references.md
|x| |y| x + z  # Reference to undefined 'z'

# Test: lambda_deep_nesting.md
|a| |b| |c| |d| |e| a + b + c + d + e
```

### **Success Criteria for Each Test**
- [ ] **Parse Stage**: Correctly parses nested lambda structure
- [ ] **Canonicalize Stage**: Shows capture information in debug output
- [ ] **Types Stage**: Processes without errors  
- [ ] **Capture Detection**: Accurately identifies captured variables
- [ ] **Debug Output**: Clear capture information visible (e.g., `(capture (name "var_name"))`)

### **Test Validation Process**
1. **Create Test File**: Write snapshot test with clear description
2. **Run Snapshot**: `zig build snapshot -- src/snapshots/test_name.md`
3. **Verify Output**: Check CANONICALIZE section shows capture information
4. **Document Results**: Note any issues or unexpected behavior
5. **Iterate**: Fix any detection issues before proceeding

## 📋 **PRIORITY 2: Complete Interpreter Implementation** [AFTER TESTING]

### **Remaining Implementation Tasks**
Only proceed after comprehensive testing validates capture detection.

#### **2.1 Complete Capture Record Creation**
**File**: `roc/src/eval/interpreter.zig`
- **Function**: Complete `handleCaptureArguments` implementation
- **Task**: Finish capture value collection from current execution context
- **Current Status**: Framework exists, needs completion

#### **2.2 Enhance Parameter Binding** 
**File**: `roc/src/eval/interpreter.zig`
- **Function**: Update `handleBindParameters` 
- **Task**: Handle capture records as hidden arguments
- **Integration**: Ensure capture records bind like regular parameters

#### **2.3 End-to-End Integration Testing**
**Tests**: Create execution tests (not just canonicalization)
- **Basic**: `(|x| |y| x + y)(5)(3)` should equal `8`
- **Complex**: Multi-level nesting execution validation
- **Performance**: Verify no significant slowdown vs. simple lambdas

## 🎯 **Session Success Metrics**

### **Phase 1 Complete (Testing)**
- [ ] **Test Coverage**: At least 8-10 comprehensive snapshot tests created
- [ ] **Pipeline Validation**: PARSE → CANONICALIZE → TYPES working for all scenarios
- [ ] **Capture Detection**: All expected captures show in canonicalized output  
- [ ] **Edge Cases**: Boundary conditions and error cases documented
- [ ] **Regression Safety**: Existing lambda functionality confirmed working

### **Phase 2 Complete (Implementation)**
- [ ] **Capture Records**: Automatic capture record creation working
- [ ] **Parameter Binding**: Capture records handled as hidden arguments
- [ ] **End-to-End**: Basic nested closure execution: `((|x| |y| x + y)(5))(3) == 8`
- [ ] **Performance**: No significant performance degradation

## 🚨 **Critical Implementation Guidelines**

### **Testing Phase Guidelines**
1. **Test Everything**: Don't assume capture detection works in untested scenarios
2. **Validate Each Stage**: Check PARSE, CANONICALIZE, and TYPES output for every test
3. **Document Failures**: Any capture detection issues must be fixed before interpreter work
4. **Keep Tests**: All snapshot tests become permanent regression tests

### **Implementation Phase Guidelines**
1. **No Shortcuts**: Only proceed after testing phase is complete
2. **Incremental Changes**: Make small, testable changes to interpreter
3. **Debug Output**: Maintain rich debugging throughout implementation
4. **Test After Each Change**: Validate functionality at each step

## 🔧 **Commands for Testing Session**

```bash
# Create new snapshot test
cd roc
touch src/snapshots/lambda_capture_[scenario].md

# Run specific test
zig build snapshot -- src/snapshots/lambda_capture_[scenario].md

# Run all tests to check for regressions
zig build test
```

## 📚 **Key Files to Focus On**

### **Testing Phase**
- `roc/src/snapshots/lambda_capture_*.md` - New test files
- `roc/src/check/canonicalize.zig` - If capture detection needs fixes

### **Implementation Phase** (After Testing)
- `roc/src/eval/interpreter.zig` - Complete capture argument handling
- `roc/src/eval/interpreter.zig` - Update parameter binding for captures

## 🎉 **Expected Outcome**

By the end of the next session:
1. **Rock-solid capture detection** validated by comprehensive tests
2. **Clear understanding** of any edge cases or limitations
3. **Solid foundation** for completing the interpreter implementation
4. **Confidence** that the captures-as-arguments approach will work reliably

**Bottom Line**: Thorough testing now saves debugging time later and ensures a robust implementation! 🚀