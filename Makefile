.PHONY: test

test:
	./rebar eunit skip_deps=true
