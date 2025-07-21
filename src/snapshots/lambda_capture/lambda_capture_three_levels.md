# META
~~~ini
description=Three-level nested lambda captures - innermost lambda captures from all outer levels
type=expr
~~~
# SOURCE
~~~roc
|outer| |middle| |inner| outer + middle + inner
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:7),OpBar(1:7-1:8),OpBar(1:9-1:10),LowerIdent(1:10-1:16),OpBar(1:16-1:17),OpBar(1:18-1:19),LowerIdent(1:19-1:24),OpBar(1:24-1:25),LowerIdent(1:26-1:31),OpPlus(1:32-1:33),LowerIdent(1:34-1:40),OpPlus(1:41-1:42),LowerIdent(1:43-1:48),EndOfFile(1:48-1:48),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.48
	(args
		(p-ident @1.2-1.7 (raw "outer")))
	(e-lambda @1.9-1.48
		(args
			(p-ident @1.10-1.16 (raw "middle")))
		(e-lambda @1.18-1.48
			(args
				(p-ident @1.19-1.24 (raw "inner")))
			(e-binop @1.26-1.48 (op "+")
				(e-ident @1.26-1.31 (raw "outer"))
				(e-binop @1.34-1.48 (op "+")
					(e-ident @1.34-1.40 (raw "middle"))
					(e-ident @1.43-1.48 (raw "inner")))))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.48
	(args
		(p-assign @1.2-1.7 (ident "outer")))
	(e-lambda @1.9-1.48
		(args
			(p-assign @1.10-1.16 (ident "middle")))
		(e-lambda @1.18-1.48
			(args
				(p-assign @1.19-1.24 (ident "inner")))
			(captures
				(capture (name "outer"))
				(capture (name "middle")))
			(e-binop @1.26-1.48 (op "add")
				(e-lookup-local @1.26-1.31
					(p-assign @1.2-1.7 (ident "outer")))
				(e-binop @1.34-1.48 (op "add")
					(e-lookup-local @1.34-1.40
						(p-assign @1.10-1.16 (ident "middle")))
					(e-lookup-local @1.43-1.48
						(p-assign @1.19-1.24 (ident "inner"))))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.48 (type "Num(_size) -> Num(_size2) -> Num(_size3) -> Num(_size4)"))
~~~
