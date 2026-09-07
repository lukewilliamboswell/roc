## Tag shapes whose generated Zig names collide with the output language.
##
## Nothing here is about layout. Each declaration exists because naming it in
## Zig is where the generator can go wrong, and the only assertion is that the
## file `roc glue` writes is a Zig file that compiles.
NameCollisions := [].{

	## A payload-free tag that is a Zig keyword once lowered to snake_case.
	##
	## `Unreachable` becomes the enum member `unreachable`, which Zig will not
	## parse. Every Zig keyword a Roc tag can spell has this problem; this one
	## is a tag an ordinary networking error union really does use.
	keyword_tag! : U8 => Try({}, [TooLarge, Unreachable])

	## Two effects that share one closed union whose variants carry nothing.
	##
	## The second is generated as an alias of the first. When every variant is
	## payload-free the union is emitted as a bare enum with no `Payload` or
	## `Tag` type beside it, so those two aliases must not be emitted either.
	first_scope! : U8 => Try({}, [ScopeLimit])
	second_scope! : U8 => Try({}, [ScopeLimit])
}
