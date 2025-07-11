# META
~~~ini
description=An empty module with a singleline exposes with trailing comma
type=file
~~~
# SOURCE
~~~roc
module [something, SomeType,]
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),LowerIdent(1:9-1:18),Comma(1:18-1:19),UpperIdent(1:20-1:28),Comma(1:28-1:29),CloseSquare(1:29-1:30),EndOfFile(1:30-1:30),
~~~
# PARSE
~~~clojure
(file @1.1-1.30
	(module @1.1-1.30
		(exposes @1.8-1.30
			(exposed-lower-ident (text "something"))
			(exposed-upper-ident (text "SomeType"))))
	(statements))
~~~
# FORMATTED
~~~roc
module [
	something,
	SomeType,
]
~~~
# CANONICALIZE
~~~clojure
(can-ir (empty true))
~~~
# TYPES
~~~clojure
(inferred-types
	(defs)
	(expressions))
~~~
