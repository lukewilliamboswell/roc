# META
~~~ini
description=Debug test for basic capture detection - outer variable captured by inner lambda
type=expr
~~~
# SOURCE
~~~roc
|outer_var| |inner_param| outer_var + inner_param
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:11),OpBar(1:11-1:12),OpBar(1:13-1:14),LowerIdent(1:14-1:25),OpBar(1:25-1:26),LowerIdent(1:27-1:36),OpPlus(1:37-1:38),LowerIdent(1:39-1:50),EndOfFile(1:50-1:50),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.50
	(args
		(p-ident @1.2-1.11 (raw "outer_var")))
	(e-lambda @1.13-1.50
		(args
			(p-ident @1.14-1.25 (raw "inner_param")))
		(e-binop @1.27-1.50 (op "+")
			(e-ident @1.27-1.36 (raw "outer_var"))
			(e-ident @1.39-1.50 (raw "inner_param")))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.50
	(args
		(p-assign @1.2-1.11 (ident "outer_var")))
	(e-lambda @1.13-1.50
		(args
			(p-assign @1.14-1.25 (ident "inner_param")))
		(captures
			(capture (name "outer_var")))
		(e-binop @1.27-1.50 (op "add")
			(e-lookup-local @1.27-1.36
				(p-assign @1.2-1.11 (ident "outer_var")))
			(e-lookup-local @1.39-1.50
				(p-assign @1.14-1.25 (ident "inner_param"))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.50 (type "Num(_size) -> Num(_size2) -> Num(_size3)"))
~~~
