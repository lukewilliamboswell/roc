platform ""
	requires { main! : () => {} }
	exposes [NameCollisions]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted {
		"roc_keyword_tag": NameCollisions.keyword_tag!,
		"roc_first_scope": NameCollisions.first_scope!,
		"roc_second_scope": NameCollisions.second_scope!,
	}
	targets: {
		inputs_dir: "targets/",
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"], output: Exe },
	}

import NameCollisions

main_for_host! : () => {}
main_for_host! = || main!()
