# Plan: Improve Capture Analysis in Canonicalization

## 1. Goal

The primary goal is to shift the responsibility of complete and accurate lambda capture analysis from the interpreter to the canonicalization phase of the compiler. This will provide the interpreter with a definitive list of all required captures for every lambda, eliminating the need for the recursive, runtime analysis I recently implemented as a workaround.

## 2. Background & Motivation

Currently, the capture analysis performed during canonicalization is incomplete. It fails to identify variables that are captured by *nested* lambdas, which means the `captures` list on a `CIR.Expr.Lambda` node is often missing entries.

This forced the implementation of a workaround (`findCapturesInExpr`) within the interpreter to re-analyze the expression tree at runtime. This approach has two main drawbacks:

1.  **Inefficiency:** It performs redundant analysis during evaluation that should be handled once at compile-time.
2.  **Poor Design:** It breaks the separation of concerns. The interpreter, which should focus on execution, is burdened with a complex static analysis task.

By moving this logic into the canonicalization step, we can create a more robust, efficient, and maintainable system.

## 3. Proposed Implementation Plan (Single-Pass Approach)

Instead of a separate analysis pass, we can integrate free variable analysis directly into the existing canonicalization functions. This is more efficient as it avoids a second traversal of the expression tree.

### 3.1. The Traversal Algorithm

The core idea is to modify the `canonicalize_expr` function (and its helpers) to not only return the canonicalized `CIR.Expr.Idx`, but also the set of **free variables** discovered within that expression.

-   **Free Variables:** A variable is "free" in an expression if it is used within that expression but is not defined (bound) within that same expression.

The logic for the modified `canonicalize_expr` function would be as follows:

1.  **Modify Function Signature:** The function signature will change from `(env, ast_node) -> CIR.Expr.Idx` to something like `(env, ast_node) -> (CIR.Expr.Idx, FreeVarSet)`, where `FreeVarSet` is a data structure like a `HashMap<CIR.Pattern.Idx, base.Ident.Idx>`.

2.  **Base Cases:**
    *   When canonicalizing an `e_lookup_local` node, the function returns the new `CIR.Expr.Idx` and a `FreeVarSet` containing just that single variable.
    *   For literals (`e_int`, `e_str`, etc.), it returns the `CIR.Expr.Idx` and an empty `FreeVarSet`.

3.  **Recursive Step (Compound Expressions):**
    *   When canonicalizing a node like `e_binop`, `e_if`, `e_block` (includes many statements), or `e_call`, the function will first recursively call itself on all children expressions.
    *   It will then **union** the `FreeVarSet`s returned from these recursive calls to compute the set of free variables for the compound expression. This unioned set is then returned to its caller.

4.  **Special Case (`e_lambda`):**
    *   When canonicalizing a lambda, first recursively call `canonicalize_expr` on its body. This will return the body's `CIR.Expr.Idx` and its `FreeVarSet`.
    *   Determine the set of variables that are bound by the lambda's own parameters (e.g., by traversing the `lambda.args` patterns).
    *   The **true captures** for the lambda are the free variables of its body **minus** the variables bound by its parameters.
    *   This final, correct set of captures should be stored in the `lambda.captures` field in the CIR.
    *   The `FreeVarSet` that the lambda canonicalization function returns to *its* parent is this same set of true captures.

### 3.2. Implementation Steps

1.  **Modify Canonicalization Signatures:** Update the function signature for `canonicalize_expr` and its related helper functions throughout the `.../check/canonicalize/...` modules to include the `FreeVarSet` return value.

2.  **Update Call Sites:** Adjust all call sites of these modified functions to handle the new return type. This will involve receiving the `FreeVarSet` and passing it up the call stack, unioning it with sets from sibling expressions.

3.  **Implement Set Logic:**
    *   Use an efficient set data structure (like a `HashMap`) for the `FreeVarSet`.
    *   Implement the `union` and `subtract` operations for these sets.

4.  **Update Lambda Canonicalization:** Modify the specific logic for canonicalizing lambdas to perform the subtraction of parameter-bound variables and to populate the `captures` list in the CIR correctly.

5.  **Simplify the Interpreter:**
    *   With the CIR now providing a complete and accurate list of captures, the workaround in the interpreter can be removed entirely.
    *   Delete the `findCapturesInExpr` function.
    *   Simplify `collectAndFilterCaptures` to trust and directly use the `lambda.captures` list from the CIR, without any filtering or re-analysis.

## 4. Expected Benefits

-   **Correctness by Design:** Capture analysis will be a well-defined, compile-time step.
-   **Performance:** The interpreter will be faster, and the compiler avoids a second, full traversal of the CIR.
-   **Improved Architecture:** A cleaner separation of concerns between the compiler's static analysis and the interpreter's execution logic.
