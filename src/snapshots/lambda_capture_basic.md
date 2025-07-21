# META
~~~ini
description=Basic lambda capture detection during canonicalization
type=expr
~~~
# SOURCE
~~~roc
|x| |y| x + y
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:3),OpBar(1:3-1:4),OpBar(1:5-1:6),LowerIdent(1:6-1:7),OpBar(1:7-1:8),LowerIdent(1:9-1:10),OpPlus(1:11-1:12),LowerIdent(1:13-1:14),EndOfFile(1:14-1:14),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.14
	(args
		(p-ident @1.2-1.3 (raw "x")))
	(e-lambda @1.5-1.14
		(args
			(p-ident @1.6-1.7 (raw "y")))
		(e-binop @1.9-1.14 (op "+")
			(e-ident @1.9-1.10 (raw "x"))
			(e-ident @1.13-1.14 (raw "y")))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.14
	(args
		(p-assign @1.2-1.3 (ident "x")))
	(e-lambda @1.5-1.14
		(args
			(p-assign @1.6-1.7 (ident "y")))
		(e-binop @1.9-1.14 (op "add")
			(e-lookup-local @1.9-1.10
				(p-assign @1.2-1.3 (ident "x")))
			(e-lookup-local @1.13-1.14
				(p-assign @1.6-1.7 (ident "y"))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.14 (type "Num(_size) -> Num(_size2) -> Num(_size3)"))
~~~
