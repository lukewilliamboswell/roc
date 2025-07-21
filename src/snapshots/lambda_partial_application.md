# META
~~~ini
description=Partial application with captures - lambda returns lambda that captures outer variables
type=expr
~~~
# SOURCE
~~~roc
|x| |y| |z| x + y + z
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:3),OpBar(1:3-1:4),OpBar(1:5-1:6),LowerIdent(1:6-1:7),OpBar(1:7-1:8),OpBar(1:9-1:10),LowerIdent(1:10-1:11),OpBar(1:11-1:12),LowerIdent(1:13-1:14),OpPlus(1:15-1:16),LowerIdent(1:17-1:18),OpPlus(1:19-1:20),LowerIdent(1:21-1:22),EndOfFile(1:22-1:22),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.22
	(args
		(p-ident @1.2-1.3 (raw "x")))
	(e-lambda @1.5-1.22
		(args
			(p-ident @1.6-1.7 (raw "y")))
		(e-lambda @1.9-1.22
			(args
				(p-ident @1.10-1.11 (raw "z")))
			(e-binop @1.13-1.22 (op "+")
				(e-ident @1.13-1.14 (raw "x"))
				(e-binop @1.17-1.22 (op "+")
					(e-ident @1.17-1.18 (raw "y"))
					(e-ident @1.21-1.22 (raw "z")))))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.22
	(args
		(p-assign @1.2-1.3 (ident "x")))
	(e-lambda @1.5-1.22
		(args
			(p-assign @1.6-1.7 (ident "y")))
		(e-lambda @1.9-1.22
			(args
				(p-assign @1.10-1.11 (ident "z")))
			(captures
				(capture (name "x"))
				(capture (name "y")))
			(e-binop @1.13-1.22 (op "add")
				(e-lookup-local @1.13-1.14
					(p-assign @1.2-1.3 (ident "x")))
				(e-binop @1.17-1.22 (op "add")
					(e-lookup-local @1.17-1.18
						(p-assign @1.6-1.7 (ident "y")))
					(e-lookup-local @1.21-1.22
						(p-assign @1.10-1.11 (ident "z"))))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.22 (type "Num(_size) -> Num(_size2) -> Num(_size3) -> Num(_size4)"))
~~~
