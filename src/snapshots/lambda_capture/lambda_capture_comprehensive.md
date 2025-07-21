# META
~~~ini
description=Comprehensive lambda capture detection with multiple scenarios
type=expr
~~~
# SOURCE
~~~roc
# block expression with many unused statements
{

    basic = |x| |y| x + y
    multi = |a, b| |c| a + b + c
    nested = |outer| |middle| |inner| outer + middle + inner
    simple = |x| x + 1
    mixed = |base| |n| n + base
    True # just returns True
}
~~~
# EXPECTED
NIL
# PROBLEMS
**UNUSED VARIABLE**
Variable `mixed` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_mixed` to suppress this warning.
The unused variable is declared here:
**lambda_capture_comprehensive.md:8:5:8:10:**
```roc
    mixed = |base| |n| n + base
```
    ^^^^^


**UNUSED VARIABLE**
Variable `simple` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_simple` to suppress this warning.
The unused variable is declared here:
**lambda_capture_comprehensive.md:7:5:7:11:**
```roc
    simple = |x| x + 1
```
    ^^^^^^


**UNUSED VARIABLE**
Variable `basic` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_basic` to suppress this warning.
The unused variable is declared here:
**lambda_capture_comprehensive.md:4:5:4:10:**
```roc
    basic = |x| |y| x + y
```
    ^^^^^


**UNUSED VARIABLE**
Variable `multi` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_multi` to suppress this warning.
The unused variable is declared here:
**lambda_capture_comprehensive.md:5:5:5:10:**
```roc
    multi = |a, b| |c| a + b + c
```
    ^^^^^


**UNUSED VARIABLE**
Variable `nested` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_nested` to suppress this warning.
The unused variable is declared here:
**lambda_capture_comprehensive.md:6:5:6:11:**
```roc
    nested = |outer| |middle| |inner| outer + middle + inner
