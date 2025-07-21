# META
~~~ini
description=Complex expressions with captures - lambda with conditionals and captures
type=expr
~~~
# SOURCE
~~~roc
|outer| |inner| if outer > 0 (outer + inner) else inner
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:7),OpBar(1:7-1:8),OpBar(1:9-1:10),LowerIdent(1:10-1:15),OpBar(1:15-1:16),KwIf(1:17-1:19),LowerIdent(1:20-1:25),OpGreaterThan(1:26-1:27),Int(1:28-1:29),OpenRound(1:30-1:31),LowerIdent(1:31-1:36),OpPlus(1:37-1:38),LowerIdent(1:39-1:44),CloseRound(1:44-1:45),KwElse(1:46-1:50),LowerIdent(1:51-1:56),EndOfFile(1:56-1:56),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.56
	(args
		(p-ident @1.2-1.7 (raw "outer")))
	(e-lambda @1.9-1.56
		(args
			(p-ident @1.10-1.15 (raw "inner")))
		(e-if-then-else @1.17-1.56
			(e-binop @1.20-1.29 (op ">")
				(e-ident @1.20-1.25 (raw "outer"))
				(e-int @1.28-1.29 (raw "0")))
			(e-tuple @1.30-1.45
				(e-binop @1.31-1.44 (op "+")
					(e-ident @1.31-1.36 (raw "outer"))
					(e-ident @1.39-1.44 (raw "inner"))))
			(e-ident @1.51-1.56 (raw "inner")))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.56
	(args
		(p-assign @1.2-1.7 (ident "outer")))
	(e-lambda @1.9-1.56
		(args
			(p-assign @1.10-1.15 (ident "inner")))
		(captures
			(capture (name "outer")))
		(e-if @1.17-1.56
			(if-branches
				(if-branch
					(e-binop @1.20-1.29 (op "gt")
						(e-lookup-local @1.20-1.25
							(p-assign @1.2-1.7 (ident "outer")))
						(e-int @1.28-1.29 (value "0")))
					(e-binop @1.31-1.44 (op "add")
						(e-lookup-local @1.31-1.36
							(p-assign @1.2-1.7 (ident "outer")))
						(e-lookup-local @1.39-1.44
							(p-assign @1.10-1.15 (ident "inner"))))))
			(if-else
				(e-lookup-local @1.51-1.56
					(p-assign @1.10-1.15 (ident "inner")))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.56 (type "Num(_size) -> Num(_size2) -> Num(_size3)"))
~~~