```
    ^^^^^^


# TOKENS
~~~zig
OpenCurly(2:1-2:2),
LowerIdent(4:5-4:10),OpAssign(4:11-4:12),OpBar(4:13-4:14),LowerIdent(4:14-4:15),OpBar(4:15-4:16),OpBar(4:17-4:18),LowerIdent(4:18-4:19),OpBar(4:19-4:20),LowerIdent(4:21-4:22),OpPlus(4:23-4:24),LowerIdent(4:25-4:26),
LowerIdent(5:5-5:10),OpAssign(5:11-5:12),OpBar(5:13-5:14),LowerIdent(5:14-5:15),Comma(5:15-5:16),LowerIdent(5:17-5:18),OpBar(5:18-5:19),OpBar(5:20-5:21),LowerIdent(5:21-5:22),OpBar(5:22-5:23),LowerIdent(5:24-5:25),OpPlus(5:26-5:27),LowerIdent(5:28-5:29),OpPlus(5:30-5:31),LowerIdent(5:32-5:33),
LowerIdent(6:5-6:11),OpAssign(6:12-6:13),OpBar(6:14-6:15),LowerIdent(6:15-6:20),OpBar(6:20-6:21),OpBar(6:22-6:23),LowerIdent(6:23-6:29),OpBar(6:29-6:30),OpBar(6:31-6:32),LowerIdent(6:32-6:37),OpBar(6:37-6:38),LowerIdent(6:39-6:44),OpPlus(6:45-6:46),LowerIdent(6:47-6:53),OpPlus(6:54-6:55),LowerIdent(6:56-6:61),
LowerIdent(7:5-7:11),OpAssign(7:12-7:13),OpBar(7:14-7:15),LowerIdent(7:15-7:16),OpBar(7:16-7:17),LowerIdent(7:18-7:19),OpPlus(7:20-7:21),Int(7:22-7:23),
LowerIdent(8:5-8:10),OpAssign(8:11-8:12),OpBar(8:13-8:14),LowerIdent(8:14-8:18),OpBar(8:18-8:19),OpBar(8:20-8:21),LowerIdent(8:21-8:22),OpBar(8:22-8:23),LowerIdent(8:24-8:25),OpPlus(8:26-8:27),LowerIdent(8:28-8:32),
UpperIdent(9:5-9:9),
CloseCurly(10:1-10:2),EndOfFile(10:2-10:2),
~~~
# PARSE
~~~clojure
(e-block @2.1-10.2
	(statements
		(s-decl @4.5-4.26
			(p-ident @4.5-4.10 (raw "basic"))
			(e-lambda @4.13-4.26
				(args
					(p-ident @4.14-4.15 (raw "x")))
				(e-lambda @4.17-4.26
					(args
						(p-ident @4.18-4.19 (raw "y")))
					(e-binop @4.21-4.26 (op "+")
						(e-ident @4.21-4.22 (raw "x"))
						(e-ident @4.25-4.26 (raw "y"))))))
		(s-decl @5.5-5.33
			(p-ident @5.5-5.10 (raw "multi"))
			(e-lambda @5.13-5.33
				(args
					(p-ident @5.14-5.15 (raw "a"))
					(p-ident @5.17-5.18 (raw "b")))
				(e-lambda @5.20-5.33
					(args
						(p-ident @5.21-5.22 (raw "c")))
					(e-binop @5.24-5.33 (op "+")
						(e-ident @5.24-5.25 (raw "a"))
						(e-binop @5.28-5.33 (op "+")
							(e-ident @5.28-5.29 (raw "b"))
							(e-ident @5.32-5.33 (raw "c")))))))
		(s-decl @6.5-6.61
			(p-ident @6.5-6.11 (raw "nested"))
			(e-lambda @6.14-6.61
				(args
					(p-ident @6.15-6.20 (raw "outer")))
				(e-lambda @6.22-6.61
					(args
						(p-ident @6.23-6.29 (raw "middle")))
					(e-lambda @6.31-6.61
						(args
							(p-ident @6.32-6.37 (raw "inner")))
						(e-binop @6.39-6.61 (op "+")
							(e-ident @6.39-6.44 (raw "outer"))
							(e-binop @6.47-6.61 (op "+")
								(e-ident @6.47-6.53 (raw "middle"))
								(e-ident @6.56-6.61 (raw "inner"))))))))
		(s-decl @7.5-7.23
			(p-ident @7.5-7.11 (raw "simple"))
			(e-lambda @7.14-7.23
				(args
					(p-ident @7.15-7.16 (raw "x")))
				(e-binop @7.18-7.23 (op "+")
					(e-ident @7.18-7.19 (raw "x"))
					(e-int @7.22-7.23 (raw "1")))))
		(s-decl @8.5-8.32
			(p-ident @8.5-8.10 (raw "mixed"))
			(e-lambda @8.13-8.32
				(args
					(p-ident @8.14-8.18 (raw "base")))
				(e-lambda @8.20-8.32
					(args
						(p-ident @8.21-8.22 (raw "n")))
					(e-binop @8.24-8.32 (op "+")
						(e-ident @8.24-8.25 (raw "n"))
						(e-ident @8.28-8.32 (raw "base"))))))
		(e-tag @9.5-9.9 (raw "True"))))
~~~
# FORMATTED
~~~roc
{

	basic = |x| |y| x + y
	multi = |a, b| |c| a + b + c
	nested = |outer| |middle| |inner| outer + middle + inner
	simple = |x| x + 1
	mixed = |base| |n| n + base
	True # just returns True
}
~~~
# CANONICALIZE
~~~clojure
(e-block @2.1-10.2
	(s-let @4.5-4.26
		(p-assign @4.5-4.10 (ident "basic"))
		(e-lambda @4.13-4.26
			(args
				(p-assign @4.14-4.15 (ident "x")))
			(e-lambda @4.17-4.26
				(args
					(p-assign @4.18-4.19 (ident "y")))
				(captures
					(capture (name "x")))
				(e-binop @4.21-4.26 (op "add")
					(e-lookup-local @4.21-4.22
						(p-assign @4.14-4.15 (ident "x")))
					(e-lookup-local @4.25-4.26
						(p-assign @4.18-4.19 (ident "y")))))))
	(s-let @5.5-5.33
		(p-assign @5.5-5.10 (ident "multi"))
		(e-lambda @5.13-5.33
			(args
				(p-assign @5.14-5.15 (ident "a"))
				(p-assign @5.17-5.18 (ident "b")))
			(e-lambda @5.20-5.33
				(args
					(p-assign @5.21-5.22 (ident "c")))
				(captures
					(capture (name "a"))
					(capture (name "b")))
				(e-binop @5.24-5.33 (op "add")
					(e-lookup-local @5.24-5.25
						(p-assign @5.14-5.15 (ident "a")))
					(e-binop @5.28-5.33 (op "add")
						(e-lookup-local @5.28-5.29
							(p-assign @5.17-5.18 (ident "b")))
						(e-lookup-local @5.32-5.33
							(p-assign @5.21-5.22 (ident "c"))))))))
	(s-let @6.5-6.61
		(p-assign @6.5-6.11 (ident "nested"))
		(e-lambda @6.14-6.61
			(args
				(p-assign @6.15-6.20 (ident "outer")))
			(e-lambda @6.22-6.61
				(args
					(p-assign @6.23-6.29 (ident "middle")))
				(e-lambda @6.31-6.61
					(args
						(p-assign @6.32-6.37 (ident "inner")))
					(captures
						(capture (name "outer"))
						(capture (name "middle")))
					(e-binop @6.39-6.61 (op "add")
						(e-lookup-local @6.39-6.44
							(p-assign @6.15-6.20 (ident "outer")))
						(e-binop @6.47-6.61 (op "add")
							(e-lookup-local @6.47-6.53
								(p-assign @6.23-6.29 (ident "middle")))
							(e-lookup-local @6.56-6.61
								(p-assign @6.32-6.37 (ident "inner")))))))))
	(s-let @7.5-7.23
		(p-assign @7.5-7.11 (ident "simple"))
		(e-lambda @7.14-7.23
			(args
				(p-assign @7.15-7.16 (ident "x")))
			(e-binop @7.18-7.23 (op "add")
				(e-lookup-local @7.18-7.19
					(p-assign @7.15-7.16 (ident "x")))
				(e-int @7.22-7.23 (value "1")))))
	(s-let @8.5-8.32
		(p-assign @8.5-8.10 (ident "mixed"))
		(e-lambda @8.13-8.32
			(args
				(p-assign @8.14-8.18 (ident "base")))
			(e-lambda @8.20-8.32
				(args
					(p-assign @8.21-8.22 (ident "n")))
				(captures
					(capture (name "base")))
				(e-binop @8.24-8.32 (op "add")
					(e-lookup-local @8.24-8.25
						(p-assign @8.21-8.22 (ident "n")))
					(e-lookup-local @8.28-8.32
						(p-assign @8.14-8.18 (ident "base")))))))
	(e-nominal @9.5-9.9 (nominal "Bool")
		(e-tag @9.5-9.9 (name "True"))))
~~~
# TYPES
~~~clojure
(expr @2.1-10.2 (type "Bool"))
~~~
